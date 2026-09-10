print(sessionInfo())
print(.libPaths())
p <- installed.packages()
print(p[intersect(c("Rcpp", "Biobase", "testthat", "withr", "float",
    "Matrix", "knitr", "rmarkdown", "BiocStyle"), rownames(p)),
    c("Package", "Version", "Built")])
