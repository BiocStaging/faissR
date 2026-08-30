#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else file.path(
  getwd(), "faissR_JSS_REPRODUCTION/validation/paired_cpu_comparison"
)
out_dir <- if (length(args) > 1L) args[[2L]] else root
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(root, "jss_paired_hnsw_raw\\.csv$", recursive = TRUE, full.names = TRUE)
if (!length(files)) stop("No paired HNSW result files found below ", root)
raw <- do.call(rbind, lapply(files, function(path) {
  x <- read.csv(path, stringsAsFactors = FALSE)
  x$source_file <- path
  x$source_mtime <- as.numeric(file.info(path)$mtime)
  x
}))
route_key <- paste(raw$pair_id, raw$route, sep = "|")
rank <- order(
  route_key,
  raw$status != "success",
  -raw$source_mtime,
  na.last = TRUE
)
raw <- raw[rank, , drop = FALSE]
raw <- raw[!duplicated(paste(raw$pair_id, raw$route, sep = "|")), , drop = FALSE]
write.csv(raw, file.path(out_dir, "jss_paired_hnsw_all_rows.csv"), row.names = FALSE)

key <- c("dataset", "comparator", "metric", "k", "target_recall",
         "validation_seed", "repeat_id", "pair_id")
f <- raw[raw$route == "faissR_hnsw", , drop = FALSE]
comparator_rows <- raw[raw$route == raw$comparator, , drop = FALSE]
paired <- merge(
  f, comparator_rows, by = key,
  suffixes = c("_faissR", "_comparator"), all = TRUE
)
paired$same_node <- paired$hostname_faissR == paired$hostname_comparator
paired$same_allocation <- paired$slurm_job_id_faissR == paired$slurm_job_id_comparator
paired$opposite_order_positions <- paired$order_position_faissR != paired$order_position_comparator
paired$pair_complete <- paired$status_faissR == "success" & paired$status_comparator == "success"
paired$cold_speed_ratio <- paired$cold_call_sec_comparator / paired$cold_call_sec_faissR
paired$fitted_build_speed_ratio <- paired$fitted_build_sec_comparator / paired$fitted_build_sec_faissR
paired$fitted_query_speed_ratio <- paired$fitted_query_sec_comparator / paired$fitted_query_sec_faissR
paired$cold_recall_equivalent <- paired$cold_recall_at_k_faissR >= 0.99 &
  paired$cold_recall_at_k_comparator >= 0.99
paired$fitted_recall_equivalent <- paired$fitted_recall_at_k_faissR >= 0.99 &
  paired$fitted_recall_at_k_comparator >= 0.99
paired$cold_point_recall_matched <- paired$cold_recall_equivalent
paired$fitted_point_recall_matched <- paired$fitted_recall_equivalent
write.csv(paired, file.path(out_dir, "jss_paired_hnsw_pairs.csv"), row.names = FALSE)

successful <- paired[
  paired$pair_complete & paired$same_node & paired$same_allocation &
    paired$opposite_order_positions,
  , drop = FALSE
]
group <- interaction(successful$dataset, successful$comparator, successful$k, drop = TRUE)
summaries <- lapply(split(successful, group), function(x) {
  q <- function(z, p) unname(stats::quantile(z, p, na.rm = TRUE, names = FALSE))
  data.frame(
    dataset = x$dataset[[1L]], comparator = x$comparator[[1L]],
    metric = x$metric[[1L]], k = x$k[[1L]],
    completed_pairs = nrow(x),
    cold_recall_equivalent_pairs = sum(x$cold_recall_equivalent, na.rm = TRUE),
    fitted_recall_equivalent_pairs = sum(x$fitted_recall_equivalent, na.rm = TRUE),
    median_cold_speed_ratio = median(x$cold_speed_ratio, na.rm = TRUE),
    cold_speed_ratio_q25 = q(x$cold_speed_ratio, 0.25),
    cold_speed_ratio_q75 = q(x$cold_speed_ratio, 0.75),
    median_fitted_build_speed_ratio = median(x$fitted_build_speed_ratio, na.rm = TRUE),
    median_fitted_query_speed_ratio = median(x$fitted_query_speed_ratio, na.rm = TRUE),
    median_cold_recall_equivalent_speed_ratio = if (any(x$cold_recall_equivalent %in% TRUE)) {
      median(x$cold_speed_ratio[x$cold_recall_equivalent %in% TRUE], na.rm = TRUE)
    } else {
      NA_real_
    },
    median_fitted_recall_equivalent_query_speed_ratio = if (any(x$fitted_recall_equivalent %in% TRUE)) {
      median(x$fitted_query_speed_ratio[x$fitted_recall_equivalent %in% TRUE], na.rm = TRUE)
    } else {
      NA_real_
    },
    stringsAsFactors = FALSE
  )
})
summary <- if (length(summaries)) do.call(rbind, summaries) else data.frame()
write.csv(summary, file.path(out_dir, "jss_paired_hnsw_summary.csv"), row.names = FALSE)

expected_pairs <- 9L * 4L * 2L * 2L * 5L
all_valid <- nrow(paired) == expected_pairs &&
  all(paired$same_node %in% TRUE) &&
  all(paired$same_allocation %in% TRUE) &&
  all(paired$opposite_order_positions %in% TRUE)
report <- c(
  "# Controlled paired CPU HNSW comparison",
  "",
  sprintf("Planned matched route pairs: %d.", expected_pairs),
  sprintf("Observed matched route pairs: %d.", nrow(paired)),
  sprintf("Successful paired executions: %d.", sum(paired$pair_complete, na.rm = TRUE)),
  sprintf("Same-node pairs: %d.", sum(paired$same_node, na.rm = TRUE)),
  sprintf("Same-allocation pairs: %d.", sum(paired$same_allocation, na.rm = TRUE)),
  sprintf("Opposite-order pairs: %d.", sum(paired$opposite_order_positions, na.rm = TRUE)),
  "",
  "Every speed ratio is T_comparator / T_faissR; values above one favor faissR.",
  "Cold-call, fitted-index build, and fitted-index query ratios are reported separately.",
  "Legacy `*_recall_equivalent` CSV columns mean point-recall-matched: both routes have mean recall@k >= 0.99; they do not apply the empirical query-bootstrap validation criterion.",
  "The first route is randomized deterministically within each seed and alternates across repetitions.",
  "Each route repetition runs in an isolated R worker, while both routes in a pair share one Slurm allocation and node.",
  "",
  paste("Design audit:", if (all_valid) "PASS" else "FAIL")
)
writeLines(report, file.path(out_dir, "JSS_PAIRED_HNSW_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!all_valid) quit(status = 1L)
