#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- if (length(pair) > 1L) {
      paste(pair[-1L], collapse = "=")
    } else {
      "TRUE"
    }
  }
  out
}

split_values <- function(x) {
  values <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  values[nzchar(values)]
}

load_matrix <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  candidates <- if (exists("dataset", env, inherits = FALSE)) {
    c("dataset", setdiff(ls(env), "dataset"))
  } else {
    ls(env)
  }
  for (name in candidates) {
    object <- get(name, env, inherits = FALSE)
    if (is.list(object) && !is.null(object$data)) return(object$data)
  }
  stop("No list containing `$data` was found in ", path, call. = FALSE)
}

load_reference <- function(data_path, metric, seed) {
  stem <- tools::file_path_sans_ext(basename(data_path))
  prefix <- if (startsWith(stem, "synthetic_")) paste0(stem, "__") else ""
  path <- file.path(
    dirname(data_path),
    sprintf(
      "%sfaissR_exact_reference_%s_k100_q1024_seed%d.RData",
      prefix, metric, seed
    )
  )
  if (!file.exists(path)) stop("Missing exact reference: ", path, call. = FALSE)
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  reference <- get("faissR_reference", env, inherits = FALSE)
  if (!identical(reference$status, "success")) {
    stop("Exact reference is not successful: ", path, call. = FALSE)
  }
  reference$path <- path
  reference
}

clear_index_caches <- function() {
  ns <- asNamespace("faissR")
  for (name in c(
    ".faissR_fitted_nn_index_cache",
    ".faissR_cuvs_ivfpq_index_cache"
  )) {
    if (!exists(name, ns, inherits = FALSE)) next
    cache <- get(name, ns, inherits = FALSE)
    keys <- setdiff(ls(cache, all.names = TRUE), ".keys")
    if (length(keys)) rm(list = keys, envir = cache)
    cache$.keys <- character()
  }
  invisible(NULL)
}

standardize <- function(x) {
  indices <- x$indices %||% x$index %||% x$idx %||% x$nn.idx
  distances <- x$distances %||% x$distance %||% x$dist %||% x$nn.dists
  if (is.null(indices) || is.null(distances)) {
    stop("KNN output lacks indices or distances.", call. = FALSE)
  }
  list(indices = as.matrix(indices), distances = as.matrix(distances))
}

remove_known_self <- function(result, rows, k) {
  result <- standardize(result)
  out_i <- matrix(NA_integer_, nrow = length(rows), ncol = k)
  out_d <- matrix(NA_real_, nrow = length(rows), ncol = k)
  for (i in seq_along(rows)) {
    keep <- which(!is.na(result$indices[i, ]) & result$indices[i, ] != rows[[i]])
    take <- head(keep, k)
    if (length(take)) {
      out_i[i, seq_along(take)] <- result$indices[i, take]
      out_d[i, seq_along(take)] <- result$distances[i, take]
    }
  }
  list(indices = out_i, distances = out_d)
}

recall_rows <- function(observed, expected) {
  vapply(seq_len(nrow(expected)), function(i) {
    truth <- expected[i, !is.na(expected[i, ])]
    found <- observed[i, !is.na(observed[i, ])]
    if (!length(truth)) return(NA_real_)
    length(intersect(truth, found)) / length(truth)
  }, numeric(1L))
}

metadata_value <- function(result, name, default = NA) {
  direct <- result[[name]] %||% attr(result, name, exact = TRUE)
  if (!is.null(direct) && length(direct)) return(direct[[1L]])
  for (attribute in c("faiss", "cuda", "tuning", "auto_selection")) {
    object <- attr(result, attribute, exact = TRUE)
    value <- if (is.list(object)) object[[name]] else NULL
    if (!is.null(value) && length(value)) return(value[[1L]])
  }
  default
}

run_search <- function(x, rows, mode, backend, method, metric, k, threads,
                       target_recall) {
  full <- identical(mode, "full")
  call <- list(
    data = x,
    k = if (full) k else k + 1L,
    exclude_self = full,
    backend = backend,
    method = method,
    metric = metric,
    tuning = "auto",
    target_recall = target_recall,
    n_threads = threads
  )
  if (!full) call$points <- x[rows, , drop = FALSE]
  started <- proc.time()[["elapsed"]]
  result <- do.call(faissR::nn, call)
  elapsed <- proc.time()[["elapsed"]] - started
  list(result = result, elapsed = elapsed)
}

quality_for_result <- function(result, rows, mode, reference, k) {
  observed <- standardize(result)
  ref_position <- match(rows, reference$rows)
  if (anyNA(ref_position)) stop("Query rows are absent from exact reference.")
  if (identical(mode, "full")) {
    observed$indices <- observed$indices[rows, seq_len(k), drop = FALSE]
  } else {
    observed <- remove_known_self(observed, rows, k)
  }
  expected <- reference$indices[ref_position, seq_len(k), drop = FALSE]
  recalls <- recall_rows(observed$indices, expected)
  c(mean = mean(recalls, na.rm = TRUE), minimum = min(recalls, na.rm = TRUE))
}

result_row <- function(dataset, backend, method, metric, k, mode, requested_m,
                       actual_m, method_position, repeat_id, phase, elapsed,
                       quality, result, reference, error = "") {
  resolved_method <- metadata_value(result, "method", NA)
  if (is.na(resolved_method) || !nzchar(as.character(resolved_method))) {
    resolved_method <- metadata_value(result, "predicted_method", method)
  }
  data.frame(
    dataset = dataset,
    backend = backend,
    requested_method = method,
    resolved_method = as.character(resolved_method),
    resolved_backend = as.character(metadata_value(result, "backend_used", NA)),
    metric = metric,
    k = k,
    query_mode = if (identical(mode, "full")) "self_search" else "explicit_query_matrix",
    requested_m = requested_m,
    actual_m = actual_m,
    method_position = method_position,
    repeat_id = repeat_id,
    phase = phase,
    elapsed_sec = elapsed,
    mean_recall_at_k = unname(quality[["mean"]]),
    min_query_recall_at_k = unname(quality[["minimum"]]),
    index_cache_hit = isTRUE(metadata_value(result, "index_cache_hit", FALSE)),
    persistent_index_cache = isTRUE(metadata_value(result, "persistent_index_cache", FALSE)),
    reference_path = reference$path,
    faissR_version = as.character(utils::packageVersion("faissR")),
    package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    status = if (nzchar(error)) "failed" else "success",
    error = error,
    stringsAsFactors = FALSE
  )
}

append_csv <- function(x, path) {
  utils::write.table(
    x, path, sep = ",", row.names = FALSE,
    col.names = !file.exists(path), append = file.exists(path), quote = TRUE,
    na = ""
  )
}

main <- function() {
  args <- parse_args()
  manifest <- utils::read.csv(args$manifest, stringsAsFactors = FALSE)
  dataset <- args$dataset
  row <- manifest[manifest$dataset == dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset must match one manifest row: ", dataset)
  candidates <- c("path", "output", "file", "file_path", "rdata_path")
  path_column <- intersect(candidates, names(row))[[1L]]
  data_path <- row[[path_column]][[1L]]
  x <- load_matrix(data_path)
  n <- nrow(x)
  backend <- args$backend
  metric <- args$metric %||% "euclidean"
  k <- as.integer(args$k %||% 30L)
  threads <- as.integer(args$threads %||% if (backend == "cuda") 2L else 12L)
  repeats <- as.integer(args$repeats %||% 3L)
  seed <- as.integer(args$seed %||% 20260807L)
  target <- as.numeric(args$target_recall %||% 0.99)
  methods <- split_values(args$methods)
  requested_sizes <- split_values(args$query_sizes %||% "1,32,1024,full")
  full_allowed <- dataset %in% split_values(args$full_datasets %||% "MetRef,COIL20,MNIST")
  reference <- load_reference(data_path, metric, seed)
  out_dir <- args$out_dir
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(out_dir, "jss_query_workload_raw.csv")

  set.seed(seed + nchar(dataset))
  ordered_rows <- sample(reference$rows, length(reference$rows), replace = FALSE)
  for (size in requested_sizes) {
    if (identical(size, "full") && !full_allowed) next
    mode <- if (identical(size, "full")) "full" else "sample"
    requested_m <- if (identical(size, "full")) n else as.integer(size)
    rows <- if (identical(mode, "full")) reference$rows else head(ordered_rows, requested_m)
    actual_m <- if (identical(mode, "full")) n else length(rows)
    method_order <- sample(methods, length(methods), replace = FALSE)
    for (method_position in seq_along(method_order)) {
      method <- method_order[[method_position]]
      clear_index_caches()
      for (repeat_id in seq_len(repeats)) {
        phase <- if (repeat_id == 1L) "cold" else "warm_repeated_query"
        run <- tryCatch(
          run_search(x, rows, mode, backend, method, metric, k, threads, target),
          error = function(e) e
        )
        if (inherits(run, "error")) {
          quality <- c(mean = NA_real_, minimum = NA_real_)
          row_out <- result_row(
            dataset, backend, method, metric, k, mode, requested_m, actual_m,
            method_position, repeat_id, phase, NA_real_, quality, list(), reference,
            conditionMessage(run)
          )
        } else {
          quality <- quality_for_result(run$result, rows, mode, reference, k)
          row_out <- result_row(
            dataset, backend, method, metric, k, mode, requested_m, actual_m,
            method_position, repeat_id, phase, run$elapsed, quality, run$result,
            reference
          )
        }
        append_csv(row_out, output)
      }
    }
  }
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  message("DONE: ", output)
}

main()
