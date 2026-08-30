#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else stop("Provide the result root.")
files <- unique(c(
  Sys.glob(file.path(root, "jss_query_workload_raw.csv")),
  Sys.glob(file.path(root, "*", "jss_query_workload_raw.csv"))
))
if (!length(files)) stop("No query-workload result files found under ", root)
raw <- do.call(rbind, lapply(files, utils::read.csv, stringsAsFactors = FALSE))
keys <- c("dataset", "backend", "requested_method", "metric", "k",
          "query_mode", "requested_m", "actual_m")
groups <- split(raw, interaction(raw[keys], drop = TRUE, lex.order = TRUE))

summaries <- lapply(groups, function(x) {
  successful <- x[x$status == "success", , drop = FALSE]
  cold <- successful$elapsed_sec[successful$phase == "cold"]
  warm <- successful$elapsed_sec[successful$phase == "warm_repeated_query"]
  warm_median <- if (length(warm)) stats::median(warm) else NA_real_
  first <- x[1L, keys, drop = FALSE]
  cbind(
    first,
    completed_repeats = nrow(successful),
    cold_sec = if (length(cold)) cold[[1L]] else NA_real_,
    warm_query_sec = warm_median,
    estimated_build_sec = if (length(cold) && is.finite(warm_median)) {
      max(0, cold[[1L]] - warm_median)
    } else NA_real_,
    mean_recall_at_k = if (nrow(successful)) min(successful$mean_recall_at_k) else NA_real_,
    cache_hit_observed = any(successful$index_cache_hit),
    resolved_methods = paste(sort(unique(successful$resolved_method)), collapse = ";"),
    status = if (nrow(successful) == nrow(x)) "complete" else "incomplete",
    stringsAsFactors = FALSE
  )
})
summary <- do.call(rbind, summaries)
comparison_keys <- c(
  "dataset", "backend", "metric", "k", "query_mode",
  "requested_m", "actual_m"
)
flat <- summary[summary$requested_method == "flat", c(
  comparison_keys, "cold_sec"
), drop = FALSE]
names(flat)[names(flat) == "cold_sec"] <- "flat_cold_sec"
summary <- merge(
  summary, flat, by = comparison_keys, all.x = TRUE, sort = FALSE
)
summary$break_even_batches_vs_rebuilt_flat <- mapply(
  function(cold, warm, flat_cold) {
    if (!all(is.finite(c(cold, warm, flat_cold))) ||
        flat_cold <= warm) return(NA_integer_)
    as.integer(max(1, ceiling((cold - warm) / (flat_cold - warm))))
  },
  summary$cold_sec, summary$warm_query_sec, summary$flat_cold_sec
)
for (batches in c(1L, 10L, 100L)) {
  summary[[paste0("amortized_total_sec_b", batches)]] <-
    summary$cold_sec + (batches - 1L) * summary$warm_query_sec
}
utils::write.csv(summary, file.path(root, "jss_query_workload_summary.csv"), row.names = FALSE)

report <- c(
  "# Query-workload audit", "",
  sprintf("Raw rows: %d.", nrow(raw)),
  sprintf("Summary cells: %d.", nrow(summary)),
  sprintf("Complete cells: %d / %d.", sum(summary$status == "complete"), nrow(summary)),
  sprintf("Cells with an observed fitted-index cache hit: %d.", sum(summary$cache_hit_observed)),
  "", "Cold time is the first call after clearing package index caches. Warm time is",
  "the median of subsequent identical query calls. Estimated build time is",
  "max(0, cold - warm); it is an explicit decomposition estimate, not a directly",
  "instrumented provider build timer. Amortized totals use",
  "cold + (number_of_batches - 1) * warm."
  , "Break-even versus rebuilt Flat is the smallest integer A satisfying",
  "cold_method + (A - 1) * warm_method <= A * cold_flat. It is undefined",
  "when the fitted method's warm-query time is not below Flat cold time."
)
writeLines(report, file.path(root, "JSS_QUERY_WORKLOAD_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (any(summary$status != "complete")) quit(status = 1L)
