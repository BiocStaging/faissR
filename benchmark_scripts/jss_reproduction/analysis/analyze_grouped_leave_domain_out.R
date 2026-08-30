#!/usr/bin/env Rscript

Sys.setenv(FAISSR_JSS_LOODO_SOURCE_ONLY = "true")
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else "analyze_grouped_leave_domain_out.R"
# Rscript can encode spaces in --file as ~+~ on some macOS builds.
script_path <- gsub("~+~", " ", script_path, fixed = TRUE)
source(file.path(dirname(normalizePath(script_path)), "analyze_leave_one_dataset_out.R"))

domain_for_dataset <- function(x) {
  groups <- c(
    COIL20 = "image_derived",
    FashionMNIST = "image_derived",
    imagenet = "image_derived",
    MNIST = "image_derived",
    USPS = "image_derived",
    flow18 = "cytometry",
    FlowRepository_FR.FCM.ZYRM_files = "cytometry",
    `FlowRepository_FR-FCM-ZYRM_files` = "cytometry",
    mass41 = "cytometry",
    MetRef = "metabolomics"
  )
  out <- unname(groups[as.character(x)])
  out[is.na(out)] <- "other"
  out
}

quantile_or_na <- function(x, probability) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  unname(stats::quantile(x, probability, names = FALSE))
}

summarize_domain <- function(part) {
  ratios <- part$crossfit_over_oracle[is.finite(part$crossfit_over_oracle)]
  data.frame(
    held_out_domain = part$held_out_domain[[1L]],
    n_datasets = length(unique(part$dataset)),
    n_cells = nrow(part),
    n_operating_points_met = sum(part$crossfit_operating_point_met),
    n_abstained = sum(part$crossfit_abstained),
    n_exact_selected = sum(part$crossfit_exact_selected),
    n_method_agreement = sum(part$crossfit_method_agreement, na.rm = TRUE),
    n_method_agreement_evaluable = sum(!is.na(part$crossfit_method_agreement)),
    median_over_oracle = if (length(ratios)) median(ratios) else NA_real_,
    p90_over_oracle = quantile_or_na(ratios, 0.90),
    p95_over_oracle = quantile_or_na(ratios, 0.95),
    maximum_over_oracle = if (length(ratios)) max(ratios) else NA_real_,
    stringsAsFactors = FALSE
  )
}

main_grouped <- function() {
  args <- parse_args()
  analysis_dir <- normalizePath(args$analysis_dir %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(
    args$out_dir %||% file.path(analysis_dir, "grouped_leave_domain_out"),
    mustWork = FALSE
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  evidence <- read.csv(
    file.path(analysis_dir, "jss_robust_method_summary.csv"),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  combined <- read.csv(
    file.path(analysis_dir, "jss_publication_results_combined.csv"),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  backend <- tolower(args$backend %||% "cuda")
  evidence <- evidence[evidence$backend == backend, , drop = FALSE]
  combined <- combined[combined$backend == backend, , drop = FALSE]
  metrics <- trimws(strsplit(args$metrics %||% "euclidean,cosine,correlation", ",")[[1L]])
  evidence <- evidence[evidence$metric %in% metrics, , drop = FALSE]
  combined <- combined[combined$metric %in% metrics, , drop = FALSE]

  dims <- unique(combined[, c("dataset", "dataset_md5", "n", "p"), drop = FALSE])
  evidence <- merge(evidence, dims, by = c("dataset", "dataset_md5"), all.x = TRUE)
  evidence$shape_group <- mapply(shape_group, evidence$n, evidence$p, USE.NAMES = FALSE)
  evidence$domain <- domain_for_dataset(evidence$dataset)
  if (any(evidence$domain == "other")) {
    stop("Assign every benchmark dataset to a prespecified domain before analysis.", call. = FALSE)
  }

  cells <- unique(evidence[, c(
    "dataset", "dataset_md5", "domain", "backend", "metric", "k",
    "target_recall", "n", "p", "shape_group"
  ), drop = FALSE])
  rows <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    cell <- cells[i, , drop = FALSE]
    same_cell <- evidence$backend == cell$backend & evidence$metric == cell$metric &
      evidence$k == cell$k & abs(evidence$target_recall - cell$target_recall) < 1e-12
    train <- evidence[evidence$domain != cell$domain & same_cell, , drop = FALSE]
    selected <- choose_training_method(train, cell$n, cell$p)
    test <- evidence[evidence$dataset == cell$dataset & same_cell, , drop = FALSE]
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
    evaluable <- nrow(selected_test) && logical_column(selected_test, "complete_validation")[[1L]] &&
      is.finite(selected_test$median_time_sec[[1L]])
    eligible <- evaluable && eligible_rows(selected_test)[[1L]]
    exact <- evaluable && is_exact_audited(selected_test)[[1L]]
    selected_time <- if (nrow(selected_test)) selected_test$median_time_sec[[1L]] else NA_real_
    selected_route <- if (nrow(selected_test)) {
      route_family(selected_test$public_method, selected_test$method_id,
                   selected_test$result_backend)[[1L]]
    } else NA_character_
    abstained <- is.na(selected$method) || !nrow(selected_test) || !evaluable

    rows[[i]] <- data.frame(
      held_out_domain = cell$domain,
      dataset = cell$dataset,
      backend = cell$backend,
      metric = cell$metric,
      k = cell$k,
      target_recall = cell$target_recall,
      n = cell$n,
      p = cell$p,
      crossfit_selected_family = selected$method %||% NA_character_,
      crossfit_selection_basis = selected$basis %||% NA_character_,
      crossfit_n_training_datasets = selected$n_training_datasets %||% 0L,
      crossfit_resolved_route_family = selected_route,
      crossfit_time_sec = selected_time,
      crossfit_exact_selected = isTRUE(exact),
      crossfit_operating_point_met = isTRUE(eligible),
      crossfit_abstained = isTRUE(abstained),
      oracle_resolved_route_family = oracle_route,
      oracle_time_sec = oracle_time,
      crossfit_method_agreement = if (!is.na(selected_route) && !is.na(oracle_route)) {
        selected_route == oracle_route
      } else NA,
      crossfit_over_oracle = if (isTRUE(eligible) && is.finite(oracle_time) && oracle_time > 0) {
        selected_time / oracle_time
      } else NA_real_,
      stringsAsFactors = FALSE
    )
  }

  result <- do.call(rbind, rows)
  write.csv(result, file.path(out_dir, "jss_grouped_leave_domain_out.csv"), row.names = FALSE)
  summary <- do.call(rbind, lapply(split(result, result$held_out_domain), summarize_domain))
  write.csv(summary, file.path(out_dir, "jss_grouped_leave_domain_out_summary.csv"), row.names = FALSE)

  writeLines(c(
    "# Grouped leave-one-domain-out sensitivity", "",
    "Prespecified groups: image-derived (COIL20, FashionMNIST, ImageNet features, MNIST, USPS), cytometry (flow18, FR-FCM-ZYRM, mass41), and metabolomics (MetRef). Every dataset in the held-out domain is excluded before method-family selection.", "",
    "This is a sensitivity reconstruction from the frozen explicit held-out routes. Its candidate universe contains exact-family routes and CAGRA, but not explicit IVF; it is not a like-for-like reconstruction of the compiled Flat/IVF policy.", "",
    paste0("Cells evaluated: ", nrow(result), "."),
    paste0("Operating points attained: ", sum(result$crossfit_operating_point_met), "."),
    paste0("Abstentions: ", sum(result$crossfit_abstained), ".")
  ), file.path(out_dir, "JSS_GROUPED_LEAVE_DOMAIN_OUT_REPORT.md"))
}

main_grouped()
