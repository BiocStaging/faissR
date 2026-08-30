library(faissR)

stopifnot(faiss_available())
set.seed(19)
x <- matrix(rnorm(4096), ncol = 16)

for (method in c("exact", "hnsw")) {
    ans <- nn(
        x,
        k = 10,
        exclude_self = TRUE,
        method = method,
        backend = "cpu",
        metric = "euclidean",
        n_threads = 2
    )
    stopifnot(
        identical(dim(ans$indices), c(nrow(x), 10L)),
        all(is.finite(ans$distances))
    )
}
