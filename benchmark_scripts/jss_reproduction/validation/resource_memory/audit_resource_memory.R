#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else stop("Provide the result root.")
files <- list.files(
  root, pattern = "^jss_resource_memory_raw[.]csv$",
  recursive = TRUE, full.names = TRUE
)
if (!length(files)) stop("No resource-memory files found under ", root)
raw <- do.call(rbind, lapply(files, utils::read.csv, stringsAsFactors = FALSE))
keys <- c("dataset", "backend", "method", "query_mode")
groups <- split(raw, interaction(raw[keys], drop = TRUE, lex.order = TRUE))
summary <- do.call(rbind, lapply(groups, function(x) {
  success <- x[x$status == "success", , drop = FALSE]
  data.frame(
    x[1L, keys, drop = FALSE], planned_repeats = 3L,
    completed_repeats = nrow(success), timeouts = sum(x$status == "timeout"),
    failures = sum(!x$status %in% c("success", "timeout")),
    minimum_recall = if (nrow(success)) min(success$mean_recall_at_k) else NA_real_,
    median_elapsed_sec = if (nrow(success)) median(success$elapsed_sec) else NA_real_,
    median_peak_rss_gib = if (nrow(success)) median(success$peak_rss_kib) / 1024^2 else NA_real_,
    median_retained_increment_gib = if (nrow(success)) median(success$retained_search_increment_kib) / 1024^2 else NA_real_,
    median_gpu_peak_mib = if (nrow(success) && any(is.finite(success$gpu_process_peak_mib))) {
      median(success$gpu_process_peak_mib[is.finite(success$gpu_process_peak_mib)])
    } else NA_real_, stringsAsFactors = FALSE
  )
}))
utils::write.csv(summary, file.path(root, "jss_resource_memory_summary.csv"), row.names = FALSE)
complete <- nrow(raw) == 120L && all(table(interaction(raw[keys], drop = TRUE)) == 3L)
report <- c(
  "# Resource memory audit", "",
  sprintf("Raw rows: %d / 120 expected.", nrow(raw)),
  sprintf("Successful workers: %d.", sum(raw$status == "success")),
  sprintf("Timeouts: %d; other failures: %d.", sum(raw$status == "timeout"), sum(!raw$status %in% c("success", "timeout"))),
  sprintf("Complete cell/repetition key: %s.", complete), "",
  "Every row was produced by a fresh R worker. VmHWM is therefore valid for",
  "that cell only. Device memory is process-scoped nvidia-smi sampling and is",
  "reported separately from host memory.", "",
  if (complete) "RESOURCE MEMORY AUDIT PASSED" else "RESOURCE MEMORY AUDIT FAILED"
)
writeLines(report, file.path(root, "JSS_RESOURCE_MEMORY_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!complete) quit(status = 1L)
