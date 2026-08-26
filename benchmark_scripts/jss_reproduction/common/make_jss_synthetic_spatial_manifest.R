#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x) || !length(x) || !nzchar(x[[1L]])) y else x
parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    bits <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[bits[[1L]]]] <- paste(bits[-1L], collapse = "=")
  }
  out
}

opts <- parse_args(args)
out_dir <- normalizePath(
  opts$out_dir %||% file.path(getwd(), "Data", "JSS_synthetic_spatial"),
  mustWork = FALSE
)
manifest_path <- normalizePath(
  opts$manifest %||% file.path(out_dir, "jss_synthetic_spatial_manifest.csv"),
  mustWork = FALSE
)
seed <- as.integer(opts$seed %||% 20260713L)

if (!requireNamespace("float", quietly = TRUE)) {
  stop("The publication synthetic-data generator requires the optional `float` package.", call. = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

rows <- lapply(c(2L, 3L), function(p) {
  n <- 10000L
  set.seed(seed + p)
  x <- matrix(stats::rnorm(n * p), nrow = n, ncol = p)
  x <- x / pmax(sqrt(rowSums(x * x)), sqrt(.Machine$double.eps))
  dataset_name <- sprintf("synthetic_spatial_n%d_p%d_unit", n, p)
  path <- file.path(out_dir, paste0(dataset_name, "_float32.RData"))
  dataset <- list(data = float::fl(x), labels = factor(rep("synthetic", n)))
  save(dataset, file = path, compress = "xz")
  data.frame(
    dataset = dataset_name,
    path = normalizePath(path, mustWork = TRUE),
    n = n,
    p = p,
    input_type = "float32",
    suite = "spatial",
    norm_model = "unit",
    norm_mean = 1,
    norm_sd = 0,
    norm_cv = 0,
    stringsAsFactors = FALSE
  )
})

utils::write.csv(do.call(rbind, rows), manifest_path, row.names = FALSE)
cat(manifest_path, "\n", sep = "")
