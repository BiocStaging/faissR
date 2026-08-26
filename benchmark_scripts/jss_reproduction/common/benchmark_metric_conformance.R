#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
  }
  out
}

split_values <- function(x, default) {
  trimws(strsplit(x %||% default, ",", fixed = TRUE)[[1L]])
}

normalize_rows <- function(x, center = FALSE) {
  if (center) x <- x - rowMeans(x)
  norm <- sqrt(rowSums(x * x))
  ok <- is.finite(norm) & norm > 0
  out <- matrix(0, nrow(x), ncol(x))
  out[ok, ] <- x[ok, , drop = FALSE] / norm[ok]
  out
}

exact_reference <- function(x, k, metric) {
  if (metric == "euclidean") {
    sq <- rowSums(x * x)
    value <- outer(sq, sq, "+") - 2 * tcrossprod(x)
    value[value < 0 & value > -1e-9] <- 0
    diag(value) <- Inf
    decreasing <- FALSE
  } else {
    transformed <- switch(
      metric,
      cosine = normalize_rows(x),
      correlation = normalize_rows(x, center = TRUE)
    )
    value <- tcrossprod(transformed)
    diag(value) <- -Inf
    decreasing <- TRUE
  }
  indices <- t(vapply(seq_len(nrow(x)), function(i) {
    head(order(value[i, ], decreasing = decreasing, na.last = NA), k)
  }, integer(k)))
  list(indices = indices, values = value, decreasing = decreasing)
}

recall_at_k <- function(observed, reference) {
  observed <- as.matrix(observed)
  reference <- as.matrix(reference)
  mean(vapply(seq_len(nrow(reference)), function(i) {
    length(intersect(observed[i, ], reference[i, ])) / ncol(reference)
  }, numeric(1)))
}

route_metadata <- function(result) {
  list(
    backend = result$backend_used %||% attr(result, "backend_used") %||% NA_character_,
    method = result$method %||% attr(result, "method") %||% NA_character_,
    requested_method = result$requested_method %||% attr(result, "requested_method") %||% NA_character_
  )
}

backend_route_pass <- function(route, backend) {
  value <- tolower(as.character(route %||% ""))
  if (!nzchar(value)) return(FALSE)
  if (backend == "cuda") grepl("cuda|gpu|cuvs", value) else !grepl("cuda|gpu|cuvs", value)
}

metric_transform <- function(x, metric) {
  if (metric == "euclidean") {
    shift <- seq_len(ncol(x)) / 13
    return(sweep(x, 2L, shift, "+"))
  }
  if (metric == "cosine") {
    scale <- seq(0.25, 3, length.out = nrow(x))
    return(x * scale)
  }
  if (metric == "correlation") {
    scale <- seq(0.5, 2.5, length.out = nrow(x))
    shift <- seq(-3, 3, length.out = nrow(x))
    return(x * scale + shift)
  }
  x
}

valid_non_degenerate_rows <- function(x, metric) {
  if (metric == "cosine") return(which(rowSums(x * x) > 1e-12))
  if (metric == "correlation") return(which(rowSums((x - rowMeans(x))^2) > 1e-12))
  seq_len(nrow(x))
}

run_case <- function(x, backend, method, metric, k, threads, target_recall) {
  started <- proc.time()[["elapsed"]]
  base <- data.frame(
    backend = backend, method = method, metric = metric, n = nrow(x), p = ncol(x), k = k,
    faissR_version = as.character(utils::packageVersion("faissR")),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
    target_recall = target_recall, status = "failed", elapsed_sec = NA_real_,
    recall_at_k = NA_real_, target_recall_pass = NA,
    invariant_recall = NA_real_, dimensions_pass = FALSE,
    finite_distance_pass = FALSE, sorted_distance_pass = FALSE,
    degenerate_row_pass = NA,
    route_pass = FALSE, resolved_backend = NA_character_, resolved_method = NA_character_,
    requested_method = NA_character_, metric_contract_pass = FALSE,
    conformance_pass = FALSE, quality_status = "not_evaluated", error = "",
    stringsAsFactors = FALSE
  )
  tryCatch({
    reference <- exact_reference(x, k, metric)
    result <- faissR::nn(
      x, k = k, exclude_self = TRUE, backend = backend, method = method,
      metric = metric, tuning = "auto", target_recall = target_recall,
      output = "double", n_threads = threads
    )
    base$elapsed_sec <- proc.time()[["elapsed"]] - started
    indices <- as.matrix(result$indices)
    distances <- as.matrix(result$distances)
    base$dimensions_pass <- identical(dim(indices), c(nrow(x), k)) &&
      identical(dim(distances), c(nrow(x), k))
    base$finite_distance_pass <- all(is.finite(distances))
    base$sorted_distance_pass <- all(apply(distances, 1L, function(v) all(diff(v) >= -1e-5)))
    base$recall_at_k <- recall_at_k(indices, reference$indices)
    base$target_recall_pass <- is.finite(base$recall_at_k) &&
      base$recall_at_k + 1e-12 >= target_recall

    transformed <- metric_transform(x, metric)
    transformed_result <- faissR::nn(
      transformed, k = k, exclude_self = TRUE, backend = backend, method = method,
      metric = metric, tuning = "auto", target_recall = target_recall,
      output = "double", n_threads = threads
    )
    rows <- valid_non_degenerate_rows(x, metric)
    base$invariant_recall <- recall_at_k(
      as.matrix(transformed_result$indices)[rows, , drop = FALSE],
      indices[rows, , drop = FALSE]
    )
    meta <- route_metadata(result)
    base$resolved_backend <- meta$backend
    base$resolved_method <- meta$method
    base$requested_method <- meta$requested_method
    base$route_pass <- backend_route_pass(meta$backend, backend)
    exact_family <- method %in% c("exact", "flat", "bruteforce")
    invariant_ok <- !exact_family ||
      is.finite(base$invariant_recall) && base$invariant_recall >= 0.99
    base$metric_contract_pass <- base$dimensions_pass && base$finite_distance_pass &&
      base$sorted_distance_pass && base$route_pass && invariant_ok
    base$conformance_pass <- base$metric_contract_pass
    base$quality_status <- if (base$target_recall_pass) "target_met" else "target_miss"
    base$status <- if (base$conformance_pass) "success" else "contract_failure"
    base
  }, error = function(e) {
    base$elapsed_sec <- proc.time()[["elapsed"]] - started
    base$status <- if (grepl("not support|unsupported|unavailable|only", conditionMessage(e), ignore.case = TRUE)) {
      "unsupported"
    } else {
      "failed"
    }
    base$error <- conditionMessage(e)
    base
  })
}

run_degenerate_case <- function(backend, method, metric, k, threads, target_recall) {
  set.seed(20260723 + match(metric, c("cosine", "correlation")))
  # Keep the fixture above the 624-row minimum required by CPU IVFPQ routes.
  x <- matrix(rnorm(1024L * 19L), nrow = 1024L, ncol = 19L)
  edge_kind <- if (metric == "cosine") "zero_norm_row" else "constant_row"
  if (metric == "cosine") x[1L, ] <- 0 else x[1L, ] <- 2.5
  base <- data.frame(
    backend = backend, method = method, metric = metric, edge_kind = edge_kind,
    n = nrow(x), p = ncol(x), k = k, target_recall = target_recall,
    faissR_version = as.character(utils::packageVersion("faissR")),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
    status = "failed", behavior = NA_character_, dimensions_pass = FALSE,
    finite_distance_pass = FALSE, route_pass = FALSE,
    resolved_backend = NA_character_, explicit_no_cpu_repair_error = FALSE,
    conformance_pass = FALSE, error = "", stringsAsFactors = FALSE
  )
  tryCatch({
    result <- faissR::nn(
      x, k = k, exclude_self = TRUE, backend = backend, method = method,
      metric = metric, tuning = "auto", target_recall = target_recall,
      output = "double", n_threads = threads
    )
    indices <- as.matrix(result$indices)
    distances <- as.matrix(result$distances)
    meta <- route_metadata(result)
    base$resolved_backend <- meta$backend
    base$dimensions_pass <- identical(dim(indices), c(nrow(x), k)) &&
      identical(dim(distances), c(nrow(x), k))
    base$finite_distance_pass <- all(is.finite(distances))
    base$route_pass <- backend_route_pass(meta$backend, backend)
    base$behavior <- "finite_backend_result"
    base$conformance_pass <- base$dimensions_pass && base$finite_distance_pass && base$route_pass
    base$status <- if (base$conformance_pass) "success" else "contract_failure"
    base
  }, error = function(e) {
    message_text <- conditionMessage(e)
    explicit <- backend == "cuda" && grepl(
      "does not repair zero-normalized CUDA results on CPU|zero[- ]norm|constant row|undefined",
      message_text,
      ignore.case = TRUE
    )
    base$error <- message_text
    base$explicit_no_cpu_repair_error <- explicit
    base$behavior <- if (explicit) "explicit_error_no_cpu_fallback" else "unexpected_error"
    base$conformance_pass <- explicit
    base$status <- if (explicit) "success" else "failed"
    base
  })
}

main <- function() {
  args <- parse_args()
  backend <- tolower(args$backend %||% "cpu")
  if (!backend %in% c("cpu", "cuda")) stop("`backend` must be cpu or cuda.", call. = FALSE)
  threads <- as.integer(args$threads %||% if (backend == "cpu") 12L else 2L)
  k <- as.integer(args$k %||% 15L)
  target <- as.numeric(args$target_recall %||% 0.99)
  methods <- split_values(
    args$methods,
    if (backend == "cpu") "auto,exact,flat,bruteforce,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana" else
      "auto,exact,flat,bruteforce,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana,cagra"
  )
  metrics <- split_values(args$metrics, "euclidean,cosine,correlation")
  out_dir <- normalizePath(args$out_dir %||% file.path(getwd(), paste0("metric_conformance_", backend)), mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  library(faissR)
  if (!faissR::faiss_available()) stop("FAISS is unavailable.", call. = FALSE)
  if (backend == "cuda" && (!faissR::cuda_available() || !faissR::cuvs_available())) {
    stop("CUDA/cuVS are unavailable.", call. = FALSE)
  }
  value <- as.character(threads)
  Sys.setenv(OMP_NUM_THREADS = value, OPENBLAS_NUM_THREADS = value, MKL_NUM_THREADS = value)

  set.seed(20260720)
  x <- matrix(rnorm(1024L * 19L), nrow = 1024L, ncol = 19L)
  x[1L, ] <- seq_len(ncol(x)) / 7
  rows <- list()
  for (method in methods) {
    for (metric in metrics) {
      message("Conformance: backend=", backend, " method=", method, " metric=", metric)
      rows[[length(rows) + 1L]] <- run_case(x, backend, method, metric, k, threads, target)
    }
  }
  for (dimension in c(2L, 3L)) {
    set.seed(20260720 + dimension)
    spatial <- matrix(runif(257L * dimension), ncol = dimension)
    rows[[length(rows) + 1L]] <- run_case(
      spatial, backend, "grid", "euclidean", k, threads, target
    )
  }
  result <- do.call(rbind, rows)
  edge_rows <- list()
  for (method in methods) {
    for (metric in c("cosine", "correlation")) {
      message("Degenerate-row contract: backend=", backend, " method=", method, " metric=", metric)
      edge_rows[[length(edge_rows) + 1L]] <- run_degenerate_case(
        backend, method, metric, k, threads, target
      )
    }
  }
  edge_result <- do.call(rbind, edge_rows)
  write.csv(result, file.path(out_dir, "jss_metric_conformance.csv"), row.names = FALSE)
  write.csv(result[result$status != "success", , drop = FALSE],
            file.path(out_dir, "jss_metric_conformance_nonpassing.csv"), row.names = FALSE)
  write.csv(result[!is.na(result$target_recall_pass) & !result$target_recall_pass, , drop = FALSE],
            file.path(out_dir, "jss_metric_quality_target_misses.csv"), row.names = FALSE)
  write.csv(edge_result, file.path(out_dir, "jss_metric_degenerate_rows.csv"), row.names = FALSE)
  write.csv(edge_result[edge_result$status != "success", , drop = FALSE],
            file.path(out_dir, "jss_metric_degenerate_rows_nonpassing.csv"), row.names = FALSE)
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  writeLines(c(
    "# Metric conformance report", "",
    paste0("Backend: `", backend, "`."),
    paste0("Successful metric-contract cells: ", sum(result$status == "success"), " / ", nrow(result), "."),
    paste0("Explicitly unsupported cells: ", sum(result$status == "unsupported"), "."),
    paste0("Contract failures: ", sum(result$status == "contract_failure"), "."),
    paste0("Execution failures: ", sum(result$status == "failed"), "."),
    paste0("Recall-target cells passing: ", sum(result$target_recall_pass, na.rm = TRUE),
           " / ", sum(!is.na(result$target_recall_pass)), " evaluated cells."),
    paste0("Recall-target misses: ",
           sum(!is.na(result$target_recall_pass) & !result$target_recall_pass), "."),
    paste0("Recall-target cells not evaluated: ", sum(is.na(result$target_recall_pass)), "."), "",
    paste0("Degenerate-row contract cells passing: ", sum(edge_result$status == "success"),
           " / ", nrow(edge_result), "."),
    paste0("Degenerate CUDA cells reporting the documented no-CPU-repair error: ",
           sum(edge_result$explicit_no_cpu_repair_error), "."), "",
    "The ordinary suite uses non-degenerate data and checks output dimensions, finite distances, ascending faissR distance order, resolved-device identity, exact-reference recall, Euclidean translation invariance, cosine positive-scale invariance, and correlation positive-affine invariance.",
    "",
    "For approximate methods, transform-invariance overlap is diagnostic rather than a metric-contract requirement because quantization, graph search, and nondeterministic GPU training may reorder candidates. Their exact-reference recall and target attainment are reported separately.",
    "",
    "Zero-norm cosine and constant-row correlation behavior is tested separately. A finite result on the requested backend passes. For CUDA routes that deliberately prohibit CPU-side repair, the documented explicit no-CPU-fallback error also passes; an unexpected error or silent backend change does not."
  ), file.path(out_dir, "JSS_METRIC_CONFORMANCE_REPORT.md"))

  required <- result$method %in% c("exact", "flat", "bruteforce")
  bad_required <- required & (result$status != "success" |
    is.na(result$target_recall_pass) | !result$target_recall_pass)
  edge_required <- edge_result$method %in% c("exact", "flat", "bruteforce")
  bad_edge_required <- edge_required & edge_result$status != "success"
  if (any(bad_required) || any(bad_edge_required)) {
    if (any(bad_required)) {
      print(result[bad_required, c(
        "backend", "method", "metric", "status", "resolved_backend",
        "dimensions_pass", "finite_distance_pass", "sorted_distance_pass",
        "recall_at_k", "target_recall_pass", "invariant_recall",
        "route_pass", "error"
      ), drop = FALSE], row.names = FALSE)
    }
    if (any(bad_edge_required)) {
      print(edge_result[bad_edge_required, c(
        "backend", "method", "metric", "edge_kind", "status", "behavior",
        "resolved_backend", "explicit_no_cpu_repair_error", "error"
      ), drop = FALSE], row.names = FALSE)
    }
    stop(
      sum(bad_required) + sum(bad_edge_required),
      " required exact-family metric contract cells did not pass; see printed details and CSV evidence.",
      call. = FALSE
    )
  }
}

main()
