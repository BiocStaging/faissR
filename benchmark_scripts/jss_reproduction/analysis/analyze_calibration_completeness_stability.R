#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list(
    calibration_root = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/final_campaign/calibration/real",
    calibration_audit_dir = "",
    held_out_root = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/final_campaign/held_out",
    out_dir = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/final_campaign/analysis/calibration_stability"
  )
  for (arg in x) {
    if (startsWith(arg, "--calibration_root=")) {
      out$calibration_root <- sub("^--calibration_root=", "", arg)
    } else if (startsWith(arg, "--calibration_audit_dir=")) {
      out$calibration_audit_dir <- sub("^--calibration_audit_dir=", "", arg)
    } else if (startsWith(arg, "--held_out_root=")) {
      out$held_out_root <- sub("^--held_out_root=", "", arg)
    } else if (startsWith(arg, "--out_dir=")) {
      out$out_dir <- sub("^--out_dir=", "", arg)
    } else {
      stop("Unknown argument: ", arg, call. = FALSE)
    }
  }
  out
}

num <- function(x) suppressWarnings(as.numeric(x))

logical_value <- function(x) {
  tolower(as.character(x)) %in% c("true", "t", "1")
}

median_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}

quantile_or_na <- function(x, probability) {
  x <- x[is.finite(x)]
  if (length(x)) unname(stats::quantile(x, probability, names = FALSE)) else NA_real_
}

group_indices <- function(x, columns) {
  split(seq_len(nrow(x)), interaction(x[columns], drop = TRUE, lex.order = TRUE))
}

bind_rows <- function(values) {
  columns <- unique(unlist(lapply(values, names), use.names = FALSE))
  values <- lapply(values, function(value) {
    for (name in setdiff(columns, names(value))) value[[name]] <- NA
    value[, columns, drop = FALSE]
  })
  do.call(rbind, values)
}

find_audit_dir <- function(path) {
  if (nzchar(path)) return(normalizePath(path, mustWork = TRUE))
  stop("Supply --calibration_audit_dir with the directory containing the calibration audit CSV files.",
       call. = FALSE)
}

read_route <- function(root, backend, route) {
  path <- file.path(root, backend, route)
  files <- list.files(
    path, pattern = "^jmlr_tuned_benchmark_results[.]csv$",
    recursive = TRUE, full.names = TRUE
  )
  if (!length(files)) stop("No held-out result files under ", path, call. = FALSE)
  values <- lapply(files, utils::read.csv, stringsAsFactors = FALSE, check.names = FALSE)
  x <- bind_rows(values)
  x <- x[x$metric %in% c("euclidean", "cosine", "correlation"), , drop = FALSE]
  if ("dataset_suite" %in% names(x)) {
    x <- x[is.na(x$dataset_suite) | x$dataset_suite == "real", , drop = FALSE]
  }
  keys <- c("dataset", "metric", "k", "target_recall", "validation_seed", "repeat_id")
  key <- interaction(lapply(x[keys], function(z) {
    z <- as.character(z)
    z[is.na(z)] <- "<NA>"
    z
  }), drop = TRUE, lex.order = TRUE)
  x[!duplicated(key, fromLast = TRUE), , drop = FALSE]
}

summarize_margin <- function(x, scope) {
  data.frame(
    scope = scope,
    operating_points = nrow(x),
    median_relative_margin = median_or_na(x$relative_margin),
    q1_relative_margin = quantile_or_na(x$relative_margin, 0.25),
    q3_relative_margin = quantile_or_na(x$relative_margin, 0.75),
    second_within_1_percent = mean(x$relative_margin <= 0.01),
    second_within_5_percent = mean(x$relative_margin <= 0.05),
    second_within_10_percent = mean(x$relative_margin <= 0.10),
    stringsAsFactors = FALSE
  )
}

summarize_validation <- function(x, backend, route) {
  data.frame(
    backend = backend,
    route = route,
    operating_points = nrow(x),
    validation_target_met = sum(x$validation_target_met),
    median_recall_change = median_or_na(x$recall_change),
    q1_recall_change = quantile_or_na(x$recall_change, 0.25),
    q3_recall_change = quantile_or_na(x$recall_change, 0.75),
    min_recall_change = min(x$recall_change, na.rm = TRUE),
    max_recall_change = max(x$recall_change, na.rm = TRUE),
    median_validation_over_calibration_time = median_or_na(x$time_ratio),
    q1_validation_over_calibration_time = quantile_or_na(x$time_ratio, 0.25),
    q3_validation_over_calibration_time = quantile_or_na(x$time_ratio, 0.75),
    stringsAsFactors = FALSE
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
audit_dir <- find_audit_dir(args$calibration_audit_dir)

recommendations <- utils::read.csv(
  file.path(audit_dir, "jss_calibration_recommendations.csv"),
  stringsAsFactors = FALSE, check.names = FALSE
)
missing <- utils::read.csv(
  file.path(audit_dir, "jss_calibration_missing_cells.csv"),
  stringsAsFactors = FALSE, check.names = FALSE
)
public_metrics <- c("euclidean", "cosine", "correlation")
recommendations <- recommendations[recommendations$metric %in% public_metrics, , drop = FALSE]
missing <- missing[missing$metric %in% public_metrics, , drop = FALSE]

raw_files <- list.files(
  args$calibration_root, pattern = "_tuning_results[.]csv$",
  recursive = TRUE, full.names = TRUE
)
if (!length(raw_files)) stop("No raw calibration result files were found.", call. = FALSE)
raw <- bind_rows(lapply(raw_files, function(path) {
  value <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  value$raw_source_file <- normalizePath(path, mustWork = TRUE)
  value
}))
raw <- raw[raw$metric %in% public_metrics, , drop = FALSE]

raw_key_columns <- c("backend", "method", "dataset", "metric", "k", "candidate_id")
successful_raw <- raw[raw$status == "success", , drop = FALSE]
raw_key <- interaction(lapply(successful_raw[raw_key_columns], as.character),
                       drop = TRUE, lex.order = TRUE)
max_candidate_repeats <- max(tabulate(raw_key))
replicate_stability_estimable <- max_candidate_repeats > 1L

failure_reason <- character(nrow(missing))
for (i in seq_len(nrow(missing))) {
  z <- raw[
    raw$backend == missing$backend[[i]] &
      raw$method == missing$method[[i]] &
      raw$dataset == missing$dataset[[i]] &
      raw$metric == missing$metric[[i]] &
      num(raw$k) == num(missing$k[[i]]),
    , drop = FALSE
  ]
  if (!nrow(z)) {
    failure_reason[[i]] <- "no_candidate_records"
    next
  }
  diagnostic <- paste(tolower(as.character(z$status)),
                      tolower(as.character(z$error)))
  if (any(grepl("out[_ ]?of[_ ]?memory|oom|killed|bad_alloc|cuda.*memory", diagnostic))) {
    failure_reason[[i]] <- "out_of_memory_or_killed"
  } else if (any(grepl("timeout|time limit", diagnostic))) {
    failure_reason[[i]] <- "timeout"
  } else {
    failure_reason[[i]] <- "execution_or_incomplete_grid"
  }
}
missing$failure_reason <- failure_reason

summarize_count <- function(columns) {
  out <- stats::aggregate(
    rep.int(1L, nrow(missing)), missing[columns], sum
  )
  names(out)[[ncol(out)]] <- "unavailable_operating_points"
  out[do.call(order, unname(out[columns])), , drop = FALSE]
}

missing_backend_method <- summarize_count(c("backend", "method", "failure_reason"))
missing_metric <- summarize_count(c("backend", "metric", "failure_reason"))
missing_dataset <- summarize_count(c("backend", "dataset", "failure_reason"))
missing_full <- summarize_count(
  c("backend", "method", "metric", "dataset", "failure_reason")
)

targets <- sort(unique(num(recommendations$target_recall_threshold)))
config_rows <- list()
row_index <- 0L
for (target in targets) {
  eligible <- raw$status == "success" & is.finite(num(raw$elapsed_sec)) &
    (logical_value(raw$exact) | num(raw$recall_at_k) >= target - 1e-12)
  value <- raw[eligible, , drop = FALSE]
  groups <- group_indices(value, c("backend", "method", "dataset", "metric", "k"))
  for (indices in groups) {
    z <- value[indices, , drop = FALSE]
    z <- z[order(num(z$elapsed_sec), -num(z$recall_at_k), as.character(z$candidate_id)),
           , drop = FALSE]
    if (nrow(z) < 2L) next
    row_index <- row_index + 1L
    config_rows[[row_index]] <- data.frame(
      backend = z$backend[[1L]], method = z$method[[1L]],
      dataset = z$dataset[[1L]], metric = z$metric[[1L]], k = z$k[[1L]],
      target_recall = target, best_candidate = z$candidate_id[[1L]],
      second_candidate = z$candidate_id[[2L]],
      relative_margin = num(z$elapsed_sec[[2L]]) / num(z$elapsed_sec[[1L]]) - 1,
      stringsAsFactors = FALSE
    )
  }
}
config_margins <- do.call(rbind, config_rows)
config_margin_summary <- rbind(
  summarize_margin(config_margins, "all"),
  do.call(rbind, lapply(split(config_margins, config_margins$backend), function(z) {
    summarize_margin(z, unique(z$backend))
  }))
)

eligible_recommendations <- logical_value(recommendations$target_met) |
  recommendations$method %in% c("exact", "flat", "bruteforce", "grid")
families <- recommendations[eligible_recommendations & is.finite(num(recommendations$elapsed_sec)),
                            , drop = FALSE]
families$family <- as.character(families$method)
families$family[families$family %in% c("exact", "flat", "bruteforce")] <- "exact_family"
family_keys <- c("backend", "dataset", "metric", "k", "target_recall_threshold", "family")
family_groups <- group_indices(families, family_keys)
family_best <- do.call(rbind, lapply(family_groups, function(indices) {
  z <- families[indices, , drop = FALSE]
  z[which.min(num(z$elapsed_sec)), , drop = FALSE]
}))
family_rows <- list()
row_index <- 0L
for (indices in group_indices(
  family_best, c("backend", "dataset", "metric", "k", "target_recall_threshold")
)) {
  z <- family_best[indices, , drop = FALSE]
  z <- z[order(num(z$elapsed_sec), as.character(z$family)), , drop = FALSE]
  if (nrow(z) < 2L) next
  row_index <- row_index + 1L
  family_rows[[row_index]] <- data.frame(
    backend = z$backend[[1L]], dataset = z$dataset[[1L]], metric = z$metric[[1L]],
    k = z$k[[1L]], target_recall = z$target_recall_threshold[[1L]],
    best_family = z$family[[1L]], second_family = z$family[[2L]],
    relative_margin = num(z$elapsed_sec[[2L]]) / num(z$elapsed_sec[[1L]]) - 1,
    stringsAsFactors = FALSE
  )
}
family_margins <- do.call(rbind, family_rows)
family_margin_summary <- rbind(
  summarize_margin(family_margins, "all"),
  do.call(rbind, lapply(split(family_margins, family_margins$backend), function(z) {
    summarize_margin(z, unique(z$backend))
  }))
)

cell_summary <- function(x, selected_method = NULL) {
  rows <- lapply(group_indices(x, c("dataset", "metric", "k", "target_recall")), function(indices) {
    z <- x[indices, , drop = FALSE]
    selected <- if (is.null(selected_method)) NA_character_ else selected_method(z)
    target <- num(z$target_recall[[1L]])
    data.frame(
      dataset = z$dataset[[1L]], metric = z$metric[[1L]], k = z$k[[1L]],
      target_recall_threshold = target,
      selected_method = selected,
      validation_recall = mean(num(z$recall_at_k), na.rm = TRUE),
      validation_time = median(num(z$time_sec), na.rm = TRUE),
      validation_target_met = all(z$status == "success") &&
        all(num(z$recall_at_k) >= target - 1e-12),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

cpu_held <- read_route(args$held_out_root, "cpu", "faissR_hnsw")
cpu_cells <- cell_summary(cpu_held)
cpu_cal <- recommendations[
  recommendations$backend == "cpu" & recommendations$method == "hnsw",
  c("dataset", "metric", "k", "target_recall_threshold", "recall_at_k", "elapsed_sec"),
  drop = FALSE
]
cpu_join <- merge(cpu_cells, cpu_cal,
                  by = c("dataset", "metric", "k", "target_recall_threshold"))
cpu_join$recall_change <- cpu_join$validation_recall - num(cpu_join$recall_at_k)
cpu_join$time_ratio <- cpu_join$validation_time / num(cpu_join$elapsed_sec)

cuda_held <- read_route(args$held_out_root, "cuda", "faissR_auto")
cuda_cells <- cell_summary(cuda_held, function(z) {
  values <- unique(tolower(as.character(z$auto_predicted_method)))
  values <- values[!is.na(values) & nzchar(values)]
  if (length(values) == 1L) values else "mixed"
})
cuda_cells$validation_target_met <- cuda_cells$validation_target_met |
  cuda_cells$selected_method == "flat"
cuda_cal <- recommendations[recommendations$backend == "cuda",
  c("dataset", "metric", "k", "target_recall_threshold", "method", "recall_at_k", "elapsed_sec"),
  drop = FALSE
]
cuda_join <- merge(
  cuda_cells, cuda_cal,
  by.x = c("dataset", "metric", "k", "target_recall_threshold", "selected_method"),
  by.y = c("dataset", "metric", "k", "target_recall_threshold", "method")
)
cuda_join$recall_change <- cuda_join$validation_recall - num(cuda_join$recall_at_k)
cuda_join$time_ratio <- cuda_join$validation_time / num(cuda_join$elapsed_sec)

validation_summary <- rbind(
  summarize_validation(cpu_join, "cpu", "hnsw"),
  summarize_validation(cuda_join, "cuda", "auto_all"),
  summarize_validation(cuda_join[cuda_join$selected_method == "flat", , drop = FALSE],
                       "cuda", "auto_flat"),
  summarize_validation(cuda_join[cuda_join$selected_method == "ivf", , drop = FALSE],
                       "cuda", "auto_ivf")
)

utils::write.csv(missing, file.path(args$out_dir, "jss_calibration_missing_cells_with_reasons.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(missing_backend_method,
                 file.path(args$out_dir, "jss_calibration_missing_by_backend_method_reason.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(missing_metric,
                 file.path(args$out_dir, "jss_calibration_missing_by_backend_metric_reason.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(missing_dataset,
                 file.path(args$out_dir, "jss_calibration_missing_by_backend_dataset_reason.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(missing_full,
                 file.path(args$out_dir, "jss_calibration_missing_full_breakdown.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(config_margins,
                 file.path(args$out_dir, "jss_calibration_configuration_near_ties.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(config_margin_summary,
                 file.path(args$out_dir, "jss_calibration_configuration_near_tie_summary.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(family_margins,
                 file.path(args$out_dir, "jss_calibration_method_family_near_ties.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(family_margin_summary,
                 file.path(args$out_dir, "jss_calibration_method_family_near_tie_summary.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(validation_summary,
                 file.path(args$out_dir, "jss_calibration_to_validation_summary.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(cpu_join, file.path(args$out_dir, "jss_cpu_hnsw_calibration_validation_cells.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(cuda_join, file.path(args$out_dir, "jss_cuda_auto_calibration_validation_cells.csv"),
                 row.names = FALSE, na = "")

reason_counts <- stats::aggregate(
  rep.int(1L, nrow(missing)), list(failure_reason = missing$failure_reason), sum
)
names(reason_counts)[[2L]] <- "n"
writeLines(c(
  "# Calibration completeness and stability audit",
  "",
  paste0("Completed public-metric operating points: ", nrow(recommendations), "."),
  paste0("Unavailable public-metric operating points: ", nrow(missing), "."),
  paste0("Failure reasons: ", paste0(reason_counts$failure_reason, "=", reason_counts$n,
                                     collapse = ", "), "."),
  paste0("Maximum raw rows per candidate key: ", max_candidate_repeats, "."),
  paste0("Replicate winner-switch frequency estimable: ", replicate_stability_estimable, "."),
  "Candidate configurations were timed once; near-tie margins are a sensitivity diagnostic, not replicate stability.",
  sprintf("Configuration-level second-best within 5%%: %.1f%% overall, %.1f%% CPU, %.1f%% CUDA.",
          100 * config_margin_summary$second_within_5_percent[config_margin_summary$scope == "all"],
          100 * config_margin_summary$second_within_5_percent[config_margin_summary$scope == "cpu"],
          100 * config_margin_summary$second_within_5_percent[config_margin_summary$scope == "cuda"]),
  sprintf("Method-family second-best within 5%%: %.1f%% overall.",
          100 * family_margin_summary$second_within_5_percent[family_margin_summary$scope == "all"]),
  paste0("CPU HNSW calibration-to-validation cells: ", nrow(cpu_join), "."),
  paste0("CUDA auto calibration-to-validation cells: ", nrow(cuda_join), ".")
), file.path(args$out_dir, "JSS_CALIBRATION_COMPLETENESS_STABILITY_REPORT.md"))

cat("Calibration completeness and stability audit completed: ", args$out_dir, "\n", sep = "")
