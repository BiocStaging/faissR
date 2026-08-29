#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
  }
  out
}

shape_group <- function(n, p) {
  if (p <= 3L) return("spatial_2d3d")
  if (n < 20000L && p <= 128L) return("small_low_dim")
  if (n < 20000L) return("small_high_dim")
  if (n < 200000L && p <= 128L) return("medium_low_dim")
  if (n < 200000L) return("medium_high_dim")
  if (p <= 128L) "large_low_dim" else "large_high_dim"
}

method_family <- function(x) sub("^faissR_(cpu|cuda)_", "", as.character(x))

route_family <- function(public_method = NA_character_, method_id = NA_character_,
                         result_backend = NA_character_) {
  n <- max(length(public_method), length(method_id), length(result_backend))
  public_method <- rep_len(tolower(as.character(public_method)), n)
  method_id <- rep_len(tolower(as.character(method_id)), n)
  result_backend <- rep_len(tolower(as.character(result_backend)), n)
  vapply(seq_len(n), function(i) {
    public <- public_method[[i]]
    if (!is.na(public) && nzchar(public) && public != "auto") {
      if (public %in% c("exact", "flat", "bruteforce")) return("exact_family")
      if (public %in% c(
        "ivfpq_fastscan", "nndescent", "cagra", "hnsw", "ivfpq", "ivf",
        "vamana", "nsg", "grid"
      )) return(public)
    }
    item <- paste(method_id[[i]], result_backend[[i]])
    if (grepl("ivfpq[_-]?fastscan|ivf[_-]?pq[_-]?fastscan", item)) return("ivfpq_fastscan")
    if (grepl("nndescent|nn[_-]?descent", item)) return("nndescent")
    if (grepl("cagra", item)) return("cagra")
    if (grepl("hnsw", item)) return("hnsw")
    if (grepl("ivfpq|ivf[_-]?pq", item)) return("ivfpq")
    if (grepl("ivf", item)) return("ivf")
    if (grepl("bruteforce|brute[_-]?force|exact|flat", item)) return("exact_family")
    if (grepl("vamana", item)) return("vamana")
    if (grepl("nsg", item)) return("nsg")
    if (grepl("grid", item)) return("grid")
    NA_character_
  }, character(1L), USE.NAMES = FALSE)
}

logical_column <- function(x, name, default = FALSE) {
  if (!name %in% names(x)) return(rep(default, nrow(x)))
  out <- suppressWarnings(as.logical(x[[name]]))
  out[is.na(out)] <- default
  out
}

eligible_rows <- function(x) {
  if (!nrow(x)) return(logical())
  if ("selection_eligible" %in% names(x)) {
    return(logical_column(x, "selection_eligible"))
  }
  logical_column(x, "complete_validation") & logical_column(x, "target_met_all_runs")
}

is_exact_audited <- function(x) logical_column(x, "exact_audited")

approximate_target_met <- function(x) {
  if (!nrow(x)) return(logical())
  if ("approximate_target_met" %in% names(x)) {
    out <- suppressWarnings(as.logical(x$approximate_target_met))
    out[is_exact_audited(x)] <- NA
    return(out)
  }
  out <- logical_column(x, "target_met_all_runs")
  out[is_exact_audited(x)] <- NA
  out
}

choose_training_method <- function(train, test_n, test_p) {
  explicit <- train$implementation == "faissR" &
    tolower(as.character(train$public_method)) != "auto" &
    !grepl("_auto$", train$method_id)
  explicit[is.na(explicit)] <- FALSE
  train <- train[explicit & eligible_rows(train) & is.finite(train$median_time_sec), , drop = FALSE]
  if (!nrow(train)) return(list(method = NA_character_, basis = "no_qualifying_training_method"))
  target_shape <- shape_group(test_n, test_p)
  same <- train[train$shape_group == target_shape, , drop = FALSE]
  basis <- "same_shape_group"
  if (!nrow(same)) {
    train$shape_distance <- sqrt(
      (log10(pmax(train$n, 1)) - log10(test_n))^2 +
        (log10(pmax(train$p, 1)) - log10(test_p))^2
    )
    nearest <- unique(train$dataset[order(train$shape_distance)])
    nearest <- nearest[seq_len(min(3L, length(nearest)))]
    same <- train[train$dataset %in% nearest, , drop = FALSE]
    basis <- "three_nearest_training_shapes"
  }
  same$family <- method_family(same$method_id)
  score <- do.call(rbind, lapply(split(same, same$family), function(part) {
    per_dataset <- aggregate(median_time_sec ~ dataset, part, median)
    data.frame(
      family = part$family[[1L]],
      n_training_datasets = nrow(per_dataset),
      median_log_time = median(log(pmax(per_dataset$median_time_sec, 1e-9))),
      worst_log_time = max(log(pmax(per_dataset$median_time_sec, 1e-9))),
      stringsAsFactors = FALSE
    )
  }))
  score <- score[order(-score$n_training_datasets, score$median_log_time,
                       score$worst_log_time, score$family), , drop = FALSE]
  best_coverage <- max(score$n_training_datasets)
  score <- score[score$n_training_datasets == best_coverage, , drop = FALSE]
  list(
    method = score$family[[1L]], basis = basis,
    n_training_datasets = score$n_training_datasets[[1L]],
    median_training_time_sec = exp(score$median_log_time[[1L]])
  )
}

first_by_time <- function(x) {
  if (!nrow(x)) return(x)
  complete <- logical_column(x, "complete_validation")
  order_time <- suppressWarnings(as.numeric(x$median_time_sec))
  order_time[!is.finite(order_time)] <- Inf
  x[order(!complete, order_time, x$method_id, na.last = TRUE), , drop = FALSE][1L, , drop = FALSE]
}

safe_fraction <- function(numerator, denominator) {
  if (!is.finite(denominator) || denominator <= 0) NA_real_ else numerator / denominator
}

summarize_loodo <- function(part, keys) {
  crossfit_evaluable <- !part$crossfit_abstained & is.finite(part$crossfit_time_sec)
  crossfit_agreement_evaluable <- crossfit_evaluable &
    !is.na(part$crossfit_method_agreement)
  package_evaluable <- !part$package_auto_abstained & is.finite(part$package_auto_time_sec)
  package_agreement_evaluable <- package_evaluable &
    !is.na(part$package_auto_method_agreement)
  crossfit_ratios <- part$crossfit_over_oracle[is.finite(part$crossfit_over_oracle)]
  package_ratios <- part$package_auto_over_oracle[is.finite(part$package_auto_over_oracle)]
  data.frame(
    part[1L, keys, drop = FALSE],
    n_cells = nrow(part),
    n_crossfit_evaluable = sum(crossfit_evaluable),
    n_crossfit_operating_point_met = sum(part$crossfit_operating_point_met),
    crossfit_operating_point_attainment_fraction = mean(part$crossfit_operating_point_met),
    n_crossfit_abstained = sum(part$crossfit_abstained),
    crossfit_abstention_fraction = mean(part$crossfit_abstained),
    n_crossfit_exact_selected = sum(part$crossfit_exact_selected),
    crossfit_exact_selection_fraction = safe_fraction(
      sum(part$crossfit_exact_selected), sum(crossfit_evaluable)
    ),
    n_crossfit_method_agreement = sum(part$crossfit_method_agreement, na.rm = TRUE),
    crossfit_method_agreement_fraction = safe_fraction(
      sum(part$crossfit_method_agreement, na.rm = TRUE),
      sum(crossfit_agreement_evaluable)
    ),
    median_crossfit_over_oracle = if (length(crossfit_ratios)) median(crossfit_ratios) else NA_real_,
    p90_crossfit_over_oracle = if (length(crossfit_ratios)) {
      unname(quantile(crossfit_ratios, 0.9))
    } else NA_real_,
    n_package_auto_evaluable = sum(package_evaluable),
    n_package_auto_operating_point_met = sum(part$package_auto_operating_point_met),
    package_auto_operating_point_attainment_fraction = mean(part$package_auto_operating_point_met),
    n_package_auto_abstained = sum(part$package_auto_abstained),
    package_auto_abstention_fraction = mean(part$package_auto_abstained),
    n_package_auto_exact_selected = sum(part$package_auto_exact_selected),
    package_auto_exact_selection_fraction = safe_fraction(
      sum(part$package_auto_exact_selected), sum(package_evaluable)
    ),
    n_package_auto_method_agreement = sum(part$package_auto_method_agreement, na.rm = TRUE),
    package_auto_method_agreement_fraction = safe_fraction(
      sum(part$package_auto_method_agreement, na.rm = TRUE),
      sum(package_agreement_evaluable)
    ),
    median_package_auto_over_oracle = if (length(package_ratios)) median(package_ratios) else NA_real_,
    p90_package_auto_over_oracle = if (length(package_ratios)) {
      unname(quantile(package_ratios, 0.9))
    } else NA_real_,
    stringsAsFactors = FALSE
  )
}

main <- function() {
  args <- parse_args()
  analysis_dir <- normalizePath(args$analysis_dir %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(analysis_dir, "leave_one_dataset_out"), mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  robust_path <- file.path(analysis_dir, "jss_robust_method_summary.csv")
  combined_path <- file.path(analysis_dir, "jss_publication_results_combined.csv")
  if (!file.exists(robust_path) || !file.exists(combined_path)) {
    stop("Run aggregate_publication_results.R first; robust and combined CSV files are required.", call. = FALSE)
  }
  evidence <- read.csv(robust_path, stringsAsFactors = FALSE, check.names = FALSE)
  combined <- read.csv(combined_path, stringsAsFactors = FALSE, check.names = FALSE)
  backend <- tolower(args$backend %||% "cuda")
  if (!backend %in% c("cpu", "cuda", "all")) {
    stop("--backend must be cpu, cuda, or all.", call. = FALSE)
  }
  if (backend != "all") {
    evidence <- evidence[evidence$backend == backend, , drop = FALSE]
    combined <- combined[combined$backend == backend, , drop = FALSE]
  }
  metrics <- strsplit(args$metrics %||% "", ",", fixed = TRUE)[[1L]]
  metrics <- trimws(metrics[nzchar(trimws(metrics))])
  if (length(metrics)) {
    evidence <- evidence[evidence$metric %in% metrics, , drop = FALSE]
    combined <- combined[combined$metric %in% metrics, , drop = FALSE]
  }
  if (!nrow(evidence) || !nrow(combined)) {
    stop("No evidence remains after applying the requested metric filter.", call. = FALSE)
  }
  dims <- unique(combined[, c("dataset", "dataset_md5", "n", "p"), drop = FALSE])
  evidence <- merge(evidence, dims, by = c("dataset", "dataset_md5"), all.x = TRUE)
  evidence$shape_group <- mapply(shape_group, evidence$n, evidence$p, USE.NAMES = FALSE)

  cells <- unique(evidence[, c(
    "dataset", "dataset_md5", "backend", "metric", "k", "target_recall",
    "n", "p", "shape_group"
  ), drop = FALSE])
  rows <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    cell <- cells[i, , drop = FALSE]
    same_cell <- function(x) {
      x$backend == cell$backend & x$metric == cell$metric & x$k == cell$k &
        abs(x$target_recall - cell$target_recall) < 1e-12
    }
    train <- evidence[evidence$dataset != cell$dataset & same_cell(evidence), , drop = FALSE]
    selected <- choose_training_method(train, cell$n, cell$p)
    test <- evidence[evidence$dataset == cell$dataset & same_cell(evidence), , drop = FALSE]
    is_auto <- test$implementation == "faissR" &
      (tolower(test$public_method) == "auto" | grepl("_auto$", test$method_id))
    is_auto[is.na(is_auto)] <- FALSE
    explicit <- test[test$implementation == "faissR" & !is_auto, , drop = FALSE]

    qualifying <- explicit[eligible_rows(explicit) & is.finite(explicit$median_time_sec), , drop = FALSE]
    qualifying <- qualifying[order(qualifying$median_time_sec, qualifying$method_id), , drop = FALSE]
    oracle <- if (nrow(qualifying)) qualifying[1L, , drop = FALSE] else qualifying
    oracle_time <- if (nrow(oracle)) oracle$median_time_sec[[1L]] else NA_real_
    oracle_route <- if (nrow(oracle)) {
      route_family(oracle$public_method, oracle$method_id, oracle$result_backend)[[1L]]
    } else NA_character_

    selected_candidates <- explicit[method_family(explicit$method_id) == selected$method, , drop = FALSE]
    selected_test <- first_by_time(selected_candidates)
    crossfit_evaluable <- nrow(selected_test) &&
      logical_column(selected_test, "complete_validation")[[1L]] &&
      is.finite(selected_test$median_time_sec[[1L]])
    crossfit_eligible <- crossfit_evaluable && eligible_rows(selected_test)[[1L]]
    crossfit_exact <- crossfit_evaluable && is_exact_audited(selected_test)[[1L]]
    crossfit_approx <- if (crossfit_exact || !crossfit_evaluable) NA else {
      approximate_target_met(selected_test)[[1L]]
    }
    crossfit_time <- if (nrow(selected_test)) selected_test$median_time_sec[[1L]] else NA_real_
    crossfit_route <- if (nrow(selected_test)) {
      route_family(selected_test$public_method, selected_test$method_id,
                   selected_test$result_backend)[[1L]]
    } else NA_character_
    crossfit_abstained <- is.na(selected$method) || !nrow(selected_test) || !crossfit_evaluable

    package_auto <- first_by_time(test[is_auto, , drop = FALSE])
    package_evaluable <- nrow(package_auto) &&
      logical_column(package_auto, "complete_validation")[[1L]] &&
      is.finite(package_auto$median_time_sec[[1L]])
    package_eligible <- package_evaluable && eligible_rows(package_auto)[[1L]]
    package_exact <- package_evaluable && is_exact_audited(package_auto)[[1L]]
    package_approx <- if (package_exact || !package_evaluable) NA else {
      approximate_target_met(package_auto)[[1L]]
    }
    package_time <- if (nrow(package_auto)) package_auto$median_time_sec[[1L]] else NA_real_
    package_route <- if (nrow(package_auto)) {
      route_family(package_auto$public_method, package_auto$method_id,
                   package_auto$result_backend)[[1L]]
    } else NA_character_
    package_abstained <- !nrow(package_auto) || !package_evaluable || is.na(package_route)

    rows[[i]] <- data.frame(
      cell,
      crossfit_selected_family = selected$method %||% NA_character_,
      crossfit_selection_basis = selected$basis %||% NA_character_,
      crossfit_n_training_datasets = selected$n_training_datasets %||% 0L,
      crossfit_median_training_time_sec = selected$median_training_time_sec %||% NA_real_,
      crossfit_test_method = if (nrow(selected_test)) selected_test$method_id[[1L]] else NA_character_,
      crossfit_resolved_route_family = crossfit_route,
      crossfit_time_sec = crossfit_time,
      crossfit_min_run_mean_query_recall_at_k = if (nrow(selected_test)) {
        if ("min_run_mean_query_recall_at_k" %in% names(selected_test)) {
          selected_test$min_run_mean_query_recall_at_k[[1L]]
        } else selected_test$min_recall_at_k[[1L]]
      } else NA_real_,
      crossfit_exact_selected = isTRUE(crossfit_exact),
      crossfit_approximate_target_met = if (length(crossfit_approx)) crossfit_approx else NA,
      crossfit_operating_point_met = isTRUE(crossfit_eligible),
      crossfit_method_agreement = if (!is.na(crossfit_route) && !is.na(oracle_route)) {
        crossfit_route == oracle_route
      } else NA,
      crossfit_abstained = isTRUE(crossfit_abstained),
      crossfit_over_oracle = if (isTRUE(crossfit_eligible) && is.finite(oracle_time) && oracle_time > 0) {
        crossfit_time / oracle_time
      } else NA_real_,
      package_auto_method = if (nrow(package_auto)) package_auto$method_id[[1L]] else NA_character_,
      package_auto_resolved_backend = if (nrow(package_auto)) package_auto$result_backend[[1L]] else NA_character_,
      package_auto_resolved_route_family = package_route,
      package_auto_time_sec = package_time,
      package_auto_exact_selected = isTRUE(package_exact),
      package_auto_approximate_target_met = if (length(package_approx)) package_approx else NA,
      package_auto_operating_point_met = isTRUE(package_eligible),
      package_auto_method_agreement = if (!is.na(package_route) && !is.na(oracle_route)) {
        package_route == oracle_route
      } else NA,
      package_auto_abstained = isTRUE(package_abstained),
      package_auto_over_oracle = if (isTRUE(package_eligible) && is.finite(oracle_time) && oracle_time > 0) {
        package_time / oracle_time
      } else NA_real_,
      oracle_method = if (nrow(oracle)) oracle$method_id[[1L]] else NA_character_,
      oracle_resolved_route_family = oracle_route,
      oracle_time_sec = oracle_time,
      oracle_exact_audited = if (nrow(oracle)) is_exact_audited(oracle)[[1L]] else NA,
      stringsAsFactors = FALSE
    )
  }
  result <- do.call(rbind, rows)
  write.csv(result, file.path(out_dir, "jss_leave_one_dataset_out.csv"), row.names = FALSE)

  summary_keys <- c("backend", "metric", "target_recall")
  grouping <- interaction(result[summary_keys], drop = TRUE, lex.order = TRUE)
  report <- do.call(rbind, lapply(split(result, grouping), summarize_loodo, keys = summary_keys))
  write.csv(report, file.path(out_dir, "jss_leave_one_dataset_out_summary.csv"), row.names = FALSE)

  dataset_keys <- c("dataset", "dataset_md5", "backend")
  dataset_grouping <- interaction(result[dataset_keys], drop = TRUE, lex.order = TRUE)
  by_dataset <- do.call(rbind, lapply(
    split(result, dataset_grouping), summarize_loodo, keys = dataset_keys
  ))
  write.csv(by_dataset, file.path(out_dir, "jss_leave_one_dataset_out_by_dataset.csv"), row.names = FALSE)

  writeLines(c(
    "# Leave-one-dataset-out selector sensitivity", "",
    "For each held-out dataset and backend/metric/k/target cell, the cross-fitted analysis excludes every row from that named dataset before selecting a method family. It first uses the same predeclared shape group; when that group is absent, it uses the three nearest training datasets in log(n)-log(p) space. It maximizes complete qualifying dataset coverage and then minimizes median log runtime.", "",
    "A cross-fitted operating point passes when the held-out route is complete and is either exact-audited or, for an approximate route, its mean query recall@k meets the requested threshold in every prespecified validation replicate. Exact selection and approximate target attainment are reported separately. Minimum query recall is not used for eligibility.", "",
    "The installed package `method = \"auto\"` result is reported separately as a non-independent diagnostic because its compiled policy summarizes the full calibration collection. It is not presented as leave-one-dataset-out evidence.", "",
    paste0("Held-out cells: ", nrow(result), "."),
    paste0("Cross-fitted operating points attained: ", sum(result$crossfit_operating_point_met), "."),
    paste0("Cross-fitted abstentions: ", sum(result$crossfit_abstained), "."),
    paste0("Cross-fitted exact selections: ", sum(result$crossfit_exact_selected), "."),
    paste0("Cross-fitted method-family agreements with the held-out empirical oracle: ",
           sum(result$crossfit_method_agreement, na.rm = TRUE), ".")
  ), file.path(out_dir, "JSS_LEAVE_ONE_DATASET_OUT_REPORT.md"))
}

if (!identical(Sys.getenv("FAISSR_JSS_LOODO_SOURCE_ONLY"), "true")) main()
