#!/usr/bin/env Rscript

for (package in c("ALL", "Biobase")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Install the Bioconductor ", package, " package to run this example.",
         call. = FALSE)
  }
}

library(faissR)
data("ALL", package = "ALL")
expression <- Biobase::exprs(ALL)

# Treat probes as observations and patients as features (12,625 x 128).
x <- scale(expression)
storage.mode(x) <- "double"

k <- 15L
threads <- 4L
targets <- c(0.90, 0.95, 0.99)
repeats <- 3L

recall_at_k <- function(reference, candidate) {
  mean(vapply(seq_len(nrow(reference)), function(i) {
    length(intersect(reference[i, ], candidate[i, ])) / ncol(reference)
  }, numeric(1)))
}

exact_sec <- system.time({
  exact <- nn(
    x, k = k, exclude_self = TRUE,
    backend = "cpu", method = "exact", metric = "euclidean",
    n_threads = threads
  )
})[["elapsed"]]

hnsw_rows <- lapply(targets, function(target) {
  elapsed <- system.time({
    candidate <- nn(
      x, k = k, exclude_self = TRUE,
      backend = "cpu", method = "hnsw", metric = "euclidean",
      tuning = "auto", target_recall = target,
      n_threads = threads
    )
  })[["elapsed"]]
  approximation <- attr(candidate, "approximation")
  data.frame(
    target_recall = target,
    method = "hnsw",
    executed_backend = attr(candidate, "backend_used"),
    elapsed_sec = elapsed,
    observed_recall_at_15 = recall_at_k(exact$indices, candidate$indices),
    calibration_evidence_target_met = approximation$tuning_benchmark_target_met,
    evidence_source = approximation$tuning_benchmark_source,
    stringsAsFactors = FALSE
  )
})
hnsw_results <- do.call(rbind, hnsw_rows)

# Demonstrate reusable fitted HNSW prediction on patients using B/T lineage.
probe_variance <- apply(expression, 1L, stats::var)
selected_probes <- order(probe_variance, decreasing = TRUE)[seq_len(128L)]
patient_x <- scale(t(expression[selected_probes, , drop = FALSE]))
storage.mode(patient_x) <- "double"
y <- droplevels(Biobase::pData(ALL)$BT)
test <- seq.int(4L, nrow(patient_x), by = 4L)
train <- setdiff(seq_len(nrow(patient_x)), test)

build_sec <- system.time({
  model <- knn(
    patient_x[train, , drop = FALSE], y[train],
    k = 5L, backend = "cpu", method = "hnsw",
    metric = "euclidean", tuning = "auto", target_recall = 0.99,
    n_threads = threads
  )
})[["elapsed"]]

first_query_sec <- system.time({
  fitted_prediction <- predict(model, patient_x[test, , drop = FALSE])
})[["elapsed"]]

warm_times <- numeric(repeats)
for (r in seq_len(repeats)) {
  warm_times[[r]] <- system.time({
    fitted_prediction <- predict(model, patient_x[test, , drop = FALSE])
  })[["elapsed"]]
}
query_meta <- attr(fitted_prediction, "faissR_nn")

reuse_results <- data.frame(
  method = "hnsw",
  build_sec = build_sec,
  first_query_sec = first_query_sec,
  median_reused_predict_sec = stats::median(warm_times),
  test_accuracy = mean(fitted_prediction == y[test]),
  query_source = query_meta$query_source,
  batch_query = query_meta$batch_query,
  query_n = query_meta$query_n,
  stringsAsFactors = FALSE
)

cat("Probe matrix dimensions:", paste(dim(x), collapse = " x "), "\n")
cat("Exact elapsed (s):", exact_sec, "\n")
print(hnsw_results, row.names = FALSE)
print(reuse_results, row.names = FALSE)

out_dir <- Sys.getenv("FAISSR_JSS_EXAMPLE_OUT", unset = "")
if (nzchar(out_dir)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(
    hnsw_results, file.path(out_dir, "all_hnsw_results.csv"),
    row.names = FALSE
  )
  write.csv(
    reuse_results, file.path(out_dir, "all_reuse_results.csv"),
    row.names = FALSE
  )
  writeLines(
    c(
      paste0("faissR_version=", as.character(packageVersion("faissR"))),
      paste0("ALL_version=", as.character(packageVersion("ALL"))),
      paste0("Biobase_version=", as.character(packageVersion("Biobase"))),
      paste0("exact_elapsed_sec=", exact_sec),
      paste0("R_version=", R.version.string)
    ),
    file.path(out_dir, "all_example_provenance.txt")
  )
}
