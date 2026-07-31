#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) {
      paste(parts[-1L], collapse = "=")
    } else {
      "TRUE"
    }
  }
  out
}

split_values <- function(x, default = "") {
  values <- trimws(strsplit(x %||% default, ",", fixed = TRUE)[[1L]])
  values[nzchar(values)]
}

main <- function() {
  args <- parse_args()
  backend <- tolower(args$backend %||% "cpu")
  if (!backend %in% c("cpu", "cuda")) stop("Invalid backend.", call. = FALSE)
  methods <- split_values(
    args$methods,
    if (backend == "cuda") {
      "auto,bruteforce,exact,flat,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana,cagra,grid"
    } else {
      "auto,bruteforce,exact,flat,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana,grid"
    }
  )
  metrics <- split_values(
    args$metrics, "euclidean,cosine,correlation,inner_product"
  )
  out_dir <- args$out_dir %||% file.path(getwd(), "package_route_qa")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  suppressPackageStartupMessages(library(faissR))
  if (!isTRUE(faissR::faiss_available())) {
    stop("Mandatory FAISS provider is unavailable.", call. = FALSE)
  }
  if (backend == "cuda" && !isTRUE(faissR::cuda_available())) {
    stop("CUDA route QA requested but CUDA is unavailable.", call. = FALSE)
  }

  set.seed(20260730)
  x <- matrix(rnorm(1024L * 19L), nrow = 1024L, ncol = 19L)
  rows <- seq_len(64L)
  points <- x[rows, , drop = FALSE]
  results <- list()
  for (method in methods) {
    for (metric in metrics) {
      if (identical(method, "grid") && !identical(metric, "euclidean")) next
      route_x <- if (identical(method, "grid")) x[, seq_len(2L), drop = FALSE] else x
      route_points <- route_x[rows, , drop = FALSE]
      started <- proc.time()[["elapsed"]]
      answer <- tryCatch(
        faissR::nn(
          route_x,
          points = route_points,
          k = 15L,
          exclude_self = FALSE,
          backend = backend,
          method = method,
          metric = metric,
          tuning = "auto",
          target_recall = 0.99,
          n_threads = if (backend == "cpu") 12L else 2L,
          output = "double"
        ),
        error = function(e) e
      )
      elapsed <- proc.time()[["elapsed"]] - started
      if (inherits(answer, "error")) {
        row <- data.frame(
          backend = backend, method = method, metric = metric,
          status = "failed", elapsed_sec = elapsed,
          dimensions_pass = FALSE, finite_distance_pass = FALSE,
          sorted_distance_pass = FALSE, route_pass = FALSE,
          resolved_backend = NA_character_, requested_method = method,
          error = conditionMessage(answer), stringsAsFactors = FALSE
        )
      } else {
        indices <- as.matrix(answer$indices %||% answer$idx)
        distances <- as.matrix(answer$distances %||% answer$dist)
        resolved <- answer$backend_used %||% attr(answer, "backend") %||%
          attr(answer, "resolved_backend") %||% NA_character_
        route_pass <- if (backend == "cuda") {
          grepl("cuda|gpu|cuvs|cagra", resolved, ignore.case = TRUE)
        } else {
          !grepl("cuda|gpu|cuvs|cagra", resolved, ignore.case = TRUE)
        }
        row <- data.frame(
          backend = backend, method = method, metric = metric,
          status = "success", elapsed_sec = elapsed,
          dimensions_pass = identical(dim(indices), c(64L, 15L)) &&
            identical(dim(distances), c(64L, 15L)),
          finite_distance_pass = all(is.finite(distances)),
          sorted_distance_pass = all(apply(
            distances, 1L,
            function(z) all(diff(z[is.finite(z)]) >= -1e-7)
          )),
          route_pass = route_pass,
          resolved_backend = resolved,
          requested_method = method,
          error = "", stringsAsFactors = FALSE
        )
      }
      results[[length(results) + 1L]] <- row
    }
  }
  table <- do.call(rbind, results)
  table$conformance_pass <- with(
    table,
    status == "success" & dimensions_pass & finite_distance_pass &
      sorted_distance_pass & route_pass
  )
  write.csv(
    table, file.path(out_dir, "jss_package_route_qa.csv"), row.names = FALSE
  )
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  writeLines(
    capture.output(print(faissR::backend_info())),
    file.path(out_dir, "faissR_backend_info.txt")
  )
  if (any(!table$conformance_pass)) {
    stop(
      sum(!table$conformance_pass),
      " package route-QA cells failed; inspect jss_package_route_qa.csv.",
      call. = FALSE
    )
  }
}

main()
