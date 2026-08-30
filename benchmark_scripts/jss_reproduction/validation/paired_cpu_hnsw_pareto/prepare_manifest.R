#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
out <- sub("^--out=", "", args[grepl("^--out=", args)])
if (length(out) != 1L || !nzchar(out)) stop("Provide --out=<manifest.csv>.")

datasets <- c(
  "COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
  "flow18", "MNIST", "imagenet", "MetRef", "mass41"
)
comparators <- c("BiocNeighbors_hnsw", "RcppHNSW_hnsw")
k_values <- c(15L, 30L, 50L, 100L)

rows <- list()
for (dataset in datasets) for (k in k_values) for (comparator in comparators) {
  search_values <- c(
    max(k, 50L), max(2L * k, 100L), max(4L * k, 200L),
    max(8L * k, 400L), max(16L * k, 800L)
  )
  for (ef_search in search_values) {
    rows[[length(rows) + 1L]] <- data.frame(
      experiment = "ef_search_curve", dataset = dataset, k = k,
      comparator = comparator, hnsw_m = 16L, ef_construction = 200L,
      ef_search = ef_search, stringsAsFactors = FALSE
    )
  }
  if (k == 30L) for (ef_construction in c(100L, 400L)) {
    for (ef_search in c(100L, 200L, 400L, 800L)) {
      rows[[length(rows) + 1L]] <- data.frame(
        experiment = "construction_sensitivity", dataset = dataset, k = k,
        comparator = comparator, hnsw_m = 16L,
        ef_construction = ef_construction, ef_search = ef_search,
        stringsAsFactors = FALSE
      )
    }
  }
}
manifest <- do.call(rbind, rows)
manifest$task_id <- seq_len(nrow(manifest))
manifest <- manifest[, c("task_id", setdiff(names(manifest), "task_id"))]
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
write.csv(manifest, out, row.names = FALSE)
cat("Wrote", nrow(manifest), "calibration tasks to", out, "\n")
