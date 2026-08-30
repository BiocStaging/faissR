#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
value <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}
root <- normalizePath(value("root", stop("Provide --root=RESULT_ROOT")),
                      mustWork = TRUE)
out_dir <- value("out_dir", file.path(root, "recall_inference"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
files <- list.files(
  root, pattern = "jmlr_tuned_benchmark_results[.]csv$",
  recursive = TRUE, full.names = TRUE
)
if (!length(files)) stop("No held-out result files found under ", root)
rows <- lapply(files, utils::read.csv, stringsAsFactors = FALSE)
columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
rows <- lapply(rows, function(x) {
  for (name in setdiff(columns, names(x))) x[[name]] <- NA
  x[, columns, drop = FALSE]
})
x <- do.call(rbind, rows)
required <- c(
  "dataset", "backend", "metric", "k", "target_recall", "method_id",
  "validation_seed", "repeat_id", "status", "recall_at_k",
  "tie_aware_recall_at_k", "tie_aware_recall_lcb",
  "tie_substitution_query_fraction", "recall_independent_query_n"
)
missing <- setdiff(required, names(x))
if (length(missing)) {
  stop("Results predate the recall-inference protocol; missing: ",
       paste(missing, collapse = ", "))
}
x <- x[x$status == "success", , drop = FALSE]
if (nrow(x) != 3888L) {
  stop("Expected 3,888 successful runs (648 cells x 2 seeds x 3 timing repeats); found ",
       nrow(x), ".")
}
keys <- c("dataset", "backend", "metric", "k", "target_recall",
          "method_id", "validation_seed")
groups <- split(x, interaction(x[keys], drop = TRUE, lex.order = TRUE))
seed_rows <- do.call(rbind, lapply(groups, function(z) {
  target <- as.numeric(z$target_recall[[1L]])
  data.frame(
    z[1L, keys, drop = FALSE],
    timing_repeats = length(unique(z$repeat_id)),
    independent_query_samples = 1L,
    independent_queries = max(z$recall_independent_query_n, na.rm = TRUE),
    identifier_mean_recall = min(z$recall_at_k, na.rm = TRUE),
    tie_aware_mean_recall = min(z$tie_aware_recall_at_k, na.rm = TRUE),
    tie_aware_query_recall_p05 = if (
      "tie_aware_query_recall_p05" %in% names(z) &&
      any(is.finite(z$tie_aware_query_recall_p05))
    ) min(z$tie_aware_query_recall_p05, na.rm = TRUE) else NA_real_,
    tie_aware_recall_lcb = min(z$tie_aware_recall_lcb, na.rm = TRUE),
    tie_substitution_query_fraction =
      max(z$tie_substitution_query_fraction, na.rm = TRUE),
    identifier_point_target_met = all(z$recall_at_k >= target),
    tie_aware_point_target_met = all(z$tie_aware_recall_at_k >= target),
    tie_aware_lcb_target_met = all(z$tie_aware_recall_lcb >= target),
    target_attainment_criterion =
      "empirical_query_bootstrap_lcb_all_independent_query_seeds",
    stringsAsFactors = FALSE
  )
}))
row.names(seed_rows) <- NULL
cell_keys <- setdiff(keys, "validation_seed")
cell_groups <- split(
  seed_rows,
  interaction(seed_rows[cell_keys], drop = TRUE, lex.order = TRUE)
)
cells <- do.call(rbind, lapply(cell_groups, function(z) data.frame(
  z[1L, cell_keys, drop = FALSE],
  independent_query_seeds = nrow(z),
  timing_repeats_per_seed = paste(sort(unique(z$timing_repeats)), collapse = ";"),
  identifier_point_target_met_all_seeds =
    all(z$identifier_point_target_met),
  tie_aware_point_target_met_all_seeds =
    all(z$tie_aware_point_target_met),
  tie_aware_lcb_target_met_all_seeds = all(z$tie_aware_lcb_target_met),
  maximum_tie_substitution_query_fraction =
    max(z$tie_substitution_query_fraction, na.rm = TRUE),
  minimum_tie_aware_recall_lcb = min(z$tie_aware_recall_lcb, na.rm = TRUE),
  minimum_tie_aware_query_recall_p05 = if (
    any(is.finite(z$tie_aware_query_recall_p05))
  ) min(z$tie_aware_query_recall_p05, na.rm = TRUE) else NA_real_,
  decision_changed_by_ties =
    all(z$tie_aware_point_target_met) != all(z$identifier_point_target_met),
  decision_changed_by_uncertainty =
    all(z$tie_aware_lcb_target_met) != all(z$tie_aware_point_target_met),
  stringsAsFactors = FALSE
)))
row.names(cells) <- NULL
if (nrow(cells) != 648L) stop("Expected 648 backend cells; found ", nrow(cells), ".")
if (any(cells$independent_query_seeds != 2L)) {
  stop("Every cell must contain two independent query seeds.")
}
if (any(cells$timing_repeats_per_seed != "3")) {
  stop("Every query seed must contain three timing repeats.")
}
utils::write.csv(
  seed_rows, file.path(out_dir, "jss_recall_inference_by_seed.csv"),
  row.names = FALSE
)
utils::write.csv(
  cells, file.path(out_dir, "jss_recall_inference_cells.csv"),
  row.names = FALSE
)
summary <- data.frame(
  cells = nrow(cells),
  identifier_point_pass = sum(cells$identifier_point_target_met_all_seeds),
  tie_aware_point_pass = sum(cells$tie_aware_point_target_met_all_seeds),
  tie_aware_lcb_pass = sum(cells$tie_aware_lcb_target_met_all_seeds),
  tie_decision_changes = sum(cells$decision_changed_by_ties),
  uncertainty_decision_changes = sum(cells$decision_changed_by_uncertainty),
  cells_with_observed_boundary_substitution =
    sum(cells$maximum_tie_substitution_query_fraction > 0),
  stringsAsFactors = FALSE
)
utils::write.csv(
  summary, file.path(out_dir, "jss_recall_inference_summary.csv"),
  row.names = FALSE
)
report <- c(
  "# Recall inference audit", "",
  sprintf("Cells: %d.", summary$cells),
  sprintf("Identifier-overlap point passes: %d.", summary$identifier_point_pass),
  sprintf("Tie-aware point passes: %d.", summary$tie_aware_point_pass),
  sprintf("Tie-aware 95%% query-bootstrap LCB passes: %d.",
          summary$tie_aware_lcb_pass),
  sprintf("Target decisions changed by boundary-tie credit: %d.",
          summary$tie_decision_changes),
  sprintf("Target decisions changed by the uncertainty criterion: %d.",
          summary$uncertainty_decision_changes), "",
  "The independent recall evidence unit is a query seed. Timing repetitions",
  "using that seed are collapsed within seed and do not increase the number of",
  "independent recall samples."
)
writeLines(report, file.path(out_dir, "JSS_RECALL_INFERENCE_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
