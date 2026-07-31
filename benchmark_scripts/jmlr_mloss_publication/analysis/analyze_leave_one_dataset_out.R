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

choose_training_method <- function(train, test_n, test_p) {
  train <- train[train$implementation == "faissR" & train$complete_validation & train$target_met_all_runs &
                   is.finite(train$median_time_sec) & !grepl("_auto$", train$method_id), , drop = FALSE]
  if (!nrow(train)) return(list(method = NA_character_, basis = "no_qualifying_training_method"))
  target_shape <- shape_group(test_n, test_p)
  same <- train[train$shape_group == target_shape, , drop = FALSE]
  basis <- "same_shape_group"
  if (!nrow(same)) {
    train$shape_distance <- sqrt(
      (log10(pmax(train$n, 1)) - log10(test_n))^2 +
        (log10(pmax(train$p, 1)) - log10(test_p))^2
    )
    nearest_datasets <- unique(train$dataset[order(train$shape_distance)])[seq_len(min(3L, length(unique(train$dataset))))]
    same <- train[train$dataset %in% nearest_datasets, , drop = FALSE]
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
  score <- score[order(-score$n_training_datasets, score$median_log_time, score$worst_log_time, score$family), , drop = FALSE]
  best_coverage <- max(score$n_training_datasets)
  score <- score[score$n_training_datasets == best_coverage, , drop = FALSE]
  list(method = score$family[[1L]], basis = basis,
       n_training_datasets = score$n_training_datasets[[1L]],
       median_training_time_sec = exp(score$median_log_time[[1L]]))
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
  summary <- read.csv(robust_path, stringsAsFactors = FALSE, check.names = FALSE)
  combined <- read.csv(combined_path, stringsAsFactors = FALSE, check.names = FALSE)
  dims <- unique(combined[, c("dataset", "dataset_md5", "n", "p"), drop = FALSE])
  summary <- merge(summary, dims, by = c("dataset", "dataset_md5"), all.x = TRUE)
  summary$shape_group <- mapply(shape_group, summary$n, summary$p, USE.NAMES = FALSE)

  cells <- unique(summary[, c("dataset", "dataset_md5", "backend", "metric", "k", "target_recall", "n", "p", "shape_group"), drop = FALSE])
  rows <- vector("list", nrow(cells))
  for (i in seq_len(nrow(cells))) {
    cell <- cells[i, , drop = FALSE]
    train <- summary[
      summary$dataset != cell$dataset & summary$backend == cell$backend &
        summary$metric == cell$metric & summary$k == cell$k &
        abs(summary$target_recall - cell$target_recall) < 1e-12,
      , drop = FALSE
    ]
    selected <- choose_training_method(train, cell$n, cell$p)
    test <- summary[
      summary$dataset == cell$dataset & summary$backend == cell$backend &
        summary$metric == cell$metric & summary$k == cell$k &
        abs(summary$target_recall - cell$target_recall) < 1e-12,
      , drop = FALSE
    ]
    explicit <- test[test$implementation == "faissR" & !grepl("_auto$", test$method_id), , drop = FALSE]
    eligible <- explicit[explicit$complete_validation & explicit$target_met_all_runs & is.finite(explicit$median_time_sec), , drop = FALSE]
    eligible <- eligible[order(eligible$median_time_sec, eligible$method_id), , drop = FALSE]
    selected_test <- explicit[method_family(explicit$method_id) == selected$method, , drop = FALSE]
    selected_test <- selected_test[order(selected_test$median_time_sec, selected_test$method_id), , drop = FALSE]
    chosen_ok <- nrow(selected_test) && selected_test$complete_validation[[1L]] &&
      selected_test$target_met_all_runs[[1L]] && is.finite(selected_test$median_time_sec[[1L]])
    oracle_time <- if (nrow(eligible)) eligible$median_time_sec[[1L]] else NA_real_
    chosen_time <- if (nrow(selected_test)) selected_test$median_time_sec[[1L]] else NA_real_
    rows[[i]] <- data.frame(
      cell,
      selected_family = selected$method %||% NA_character_,
      selection_basis = selected$basis %||% NA_character_,
      n_training_datasets = selected$n_training_datasets %||% 0L,
      median_training_time_sec = selected$median_training_time_sec %||% NA_real_,
      selected_test_method = if (nrow(selected_test)) selected_test$method_id[[1L]] else NA_character_,
      selected_test_time_sec = chosen_time,
      selected_test_min_recall = if (nrow(selected_test)) selected_test$min_recall_at_k[[1L]] else NA_real_,
      selected_test_target_met = isTRUE(chosen_ok),
      oracle_method = if (nrow(eligible)) eligible$method_id[[1L]] else NA_character_,
      oracle_time_sec = oracle_time,
      runtime_regret = if (isTRUE(chosen_ok) && is.finite(oracle_time) && oracle_time > 0) chosen_time / oracle_time else NA_real_,
      abstained = is.na(selected$method) || !nrow(selected_test),
      stringsAsFactors = FALSE
    )
  }
  result <- do.call(rbind, rows)
  write.csv(result, file.path(out_dir, "jss_leave_one_dataset_out.csv"), row.names = FALSE)
  keys <- c("backend", "metric", "target_recall")
  grouping <- interaction(result[keys], drop = TRUE, lex.order = TRUE)
  report <- do.call(rbind, lapply(split(result, grouping), function(part) data.frame(
    part[1L, keys, drop = FALSE],
    n_cells = nrow(part),
    n_evaluable = sum(!part$abstained),
    n_target_met = sum(part$selected_test_target_met),
    target_attainment_fraction = mean(part$selected_test_target_met),
    median_runtime_regret = if (any(is.finite(part$runtime_regret))) median(part$runtime_regret, na.rm = TRUE) else NA_real_,
    p90_runtime_regret = if (any(is.finite(part$runtime_regret))) unname(quantile(part$runtime_regret, 0.9, na.rm = TRUE)) else NA_real_,
    stringsAsFactors = FALSE
  )))
  write.csv(report, file.path(out_dir, "jss_leave_one_dataset_out_summary.csv"), row.names = FALSE)
  writeLines(c(
    "# Leave-one-dataset-out selector sensitivity", "",
    "For each held-out dataset and backend/metric/k/target cell, this analysis reconstructs an empirical shape policy using only the other datasets. It first uses the same predeclared shape group; when that group is absent, it uses the three nearest datasets in log(n)-log(p) space. The selected family maximizes complete dataset coverage and then minimizes median log runtime among methods meeting recall on all retained training cells.", "",
    "This is a sensitivity analysis of shape-based method selection. It does not retrain or alter the package's frozen compiled selector.", "",
    paste0("Evaluated cells: ", nrow(result), "."),
    paste0("Held-out cells meeting target: ", sum(result$selected_test_target_met), "."),
    paste0("Abstentions or absent selected methods: ", sum(result$abstained), ".")
  ), file.path(out_dir, "JSS_LEAVE_ONE_DATASET_OUT_REPORT.md"))
}

main()
