#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else file.path(
  getwd(), "faissR_JSS_REPRODUCTION/validation/cpu_auto_selection"
)
out_dir <- if (length(args) > 1L) args[[2L]] else file.path(root, "analysis")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(root, "\\.csv$", recursive = TRUE, full.names = TRUE)
files <- files[grepl("/worker_results/", files)]
if (!length(files)) stop("No CPU auto worker results found below ", root)
rows <- do.call(rbind, lapply(files, function(path) {
  x <- read.csv(path, stringsAsFactors = FALSE)
  x$source_file <- path
  x$source_mtime <- as.numeric(file.info(path)$mtime)
  x
}))
rows <- rows[rows$method_id == "faissR_cpu_auto" &
  rows$metric %in% c("euclidean", "cosine", "correlation"), , drop = FALSE]
key <- paste(rows$dataset, rows$metric, rows$k, rows$target_recall,
             rows$validation_seed, rows$repeat_id, sep = "|")
rank <- order(key, rows$status != "success", -rows$source_mtime, na.last = TRUE)
rows <- rows[rank, , drop = FALSE]
rows <- rows[!duplicated(paste(
  rows$dataset, rows$metric, rows$k, rows$target_recall,
  rows$validation_seed, rows$repeat_id, sep = "|"
)), , drop = FALSE]
write.csv(rows, file.path(out_dir, "jss_cpu_auto_validation_rows.csv"),
          row.names = FALSE)

cell_key <- interaction(rows[c("dataset", "metric", "k", "target_recall")],
                        drop = TRUE, lex.order = TRUE)
cells <- do.call(rbind, lapply(split(rows, cell_key), function(x) {
  success <- x$status == "success"
  exact_route <- success & (x$exact %in% TRUE |
    tolower(x$auto_predicted_method) %in% c("exact", "flat", "bruteforce"))
  approximate <- success & !exact_route
  complete <- nrow(x) == 6L
  exact_audited <- complete && all(success) && all(exact_route)
  approximate_target_met <- complete && all(success) && all(approximate) &&
    all(x$recall_at_k >= x$target_recall)
  methods <- unique(tolower(x$auto_predicted_method[success]))
  methods <- methods[!is.na(methods) & nzchar(methods)]
  data.frame(
    dataset = x$dataset[[1L]], metric = x$metric[[1L]], k = x$k[[1L]],
    target_recall = x$target_recall[[1L]], attempted_replicates = nrow(x),
    successful_replicates = sum(success), timeout_replicates = sum(x$status == "timeout"),
    failure_replicates = sum(!x$status %in% c("success", "timeout")),
    selected_method = if (length(methods) == 1L) methods else NA_character_,
    selection_stable = length(methods) == 1L,
    exact_audited = exact_audited,
    approximate_target_met = approximate_target_met,
    operating_point_met = exact_audited || approximate_target_met,
    min_replicate_mean_recall = if (any(success)) min(x$recall_at_k[success]) else NA_real_,
    median_elapsed_sec = if (any(success)) median(x$time_sec[success]) else NA_real_,
    stringsAsFactors = FALSE
  )
}))
write.csv(cells, file.path(out_dir, "jss_cpu_auto_validation_cells.csv"),
          row.names = FALSE)

frequency <- aggregate(
  rep(1L, nrow(cells)),
  cells[c("metric", "target_recall", "selected_method")], sum
)
names(frequency)[[ncol(frequency)]] <- "cells"
write.csv(frequency, file.path(out_dir, "jss_cpu_auto_selection_frequencies.csv"),
          row.names = FALSE)

expected_rows <- 9L * 3L * 4L * 3L * 2L * 3L
expected_cells <- 9L * 3L * 4L * 3L
design_pass <- nrow(rows) == expected_rows && nrow(cells) == expected_cells &&
  all(cells$attempted_replicates == 6L)
report <- c(
  "# CPU automatic-selection validation", "",
  sprintf("Planned replicate rows: %d.", expected_rows),
  sprintf("Observed replicate rows: %d.", nrow(rows)),
  sprintf("Planned operating cells: %d.", expected_cells),
  sprintf("Observed operating cells: %d.", nrow(cells)),
  sprintf("Operating points met: %d.", sum(cells$operating_point_met)),
  sprintf("Exact-audited cells: %d.", sum(cells$exact_audited)),
  sprintf("Approximate target-met cells: %d.", sum(cells$approximate_target_met)),
  sprintf("Cells with stable selected method across successful replicates: %d.",
          sum(cells$selection_stable)),
  sprintf("Timeout replicate rows: %d.", sum(rows$status == "timeout")),
  "",
  "Target attainment means mean recall@k meets the requested threshold in every prespecified validation replicate.",
  "Exhaustive-family selections are reported separately as exact-audited cells.",
  paste("Design audit:", if (design_pass) "PASS" else "FAIL")
)
writeLines(report, file.path(out_dir, "JSS_CPU_AUTO_SELECTION_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!design_pass) quit(status = 1L)
