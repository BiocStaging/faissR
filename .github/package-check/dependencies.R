# Install only missing test dependencies into a dedicated lab library.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
dir.create(args[[1]], recursive = TRUE, showWarnings = FALSE)
.libPaths(c(normalizePath(args[[1]]), .libPaths()))
options(repos = c(CRAN = "https://cloud.r-project.org"))
cran <- c("Rcpp", "testthat", "withr", "float", "Matrix", "knitr",
    "rmarkdown", "BiocManager")
missing <- cran[!vapply(cran, requireNamespace, logical(1), quietly = TRUE)]
if (requireNamespace("Rcpp", quietly = TRUE) && packageVersion("Rcpp") < "1.1.0") {
    missing <- union(missing, "Rcpp")
}
if (length(missing)) install.packages(missing, lib = .libPaths()[1L])
bioc <- c("Biobase", "BiocStyle")
missing <- bioc[!vapply(bioc, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
    BiocManager::install(missing, lib = .libPaths()[1L], update = FALSE, ask = FALSE)
}
stopifnot(all(vapply(c(cran, bioc), requireNamespace, logical(1), quietly = TRUE)))
print(sessionInfo())
