#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else file.path(
  getwd(), "faissR_JSS_REPRODUCTION/validation/paired_external_cpu_comparison"
)
out_dir <- if (length(args) > 1L) args[[2L]] else file.path(root, "analysis")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(root, "jss_paired_external_cpu_raw\\.csv$", recursive = TRUE,
                    full.names = TRUE)
if (!length(files)) stop("No paired external CPU result files found below ", root)
raw <- do.call(rbind, lapply(files, function(path) {
  x <- read.csv(path, stringsAsFactors = FALSE)
  x$source_file <- path
  x$source_mtime <- as.numeric(file.info(path)$mtime)
  x
}))
route_key <- paste(raw$pair_id, raw$route, sep = "|")
rank <- order(route_key, raw$status != "success", -raw$source_mtime, na.last = TRUE)
raw <- raw[rank, , drop = FALSE]
raw <- raw[!duplicated(paste(raw$pair_id, raw$route, sep = "|")), , drop = FALSE]
write.csv(raw, file.path(out_dir, "jss_paired_external_cpu_all_rows.csv"),
          row.names = FALSE)

keys <- c("dataset", "comparison", "comparator", "metric", "k",
          "target_recall", "validation_seed", "repeat_id", "pair_id")
faissr <- raw[startsWith(raw$route, "faissR_"), , drop = FALSE]
external <- raw[raw$route == raw$comparator, , drop = FALSE]
pairs <- merge(faissr, external, by = keys,
               suffixes = c("_faissR", "_comparator"), all = TRUE)
pairs$same_node <- pairs$hostname_faissR == pairs$hostname_comparator
pairs$same_allocation <- pairs$slurm_job_id_faissR == pairs$slurm_job_id_comparator
pairs$opposite_order_positions <- pairs$order_position_faissR !=
  pairs$order_position_comparator
pairs$pair_complete <- pairs$status_faissR == "success" &
  pairs$status_comparator == "success"
pairs$speed_ratio <- pairs$elapsed_sec_comparator / pairs$elapsed_sec_faissR
pairs$pair_recall_pass <- pairs$recall_at_k_faissR >= pairs$target_recall &
  pairs$recall_at_k_comparator >= pairs$target_recall
pairs$comparison_contract <- ifelse(
  pairs$comparison == "exact_FNN", "exhaustive_provider_pair",
  "approximate_recall_equivalence"
)
write.csv(pairs, file.path(out_dir, "jss_paired_external_cpu_pairs.csv"),
          row.names = FALSE)

cell_key <- interaction(
  pairs[c("dataset", "comparison", "metric", "k", "target_recall")],
  drop = TRUE, lex.order = TRUE
)
cells <- do.call(rbind, lapply(split(pairs, cell_key), function(x) {
  valid_design <- x$pair_complete & x$same_node & x$same_allocation &
    x$opposite_order_positions
  exact_pair <- x$comparison[[1L]] == "exact_FNN"
  target_equivalent <- if (exact_pair) {
    NA
  } else {
    all(valid_design) && all(x$pair_recall_pass[valid_design]) &&
      sum(valid_design) == 6L
  }
  ratios <- x$speed_ratio[valid_design & (exact_pair | x$pair_recall_pass)]
  data.frame(
    dataset = x$dataset[[1L]], comparison = x$comparison[[1L]],
    metric = x$metric[[1L]], k = x$k[[1L]],
    target_recall = x$target_recall[[1L]], planned_pairs = 6L,
    completed_pairs = sum(valid_design, na.rm = TRUE),
    faissR_timeouts = sum(x$status_faissR == "timeout", na.rm = TRUE),
    comparator_timeouts = sum(x$status_comparator == "timeout", na.rm = TRUE),
    exact_provider_pair = exact_pair,
    approximate_target_equivalent = target_equivalent,
    median_speed_ratio = if (length(ratios)) median(ratios, na.rm = TRUE) else NA_real_,
    speed_ratio_q25 = if (length(ratios)) unname(quantile(ratios, 0.25, na.rm = TRUE)) else NA_real_,
    speed_ratio_q75 = if (length(ratios)) unname(quantile(ratios, 0.75, na.rm = TRUE)) else NA_real_,
    stringsAsFactors = FALSE
  )
}))
write.csv(cells, file.path(out_dir, "jss_paired_external_cpu_cells.csv"),
          row.names = FALSE)

expected <- 3L * 4L * 2L * 3L + 9L * 4L * 3L * 2L * 3L
design_pass <- nrow(pairs) == expected &&
  all(pairs$same_node %in% TRUE) &&
  all(pairs$same_allocation %in% TRUE) &&
  all(pairs$opposite_order_positions %in% TRUE)
report <- c(
  "# Controlled paired external CPU comparison", "",
  sprintf("Planned matched route pairs: %d.", expected),
  sprintf("Observed matched route pairs: %d.", nrow(pairs)),
  sprintf("Successful paired executions: %d.", sum(pairs$pair_complete, na.rm = TRUE)),
  sprintf("Same-node pairs: %d.", sum(pairs$same_node, na.rm = TRUE)),
  sprintf("Same-allocation pairs: %d.", sum(pairs$same_allocation, na.rm = TRUE)),
  sprintf("Opposite-order pairs: %d.", sum(pairs$opposite_order_positions, na.rm = TRUE)),
  "",
  "Speed ratio is T_external / T_faissR; values above one favor faissR.",
  "Exact/FNN cells are labeled as exhaustive-provider pairs rather than ANN target successes.",
  "NN-descent cells are summarized only when both routes meet the requested mean recall in every prespecified replicate.",
  "Every timed call runs in an isolated R worker; paired routes share one Slurm allocation and node.",
  "",
  paste("Design audit:", if (design_pass) "PASS" else "FAIL")
)
writeLines(report, file.path(out_dir, "JSS_PAIRED_EXTERNAL_CPU_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!design_pass) quit(status = 1L)
