#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- sub("^--root=", "", args[grepl("^--root=", args)])
root <- normalizePath(root, mustWork = TRUE)
files <- list.files(file.path(root, "validation"), "jss_paired_hnsw_raw[.]csv$", recursive = TRUE, full.names = TRUE)
if (length(files) != 72L) stop("Expected 72 validation result files; found ", length(files), ".")
x <- do.call(rbind, lapply(files, read.csv, stringsAsFactors = FALSE))
if (nrow(x) != 720L) stop("Expected 720 route runs; found ", nrow(x), ".")
x$cold_success <- x$status == "success" & is.finite(x$cold_call_sec) &
  is.finite(x$cold_recall_at_k)
x$fitted_success <- x$status == "success" & is.finite(x$fitted_build_sec) &
  is.finite(x$fitted_query_sec) & is.finite(x$fitted_recall_at_k)
keys <- c("dataset", "k", "comparator", "route")
groups <- interaction(x[keys], drop = TRUE, lex.order = TRUE)
summary <- do.call(rbind, lapply(split(x, groups), function(z) data.frame(
  z[1L, keys, drop = FALSE], n_runs = nrow(z),
  n_cold_success = sum(z$cold_success),
  n_fitted_success = sum(z$fitted_success),
  n_timeout = sum(z$status == "timeout"),
  target_met_all_runs = nrow(z) == 5L && all(z$cold_success) &&
    all(z$cold_recall_at_k >= 0.99),
  fitted_target_met_all_runs = nrow(z) == 5L && all(z$fitted_success) &&
    all(z$fitted_recall_at_k >= 0.99),
  minimum_recall = if (any(z$cold_success)) {
    min(z$cold_recall_at_k[z$cold_success])
  } else NA_real_,
  fitted_minimum_recall = if (any(z$fitted_success)) {
    min(z$fitted_recall_at_k[z$fitted_success])
  } else NA_real_,
  median_time_sec = if (any(z$cold_success)) {
    median(z$cold_call_sec[z$cold_success])
  } else NA_real_,
  median_fitted_build_sec = if (any(z$fitted_success)) {
    median(z$fitted_build_sec[z$fitted_success])
  } else NA_real_,
  median_fitted_query_sec = if (any(z$fitted_success)) {
    median(z$fitted_query_sec[z$fitted_success])
  } else NA_real_,
  median_fitted_index_rss_delta_kib = if (
    any(z$fitted_success & is.finite(z$fitted_index_rss_delta_kib))
  ) {
    median(z$fitted_index_rss_delta_kib[
      z$fitted_success & is.finite(z$fitted_index_rss_delta_kib)
    ])
  } else NA_real_,
  median_fitted_index_r_object_bytes = if (
    any(z$fitted_success & is.finite(z$fitted_index_r_object_bytes))
  ) {
    median(z$fitted_index_r_object_bytes[
      z$fitted_success & is.finite(z$fitted_index_r_object_bytes)
    ])
  } else NA_real_,
  cpus_allowed_list = paste(unique(z$cpus_allowed_list), collapse = ";"),
  maximum_observed_process_threads = if (any(is.finite(z$process_threads_after))) {
    max(z$process_threads_after[is.finite(z$process_threads_after)])
  } else NA_integer_,
  stringsAsFactors = FALSE
)))
write.csv(summary, file.path(root, "validation_route_summary.csv"), row.names = FALSE)

pair_keys <- c("dataset", "k", "comparator")
pairs <- split(summary, interaction(summary[pair_keys], drop = TRUE, lex.order = TRUE))
paired <- do.call(rbind, lapply(pairs, function(z) {
  f <- z[z$route == "faissR_hnsw", ]; c <- z[z$route == z$comparator[[1L]], ]
  stopifnot(nrow(f) == 1L, nrow(c) == 1L)
  data.frame(
    z[1L, pair_keys, drop = FALSE],
    both_target_met = f$target_met_all_runs && c$target_met_all_runs,
    both_fitted_target_met = f$fitted_target_met_all_runs &&
      c$fitted_target_met_all_runs,
    faissR_time_sec = f$median_time_sec,
    comparator_time_sec = c$median_time_sec,
    comparator_over_faissR = c$median_time_sec / f$median_time_sec,
    faissR_fitted_build_sec = f$median_fitted_build_sec,
    comparator_fitted_build_sec = c$median_fitted_build_sec,
    comparator_over_faissR_build = c$median_fitted_build_sec /
      f$median_fitted_build_sec,
    faissR_fitted_query_sec = f$median_fitted_query_sec,
    comparator_fitted_query_sec = c$median_fitted_query_sec,
    comparator_over_faissR_fitted_query = c$median_fitted_query_sec /
      f$median_fitted_query_sec,
    faissR_minimum_recall = f$minimum_recall,
    comparator_minimum_recall = c$minimum_recall,
    faissR_success = f$n_cold_success,
    comparator_success = c$n_cold_success,
    faissR_fitted_success = f$n_fitted_success,
    comparator_fitted_success = c$n_fitted_success,
    comparator_timeouts = c$n_timeout,
    stringsAsFactors = FALSE
  )
}))
write.csv(paired, file.path(root, "validation_paired_summary.csv"), row.names = FALSE)
eligible <- paired[paired$both_target_met, ]
fitted_eligible <- paired[paired$both_fitted_target_met, ]
report <- aggregate(comparator_over_faissR ~ comparator, eligible, function(v) c(
  n = length(v), median = median(v), q25 = quantile(v, .25), q75 = quantile(v, .75),
  minimum = min(v), maximum = max(v)
))
write.csv(report, file.path(root, "validation_provider_summary.csv"), row.names = FALSE)
fitted_report <- aggregate(
  cbind(comparator_over_faissR_build,
        comparator_over_faissR_fitted_query) ~ comparator,
  fitted_eligible,
  function(v) c(n = length(v), median = median(v), q25 = quantile(v, .25),
                q75 = quantile(v, .75), minimum = min(v), maximum = max(v))
)
write.csv(
  fitted_report,
  file.path(root, "validation_fitted_provider_summary.csv"),
  row.names = FALSE
)
writeLines(c(
  "# Independently tuned CPU HNSW comparison", "",
  paste0("Validation route runs: ", nrow(x), "/720."),
  paste0("Successful cold route runs: ", sum(x$cold_success), "."),
  paste0("Successful fitted route runs: ", sum(x$fitted_success), "."),
  paste0("Target-equivalent provider pairs: ", nrow(eligible), "/72."),
  paste0("Target-equivalent fitted provider pairs: ", nrow(fitted_eligible),
         "/72."),
  "Each provider configuration was selected using calibration seed 20260706 and evaluated with independent seed 20260807. Cold, fitted-build, and fitted-query times are distinct measured phases; no fitted time is inferred from a cold-call subtraction."
), file.path(root, "JSS_PAIRED_CPU_HNSW_PARETO_REPORT.md"))
cat("PARETO VALIDATION AUDIT PASSED\n")
