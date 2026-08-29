#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list(
    results_root = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/reviewer_response/external_r_comparison/cpu",
    out_dir = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/reviewer_response/external_r_comparison/analysis"
  )
  for (arg in x) {
    if (startsWith(arg, "--results_root=")) out$results_root <- sub("^--results_root=", "", arg)
    else if (startsWith(arg, "--out_dir=")) out$out_dir <- sub("^--out_dir=", "", arg)
    else stop("Unknown argument: ", arg, call. = FALSE)
  }
  out
}

read_result <- function(path) {
  x <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  x$source_file <- normalizePath(path, mustWork = TRUE)
  x
}

quant <- function(x, probability) {
  if (!length(x)) return(NA_real_)
  unname(stats::quantile(x, probability, na.rm = TRUE, names = FALSE, type = 7))
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
files <- list.files(
  args$results_root,
  pattern = "^jmlr_tuned_benchmark_results[.]csv$",
  recursive = TRUE,
  full.names = TRUE
)
if (!length(files)) stop("No benchmark result files under ", args$results_root, call. = FALSE)

all <- do.call(rbind, lapply(files, read_result))
required <- c(
  "dataset", "method_id", "implementation", "metric", "k",
  "target_recall", "validation_seed", "repeat_id", "status", "time_sec",
  "recall_at_k", "implementation_version", "method_parameters"
)
missing_columns <- setdiff(required, names(all))
if (length(missing_columns)) {
  stop("Missing result columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
}

method_map <- data.frame(
  method_id = c(
    "faissR_cpu_exact", "FNN_brute",
    "faissR_cpu_hnsw", "RcppHNSW_hnsw",
    "faissR_cpu_nndescent", "rnndescent_nnd"
  ),
  route = c(
    "faissR_exact", "FNN_brute",
    "faissR_hnsw", "RcppHNSW_hnsw",
    "faissR_nndescent_derived", "rnndescent_nnd"
  ),
  family = rep(c("exact", "hnsw", "nndescent"), each = 2L),
  role = rep(c("faissR", "external"), 3L),
  stringsAsFactors = FALSE
)
all <- merge(all, method_map, by = "method_id", all.x = FALSE, all.y = FALSE)
if (!nrow(all)) stop("None of the expected comparison methods was found.", call. = FALSE)

all$target_recall <- suppressWarnings(as.numeric(all$target_recall))
all$time_sec <- suppressWarnings(as.numeric(all$time_sec))
all$recall_at_k <- suppressWarnings(as.numeric(all$recall_at_k))
all$k <- as.integer(all$k)
all$repeat_id <- as.integer(all$repeat_id)
all$validation_seed <- as.character(all$validation_seed)

analysis_rows <- all[
  (all$role == "external" & is.na(all$target_recall)) |
    (all$role == "faissR" & abs(all$target_recall - 0.99) < 1e-12),
  , drop = FALSE
]

expected <- expand.grid(
  family = c("exact", "hnsw", "nndescent"),
  role = c("faissR", "external"),
  metric = c("euclidean", "cosine", "correlation"),
  stringsAsFactors = FALSE
)
expected <- expected[
  (expected$family == "exact" & expected$metric == "euclidean") |
    (expected$family == "hnsw" & expected$metric %in% c("euclidean", "cosine")) |
    expected$family == "nndescent",
  , drop = FALSE
]

inventory_rows <- lapply(seq_len(nrow(expected)), function(i) {
  key <- expected[i, , drop = FALSE]
  z <- analysis_rows[
    analysis_rows$family == key$family & analysis_rows$role == key$role &
      analysis_rows$metric == key$metric,
    , drop = FALSE
  ]
  data.frame(
    family = key$family,
    role = key$role,
    metric = key$metric,
    route = paste(sort(unique(z$route)), collapse = ";"),
    implementation = paste(sort(unique(z$implementation)), collapse = ";"),
    implementation_version = paste(sort(unique(z$implementation_version)), collapse = ";"),
    rows = nrow(z),
    successful_rows = sum(z$status == "success", na.rm = TRUE),
    failed_rows = sum(z$status != "success", na.rm = TRUE),
    datasets_with_success = length(unique(z$dataset[z$status == "success"])),
    mean_recall = if (any(is.finite(z$recall_at_k))) mean(z$recall_at_k, na.rm = TRUE) else NA_real_,
    min_recall = if (any(is.finite(z$recall_at_k))) min(z$recall_at_k, na.rm = TRUE) else NA_real_,
    stringsAsFactors = FALSE
  )
})
inventory <- do.call(rbind, inventory_rows)

pairs <- list(
  exact = c(faissR = "faissR_exact", external = "FNN_brute"),
  hnsw = c(faissR = "faissR_hnsw", external = "RcppHNSW_hnsw"),
  nndescent = c(faissR = "faissR_nndescent_derived", external = "rnndescent_nnd")
)
key_columns <- c("dataset", "metric", "k", "validation_seed", "repeat_id")
paired_parts <- list()
for (family in names(pairs)) {
  routes <- pairs[[family]]
  lhs <- analysis_rows[
    analysis_rows$route == routes[["faissR"]] & analysis_rows$status == "success",
    c(key_columns, "time_sec", "recall_at_k", "method_parameters"), drop = FALSE
  ]
  rhs <- analysis_rows[
    analysis_rows$route == routes[["external"]] & analysis_rows$status == "success",
    c(key_columns, "time_sec", "recall_at_k", "method_parameters"), drop = FALSE
  ]
  names(lhs)[-(seq_along(key_columns))] <- paste0("faissR_", names(lhs)[-(seq_along(key_columns))])
  names(rhs)[-(seq_along(key_columns))] <- paste0("external_", names(rhs)[-(seq_along(key_columns))])
  joined <- merge(lhs, rhs, by = key_columns, all = FALSE)
  if (!nrow(joined)) next
  joined$family <- family
  joined$faissR_route <- routes[["faissR"]]
  joined$external_route <- routes[["external"]]
  joined$speed_ratio_external_over_faissR <- joined$external_time_sec / joined$faissR_time_sec
  paired_parts[[family]] <- joined
}
paired <- if (length(paired_parts)) do.call(rbind, paired_parts) else data.frame()

if (nrow(paired)) {
  approximate <- paired$family %in% c("hnsw", "nndescent")
  attainment_groups <- split(
    seq_len(nrow(paired)),
    interaction(paired$family, paired$dataset, paired$metric, paired$k, drop = TRUE)
  )
  equivalent <- rep(TRUE, nrow(paired))
  for (indices in attainment_groups) {
    if (!approximate[indices[[1L]]]) next
    equivalent[indices] <-
      all(is.finite(paired$faissR_recall_at_k[indices])) &&
      all(is.finite(paired$external_recall_at_k[indices])) &&
      all(paired$faissR_recall_at_k[indices] >= 0.99) &&
      all(paired$external_recall_at_k[indices] >= 0.99)
  }
  paired$recall_equivalent <- equivalent
  paired$recall_equivalence_rule <- ifelse(
    approximate,
    "both routes have mean recall_at_k >= 0.99 in every replicate",
    "exact-family pair; exactness assessed separately"
  )

  paired_scopes <- rbind(
    transform(paired, comparison_scope = "all_successful_prespecified_interface"),
    transform(
      paired[paired$recall_equivalent, , drop = FALSE],
      comparison_scope = "recall_equivalent"
    )
  )
  dataset_groups <- split(
    paired_scopes,
    interaction(
      paired_scopes$family, paired_scopes$metric,
      paired_scopes$dataset, paired_scopes$comparison_scope,
      drop = TRUE
    )
  )
  dataset_summary <- do.call(rbind, lapply(dataset_groups, function(z) data.frame(
    family = z$family[[1L]],
    metric = z$metric[[1L]],
    dataset = z$dataset[[1L]],
    comparison_scope = z$comparison_scope[[1L]],
    paired_cells = nrow(z),
    median_speed_ratio = stats::median(z$speed_ratio_external_over_faissR, na.rm = TRUE),
    q25_speed_ratio = quant(z$speed_ratio_external_over_faissR, 0.25),
    q75_speed_ratio = quant(z$speed_ratio_external_over_faissR, 0.75),
    mean_faissR_recall = mean(z$faissR_recall_at_k, na.rm = TRUE),
    mean_external_recall = mean(z$external_recall_at_k, na.rm = TRUE),
    stringsAsFactors = FALSE
  )))
  comparison_groups <- split(
    dataset_summary,
    interaction(
      dataset_summary$family, dataset_summary$metric,
      dataset_summary$comparison_scope, drop = TRUE
    )
  )
  comparison_summary <- do.call(rbind, lapply(comparison_groups, function(z) data.frame(
    family = z$family[[1L]],
    metric = z$metric[[1L]],
    comparison_scope = z$comparison_scope[[1L]],
    datasets = nrow(z),
    paired_cells = sum(z$paired_cells),
    median_dataset_speed_ratio = stats::median(z$median_speed_ratio),
    q25_dataset_speed_ratio = quant(z$median_speed_ratio, 0.25),
    q75_dataset_speed_ratio = quant(z$median_speed_ratio, 0.75),
    min_dataset_speed_ratio = min(z$median_speed_ratio),
    max_dataset_speed_ratio = max(z$median_speed_ratio),
    stringsAsFactors = FALSE
  )))
} else {
  dataset_summary <- data.frame()
  comparison_summary <- data.frame()
}

dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(all, file.path(args$out_dir, "jss_external_r_all_rows.csv"), row.names = FALSE)
utils::write.csv(inventory, file.path(args$out_dir, "jss_external_r_inventory.csv"), row.names = FALSE)
utils::write.csv(paired, file.path(args$out_dir, "jss_external_r_paired_cells.csv"), row.names = FALSE)
utils::write.csv(dataset_summary, file.path(args$out_dir, "jss_external_r_dataset_summary.csv"), row.names = FALSE)
utils::write.csv(comparison_summary, file.path(args$out_dir, "jss_external_r_comparison_summary.csv"), row.names = FALSE)

missing_runs <- inventory[inventory$rows == 0L, c("family", "role", "metric"), drop = FALSE]
report <- c(
  "# External R nearest-neighbor comparison",
  "",
  paste0("Expected method-metric jobs: ", nrow(inventory), "."),
  paste0("Jobs with result rows: ", sum(inventory$rows > 0L), "."),
  paste0("Successful rows: ", sum(inventory$successful_rows), "; failed or timed-out rows: ", sum(inventory$failed_rows), "."),
  paste0("Paired successful cells: ", nrow(paired), "."),
  paste0(
    "Paired rows in recall-equivalent approximate cells: ",
    if (nrow(paired)) sum(paired$recall_equivalent & paired$family != "exact") else 0L,
    "."
  ),
  "",
  "Ratios are external-package elapsed time divided by faissR elapsed time; values greater than one favor faissR. faissR approximate routes use the target-0.99 operating point. External routes use the explicitly recorded prespecified public-package configuration. The prespecified-interface summary includes every successful pair. The recall-equivalent summary retains an approximate dataset-metric-k cell only when both routes have mean recall@k >= 0.99 in every validation replicate. Results are end-to-end API comparisons, not isolated kernel benchmarks.",
  "Pairing means analytical matching by dataset, metric, k, validation seed, and repeat. The one-method jobs do not guarantee same-node execution. Each timed call uses a fresh R worker, with data and reference loading before the timer, gc() immediately before timing, no untimed search warm-up, no operating-system cache flush, and no randomized cross-method execution order.",
  "",
  "The surveyed CPU comparator packages return ordinary host-resident R objects. No comparator in this experiment exposes an R nearest-neighbor result that remains resident in NVIDIA device memory for direct downstream consumption."
)
if (nrow(missing_runs)) {
  report <- c(report, "", "## Missing jobs", "", apply(missing_runs, 1L, function(z) paste0("- ", paste(z, collapse = " / "))))
}
writeLines(report, file.path(args$out_dir, "JSS_EXTERNAL_R_COMPARISON_REPORT.md"), useBytes = TRUE)

if (nrow(missing_runs)) {
  stop(nrow(missing_runs), " expected method-metric jobs have no result rows.", call. = FALSE)
}
cat("External R comparison audit completed: ", args$out_dir, "\n", sep = "")
