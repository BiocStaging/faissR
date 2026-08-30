#!/usr/bin/env Rscript

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  out
}

bind_rows <- function(values) {
  columns <- unique(unlist(lapply(values, names), use.names = FALSE))
  values <- lapply(values, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, values)
}

median_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) median(x) else NA_real_
}

quantile_or_na <- function(x, probability) {
  x <- x[is.finite(x)]
  if (length(x)) unname(quantile(x, probability, names = FALSE)) else NA_real_
}

summarize_groups <- function(x, columns) {
  key <- interaction(x[columns], drop = TRUE, lex.order = TRUE)
  pieces <- lapply(split(x, key), function(part) {
    values <- as.list(part[1L, columns, drop = FALSE])
    c(values, list(
      planned_pairs = nrow(part),
      both_successful = sum(part$both_successful),
      recall_equivalent_pairs = sum(part$recall_equivalent),
      comparator_timeouts = sum(part$status_comparator == "timeout"),
      comparator_failures = sum(part$status_comparator == "failed"),
      faissR_timeouts = sum(part$status_faissR == "timeout"),
      faissR_failures = sum(part$status_faissR == "failed"),
      median_comparator_over_faissR = median_or_na(
        part$time_ratio_comparator_over_faissR[part$recall_equivalent]
      ),
      q25_comparator_over_faissR = quantile_or_na(
        part$time_ratio_comparator_over_faissR[part$recall_equivalent], 0.25
      ),
      q75_comparator_over_faissR = quantile_or_na(
        part$time_ratio_comparator_over_faissR[part$recall_equivalent], 0.75
      ),
      median_comparator_recall = median_or_na(part$recall_at_k_comparator),
      median_faissR_recall = median_or_na(part$recall_at_k_faissR)
    ))
  })
  bind_rows(lapply(pieces, function(x) as.data.frame(x, stringsAsFactors = FALSE)))
}

args <- parse_args()
root <- args$root
out_dir <- args$out_dir
expected_version <- args$expected_version
expected_commit <- args$expected_commit
if (is.null(root) || !dir.exists(root)) stop("--root must name the completed run directory")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(root, pattern = "jss_comprehensive_r_raw[.]csv$",
                    recursive = TRUE, full.names = TRUE)
if (length(files) != 216L) {
  stop("Expected 216 task result files; found ", length(files))
}
raw <- bind_rows(lapply(files, read.csv, stringsAsFactors = FALSE,
                        check.names = FALSE))
expected_routes <- list(
  euclidean = c(
    "faissR_auto", "faissR_exact", "faissR_nndescent", "faissR_hnsw",
    "FNN_brute", "FNN_kd", "FNN_cover", "RANN_kd", "RANN_bd",
    "Rnanoflann_standard", "rnndescent_nnd",
    "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
    "BiocNeighbors_annoy", "RcppAnnoy_euclidean", "RcppHNSW_hnsw"
  ),
  cosine = c(
    "faissR_auto", "faissR_exact", "faissR_nndescent", "faissR_hnsw",
    "rnndescent_nnd", "BiocNeighbors_exhaustive",
    "BiocNeighbors_hnsw", "BiocNeighbors_annoy",
    "RcppAnnoy_angular", "RcppHNSW_hnsw"
  ),
  correlation = c(
    "faissR_auto", "faissR_exact", "faissR_nndescent", "rnndescent_nnd"
  )
)
expected_rows <- 72L * 3L * sum(lengths(expected_routes))
if (nrow(raw) != expected_rows) {
  stop("Expected ", expected_rows, " result rows; found ", nrow(raw))
}
key_columns <- c("dataset", "metric", "k", "validation_seed", "repeat_id", "route")
if (anyDuplicated(raw[key_columns])) stop("Duplicate route/repetition keys detected")
if (!all(raw$faissR_version == expected_version)) stop("faissR version mismatch")
if (!all(raw$faissR_package_commit == expected_commit)) stop("Package commit mismatch")
if (!all(raw$faissR_image_commit == expected_commit)) stop("Image commit mismatch")

cell_columns <- c("dataset", "metric", "k", "validation_seed")
cells <- unique(raw[cell_columns])
if (nrow(cells) != 216L) stop("Expected 216 distinct design cells")
for (metric in names(expected_routes)) {
  part <- raw[raw$metric == metric, , drop = FALSE]
  counts <- table(part$route)
  wanted <- expected_routes[[metric]]
  if (!setequal(names(counts), wanted) || any(counts[wanted] != 216L)) {
    stop("Incomplete route/repetition coverage for metric ", metric)
  }
}

external <- raw[raw$package != "faissR", , drop = FALSE]
faiss <- raw[raw$package == "faissR", , drop = FALSE]
left_keys <- c("dataset", "metric", "k", "validation_seed", "repeat_id")
external$pair_key <- paste(
  external$dataset, external$metric, external$k, external$validation_seed,
  external$repeat_id, external$reference_route, sep = "\r"
)
faiss$pair_key <- paste(
  faiss$dataset, faiss$metric, faiss$k, faiss$validation_seed,
  faiss$repeat_id, faiss$route, sep = "\r"
)
faiss_keep <- faiss[, c(
  "pair_key", "status", "elapsed_sec", "recall_at_k", "min_query_recall",
  "hostname", "order_position"
), drop = FALSE]
names(faiss_keep)[-1L] <- paste0(names(faiss_keep)[-1L], "_faissR")
pairs <- merge(external, faiss_keep, by = "pair_key", all.x = TRUE, sort = FALSE)
names(pairs)[names(pairs) == "status"] <- "status_comparator"
names(pairs)[names(pairs) == "elapsed_sec"] <- "elapsed_sec_comparator"
names(pairs)[names(pairs) == "recall_at_k"] <- "recall_at_k_comparator"
names(pairs)[names(pairs) == "min_query_recall"] <- "min_query_recall_comparator"
pairs$both_successful <- pairs$status_comparator == "success" &
  pairs$status_faissR == "success"
pairs$recall_equivalent <- pairs$both_successful &
  pairs$recall_at_k_comparator >= pairs$target_recall &
  pairs$recall_at_k_faissR >= pairs$target_recall
pairs$same_node <- pairs$hostname == pairs$hostname_faissR
pairs$time_ratio_comparator_over_faissR <- ifelse(
  pairs$both_successful,
  pairs$elapsed_sec_comparator / pairs$elapsed_sec_faissR,
  NA_real_
)
if (any(!pairs$same_node, na.rm = TRUE)) stop("A paired route was not run on the same node")

package_summary <- summarize_groups(pairs, c("package", "comparison_class", "reference_route"))
route_summary <- summarize_groups(pairs, c("package", "route", "metric", "comparison_class", "reference_route"))
dataset_summary <- summarize_groups(pairs, c("dataset", "package", "route", "metric"))

requested_packages <- c(
  "FNN", "RANN", "rnndescent", "BiocNeighbors",
  "Rnanoflann", "RcppAnnoy", "RcppHNSW"
)
if (!setequal(unique(external$package), requested_packages)) {
  stop("External-package coverage differs from the prespecified seven packages")
}
metric_contract <- expand.grid(
  package = requested_packages,
  metric = c("euclidean", "cosine", "correlation"),
  stringsAsFactors = FALSE
)
metric_contract$applicable <- mapply(function(package, metric) {
  any(external$package == package & external$metric == metric)
}, metric_contract$package, metric_contract$metric)
metric_contract$interpretation <- ifelse(
  metric_contract$applicable, "evaluated_public_interface",
  "unsupported_or_not_validated_for_this_metric"
)

write.csv(raw, file.path(out_dir, "jss_comprehensive_r_all_rows.csv"), row.names = FALSE)
write.csv(pairs, file.path(out_dir, "jss_comprehensive_r_pairs.csv"), row.names = FALSE)
write.csv(package_summary, file.path(out_dir, "jss_comprehensive_r_by_package.csv"), row.names = FALSE)
write.csv(route_summary, file.path(out_dir, "jss_comprehensive_r_by_route.csv"), row.names = FALSE)
write.csv(dataset_summary, file.path(out_dir, "jss_comprehensive_r_by_dataset.csv"), row.names = FALSE)
write.csv(metric_contract, file.path(out_dir, "jss_comprehensive_r_metric_contract.csv"), row.names = FALSE)
writeLines(files, file.path(out_dir, "raw_result_manifest.txt"))

report <- c(
  "# Comprehensive R nearest-neighbor comparison",
  "",
  paste0("Task files: ", length(files), " / 216."),
  paste0("Raw route repetitions: ", nrow(raw), " / ", expected_rows, "."),
  paste0("External packages: ", paste(sort(requested_packages), collapse = ", "), "."),
  paste0("Successful route executions: ", sum(raw$status == "success"), " / ", nrow(raw), "."),
  paste0("Timeouts: ", sum(raw$status == "timeout"), "."),
  paste0("Other execution failures: ", sum(raw$status == "failed"), "."),
  paste0("Point-recall-matched paired repetitions: ", sum(pairs$recall_equivalent), " / ", nrow(pairs), "."),
  "The legacy `recall_equivalent` field applies a point-mean matching rule and is not the empirical query-bootstrap validation-attainment criterion.",
  "",
  "Ratios are comparator elapsed time divided by the matched faissR route elapsed time.",
  "Values above one favor faissR. All paired executions share dataset, metric, k,",
  "validation seed, repetition, Slurm allocation, and node.",
  "",
  "COMPREHENSIVE R COMPARISON AUDIT PASSED"
)
writeLines(report, file.path(out_dir, "JSS_COMPREHENSIVE_R_COMPARISON_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
