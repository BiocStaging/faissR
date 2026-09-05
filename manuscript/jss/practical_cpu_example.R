#!/usr/bin/env Rscript

# Compact biological example; timings illustrate the API, not provider ranking.
library(faissR)
data("sample.ExpressionSet", package = "Biobase")
expression_data <- Biobase::exprs(sample.ExpressionSet)
x <- scale(expression_data)
set.seed(1)
targets <- c(0.90, 0.95, 0.99)
recall_at_k <- function(reference, candidate) {
    mean(vapply(seq_len(nrow(reference)), function(i) {
        length(intersect(reference[i, ], candidate[i, ])) / ncol(reference)
    }, numeric(1)))
}
exact <- nn(x, k = 15, exclude_self = TRUE, backend = "cpu",
            method = "exact", metric = "euclidean", n_threads = 1)
hnsw_results <- do.call(rbind, lapply(targets, function(tier) {
    candidate <- nn(x, k = 15, exclude_self = TRUE, backend = "cpu",
                    method = "hnsw", metric = "euclidean", n_threads = 1,
                    tuning = "auto", target_recall = tier)
    data.frame(requested_tier = tier,
               observed_recall = recall_at_k(exact$indices, candidate$indices),
               provider = attr(candidate, "backend_used"))
}))

# Feature selection and scaling use training samples only.
y <- droplevels(Biobase::pData(sample.ExpressionSet)$type)
test <- seq.int(4L, ncol(expression_data), by = 4L)
train <- setdiff(seq_len(ncol(expression_data)), test)
variance <- apply(expression_data[, train, drop = FALSE], 1L, var)
keep <- head(order(variance, decreasing = TRUE), 128L)
training <- scale(t(expression_data[keep, train, drop = FALSE]))
queries <- scale(t(expression_data[keep, test, drop = FALSE]),
                 center = attr(training, "scaled:center"),
                 scale = attr(training, "scaled:scale"))
build_sec <- system.time(model <- knn(
    training, y[train], k = 5, backend = "cpu", method = "hnsw",
    metric = "euclidean", n_threads = 1
))[["elapsed"]]
first_sec <- system.time(prediction <- predict(model, queries))[["elapsed"]]
times <- replicate(3, system.time(
    prediction <- predict(model, queries)
)[["elapsed"]])
route <- attr(prediction, "faissR_nn")
stopifnot(identical(route$query_source, "fitted_index"))
reuse_results <- data.frame(build_sec = build_sec, first_sec = first_sec,
                           median_reused_sec = median(times),
                           query_source = route$query_source)
cat("Probe-by-sample matrix:", paste(dim(x), collapse = " x "), "\n")
print(hnsw_results, row.names = FALSE, digits = 3)
print(reuse_results, row.names = FALSE, digits = 3)

out_dir <- Sys.getenv("FAISSR_JSS_EXAMPLE_OUT", unset = "")
if (nzchar(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    write.csv(hnsw_results, file.path(out_dir, "biobase_hnsw_results.csv"),
              row.names = FALSE)
    write.csv(reuse_results, file.path(out_dir, "biobase_reuse_results.csv"),
              row.names = FALSE)
    writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
    output <- capture.output({
        print(hnsw_results, row.names = FALSE, digits = 3)
        print(reuse_results, row.names = FALSE, digits = 3)
    })
    writeLines(c("\\begin{CodeChunk}", "\\begin{CodeOutput}", output,
                 "\\end{CodeOutput}", "\\end{CodeChunk}"),
               file.path(out_dir, "practical_cpu_output.tex"))
}
