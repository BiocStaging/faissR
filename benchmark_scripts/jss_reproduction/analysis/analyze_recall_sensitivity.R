#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
value <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}
root <- normalizePath(value("root", stop("Provide --root=RESULT_ROOT")),
                      mustWork = TRUE)
out_dir <- value("out_dir", file.path(root, "analysis", "recall_sensitivity"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
datasets <- strsplit(value("datasets", "flow18,mass41,imagenet"), ",",
                     fixed = TRUE)[[1L]]
datasets <- trimws(datasets[nzchar(trimws(datasets))])

source(file.path(
  "benchmark_scripts", "jss_reproduction", "common",
  "benchmark_recall_inference.R"
))

detail_files <- list.files(
  root, pattern = "_query_recall[.]rds$", recursive = TRUE,
  full.names = TRUE
)
if (!length(detail_files)) {
  stop("No per-query recall sidecars were found under ", root, ".")
}

records <- list()
for (path in detail_files) {
  csv_path <- sub("_query_recall[.]rds$", ".csv", path)
  if (!file.exists(csv_path)) next
  meta <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  if (!nrow(meta) || !identical(meta$status[[1L]], "success")) next
  if (!meta$dataset[[1L]] %in% datasets) next
  detail <- readRDS(path)
  recall <- as.numeric(detail$tie_aware_recall)
  recall <- recall[is.finite(recall)]
  if (!length(recall)) next
  records[[length(records) + 1L]] <- list(meta = meta[1L, , drop = FALSE],
                                         recall = recall, path = path)
}
if (!length(records)) stop("No selected-dataset recall sidecars were usable.")

key_for <- function(meta) paste(
  meta$dataset, meta$backend, meta$metric, meta$k, meta$target_recall,
  meta$method_id, meta$validation_seed, sep = "\r"
)
keys <- vapply(records, function(z) key_for(z$meta), character(1))
records <- records[!duplicated(keys)]

seed_from <- function(...) {
  text <- paste(..., collapse = "|")
  raw <- utf8ToInt(text)
  as.integer((sum(raw * seq_along(raw)) %% (.Machine$integer.max - 1L)) + 1L)
}

rows <- list()
for (record in records) {
  meta <- record$meta
  recall <- record$recall
  n <- length(recall)
  query_sizes <- unique(sort(c(c(128L, 256L, 512L, 1024L)[
    c(128L, 256L, 512L, 1024L) <= n
  ], n)))
  for (query_n in query_sizes) {
    subsample_repeats <- if (query_n == n) 1L else 50L
    for (subsample_repeat in seq_len(subsample_repeats)) {
      sample_seed <- seed_from(key_for(meta), query_n, subsample_repeat)
      indices <- if (query_n == n) seq_len(n) else with_local_seed(
        sample_seed, sample.int(n, query_n, replace = FALSE)
      )
      selected <- recall[indices]
      for (bootstrap_resamples in c(1000L, 5000L)) {
        lcb <- query_bootstrap_lcb(
          selected, confidence = 0.95, resamples = bootstrap_resamples,
          seed = seed_from(key_for(meta), query_n, subsample_repeat,
                           bootstrap_resamples)
        )
        rows[[length(rows) + 1L]] <- data.frame(
          dataset = meta$dataset,
          backend = meta$backend,
          metric = meta$metric,
          k = meta$k,
          target_recall = meta$target_recall,
          method_id = meta$method_id,
          validation_seed = meta$validation_seed,
          audited_queries_available = n,
          audited_queries_used = query_n,
          subsample_repeat = subsample_repeat,
          bootstrap_resamples = bootstrap_resamples,
          mean_tie_aware_recall = mean(selected),
          p05_tie_aware_recall = unname(stats::quantile(
            selected, 0.05, names = FALSE, type = 8
          )),
          minimum_tie_aware_recall = min(selected),
          empirical_query_bootstrap_lcb = lcb,
          target_met = lcb >= as.numeric(meta$target_recall),
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
raw <- do.call(rbind, rows)

summary_keys <- c("dataset", "backend", "metric", "k", "target_recall",
                  "audited_queries_used", "bootstrap_resamples")
groups <- split(raw, interaction(raw[summary_keys], drop = TRUE,
                                 lex.order = TRUE))
summary <- do.call(rbind, lapply(groups, function(z) data.frame(
  z[1L, summary_keys, drop = FALSE],
  independent_query_seeds = length(unique(z$validation_seed)),
  subsample_evaluations = nrow(z),
  median_lcb = stats::median(z$empirical_query_bootstrap_lcb),
  minimum_lcb = min(z$empirical_query_bootstrap_lcb),
  target_attainment_fraction = mean(z$target_met),
  median_query_recall_p05 = stats::median(z$p05_tie_aware_recall),
  stringsAsFactors = FALSE
)))
row.names(summary) <- NULL

utils::write.csv(raw, file.path(out_dir, "jss_recall_sensitivity_raw.csv"),
                 row.names = FALSE)
utils::write.csv(
  summary, file.path(out_dir, "jss_recall_sensitivity_summary.csv"),
  row.names = FALSE
)

full <- raw[raw$audited_queries_used == raw$audited_queries_available, ]
decision_key <- c("dataset", "backend", "metric", "k", "target_recall",
                  "method_id", "validation_seed")
wide <- reshape(
  full[c(decision_key, "bootstrap_resamples", "target_met")],
  idvar = decision_key, timevar = "bootstrap_resamples", direction = "wide"
)
changes <- if (all(c("target_met.1000", "target_met.5000") %in% names(wide))) {
  sum(wide$target_met.1000 != wide$target_met.5000, na.rm = TRUE)
} else NA_integer_
report <- c(
  "# Recall sensitivity audit", "",
  sprintf("Selected datasets: %s.", paste(datasets, collapse = ", ")),
  sprintf("Independent dataset/backend/metric/k/target/seed records: %d.",
          length(records)),
  "Query-count sensitivity uses 50 deterministic without-replacement",
  "subsamples at each size below the available audited-query count.",
  sprintf("Full-sample target decisions changed between 1,000 and 5,000 bootstrap resamples: %s.",
          as.character(changes)), "",
  "These are empirical query-bootstrap diagnostics for uniformly sampled",
  "audited rows; they are not distribution-free or cluster-stratified bounds."
)
writeLines(report, file.path(out_dir, "JSS_RECALL_SENSITIVITY_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
