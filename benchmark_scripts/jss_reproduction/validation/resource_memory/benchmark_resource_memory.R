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

script_path <- function() {
  hit <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (!length(hit)) stop("Cannot determine benchmark script path.", call. = FALSE)
  normalizePath(sub("^--file=", "", hit[[1L]]), mustWork = TRUE)
}

proc_kib <- function(field) {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  line <- grep(paste0("^", field, ":"), readLines(path, warn = FALSE), value = TRUE)
  if (!length(line)) return(NA_real_)
  as.numeric(sub(".*?([0-9]+).*", "\\1", line[[1L]]))
}

dataset_path_column <- function(x) {
  hit <- intersect(c("path", "output", "file", "file_path", "rdata_path"), names(x))
  if (!length(hit)) stop("Dataset manifest has no path column.", call. = FALSE)
  hit[[1L]]
}

load_matrix <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  for (name in c("dataset", setdiff(ls(env), "dataset"))) {
    object <- get(name, env, inherits = FALSE)
    if (is.list(object) && !is.null(object$data)) return(object$data)
  }
  stop("No list containing `$data` was found in ", path, call. = FALSE)
}

load_reference <- function(data_path, metric, seed) {
  stem <- tools::file_path_sans_ext(basename(data_path))
  prefix <- if (startsWith(stem, "synthetic_")) paste0(stem, "__") else ""
  path <- file.path(dirname(data_path), sprintf(
    "%sfaissR_exact_reference_%s_k100_q1024_seed%d.RData",
    prefix, metric, seed
  ))
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
  out <- matrix(NA_integer_, nrow = length(rows), ncol = k)
  for (i in seq_along(rows)) {
    keep <- which(!is.na(result$indices[i, ]) & result$indices[i, ] != rows[[i]])
    take <- head(keep, k)
    if (length(take)) out[i, seq_along(take)] <- result$indices[i, take]
  }
  out
}

mean_recall <- function(observed, expected) {
  mean(vapply(seq_len(nrow(expected)), function(i) {
    truth <- expected[i, !is.na(expected[i, ])]
    found <- observed[i, !is.na(observed[i, ])]
    if (!length(truth)) return(NA_real_)
    length(intersect(truth, found)) / length(truth)
  }, numeric(1L)), na.rm = TRUE)
}

metadata_value <- function(result, name, default = NA) {
  value <- result[[name]] %||% attr(result, name, exact = TRUE)
  if (!is.null(value) && length(value)) return(value[[1L]])
  for (attribute in c("faiss", "cuda", "tuning", "auto_selection")) {
    object <- attr(result, attribute, exact = TRUE)
    value <- if (is.list(object)) object[[name]] else NULL
    if (!is.null(value) && length(value)) return(value[[1L]])
  }
  default
}

start_gpu_sampler <- function(path, pid, interval = 0.1) {
  if (!nzchar(Sys.which("nvidia-smi"))) return(NULL)
  done <- paste0(path, ".done")
  command <- sprintf(
    paste(
      "while [ ! -f %s ]; do",
      "nvidia-smi --query-compute-apps=pid,used_gpu_memory",
      "--format=csv,noheader,nounits 2>/dev/null |",
      "awk -F, '$1 + 0 == %d {gsub(/ /,\"\",$2); print $2}' >> %s;",
      "sleep %.2f; done"
    ),
    shQuote(done), as.integer(pid), shQuote(path), interval
  )
  system2("/bin/sh", c("-c", shQuote(command)), wait = FALSE)
  list(path = path, done = done)
}

stop_gpu_sampler <- function(sampler) {
  if (is.null(sampler)) return(NA_real_)
  file.create(sampler$done)
  Sys.sleep(0.25)
  values <- if (file.exists(sampler$path)) {
    suppressWarnings(as.numeric(readLines(sampler$path, warn = FALSE)))
  } else {
    numeric()
  }
  unlink(c(sampler$path, sampler$done))
  values <- values[is.finite(values)]
  if (length(values)) max(values) else NA_real_
}

worker <- function(config, result_path) {
  Sys.setenv(
    OMP_NUM_THREADS = config$threads,
    OPENBLAS_NUM_THREADS = config$threads,
    MKL_NUM_THREADS = config$threads,
    VECLIB_MAXIMUM_THREADS = config$threads
  )
  baseline_rss <- proc_kib("VmRSS")
  x <- load_matrix(config$data_path)
  input_rss <- proc_kib("VmRSS")
  reference <- load_reference(config$data_path, config$metric, config$seed)
  rows <- as.integer(reference$rows)
  call <- list(
    data = x, k = if (config$query_mode == "self") config$k else config$k + 1L,
    exclude_self = config$query_mode == "self", backend = config$backend,
    method = config$method, metric = config$metric, tuning = "auto",
    target_recall = config$target_recall, n_threads = config$threads
  )
  if (config$query_mode == "external") {
    call$points <- x[rows, , drop = FALSE]
  }
  sampler <- if (config$backend == "cuda") {
    start_gpu_sampler(tempfile("faissR_gpu_memory_"), Sys.getpid())
  } else {
    NULL
  }
  started <- proc.time()[["elapsed"]]
  answer <- do.call(faissR::nn, call)
  elapsed <- proc.time()[["elapsed"]] - started
  gpu_peak <- stop_gpu_sampler(sampler)
  post_search_rss <- proc_kib("VmRSS")
  peak_rss <- proc_kib("VmHWM")
  standardized <- standardize(answer)
  observed <- if (config$query_mode == "self") {
    standardized$indices[rows, seq_len(config$k), drop = FALSE]
  } else {
    remove_known_self(answer, rows, config$k)
  }
  expected <- reference$indices[, seq_len(config$k), drop = FALSE]
  row <- data.frame(
    dataset = config$dataset, backend = config$backend,
    method = config$method, metric = config$metric, k = config$k,
    target_recall = config$target_recall, query_mode = config$query_mode,
    query_rows = if (config$query_mode == "self") nrow(x) else length(rows),
    repeat_id = config$repeat_id, n = nrow(x), p = ncol(x),
    elapsed_sec = elapsed, mean_recall_at_k = mean_recall(observed, expected),
    baseline_rss_kib = baseline_rss, post_input_rss_kib = input_rss,
    post_search_rss_kib = post_search_rss, peak_rss_kib = peak_rss,
    retained_search_increment_kib = post_search_rss - input_rss,
    result_object_bytes = as.numeric(object.size(answer)),
    result_buffer_bytes = length(standardized$indices) * 4 +
      length(standardized$distances) * 8,
    gpu_process_peak_mib = gpu_peak,
    resolved_backend = as.character(metadata_value(answer, "backend_used", NA)),
    resolved_method = as.character(metadata_value(answer, "method", config$method)),
    result_residency = as.character(metadata_value(answer, "result_residency", "host")),
    status = "success", error = "", reference_path = reference$path,
    faissR_version = as.character(utils::packageVersion("faissR")),
    package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    stringsAsFactors = FALSE
  )
  saveRDS(row, result_path)
}

failed_row <- function(config, status, error) {
  data.frame(
    dataset = config$dataset, backend = config$backend,
    method = config$method, metric = config$metric, k = config$k,
    target_recall = config$target_recall, query_mode = config$query_mode,
    query_rows = NA_integer_, repeat_id = config$repeat_id,
    n = NA_integer_, p = NA_integer_, elapsed_sec = NA_real_,
    mean_recall_at_k = NA_real_, baseline_rss_kib = NA_real_,
    post_input_rss_kib = NA_real_, post_search_rss_kib = NA_real_,
    peak_rss_kib = NA_real_, retained_search_increment_kib = NA_real_,
    result_object_bytes = NA_real_, result_buffer_bytes = NA_real_,
    gpu_process_peak_mib = NA_real_, resolved_backend = NA_character_,
    resolved_method = NA_character_, result_residency = NA_character_,
    status = status, error = error, reference_path = NA_character_,
    faissR_version = as.character(utils::packageVersion("faissR")),
    package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    stringsAsFactors = FALSE
  )
}

append_csv <- function(x, path) {
  utils::write.table(
    x, path, sep = ",", row.names = FALSE, quote = TRUE, na = "",
    col.names = !file.exists(path), append = file.exists(path)
  )
}

main <- function() {
  args <- parse_args()
  if (identical(args$child %||% "FALSE", "TRUE")) {
    config <- readRDS(args$config)
    result <- tryCatch(
      worker(config, args$result),
      error = function(e) saveRDS(failed_row(config, "failed", conditionMessage(e)), args$result)
    )
    return(invisible(result))
  }
  manifest <- utils::read.csv(args$manifest, stringsAsFactors = FALSE)
  row <- manifest[manifest$dataset == args$dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset must match one manifest row.", call. = FALSE)
  path_col <- dataset_path_column(row)
  config <- list(
    dataset = args$dataset, data_path = row[[path_col]][[1L]],
    backend = args$backend, method = args$method,
    metric = args$metric %||% "euclidean", k = as.integer(args$k %||% 30L),
    target_recall = as.numeric(args$target_recall %||% 0.99),
    query_mode = args$query_mode, repeat_id = as.integer(args$repeat_id),
    seed = as.integer(args$seed %||% 20260807L),
    threads = as.integer(args$threads %||% if (args$backend == "cuda") 2L else 12L)
  )
  dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
  cfg <- tempfile(fileext = ".rds")
  result <- tempfile(fileext = ".rds")
  saveRDS(config, cfg)
  on.exit(unlink(c(cfg, result)), add = TRUE)
  command <- c(
    file.path(R.home("bin"), "Rscript"), "--vanilla", script_path(),
    "--child=TRUE", paste0("--config=", cfg), paste0("--result=", result)
  )
  timeout <- as.integer(args$timeout %||% 12000L)
  timeout_bin <- Sys.which("timeout")
  if (nzchar(timeout_bin)) command <- c(timeout_bin, timeout, command)
  status <- system2(command[[1L]], vapply(command[-1L], shQuote, character(1L)))
  output <- if (file.exists(result)) {
    readRDS(result)
  } else {
    failed_row(
      config, if (identical(status, 124L)) "timeout" else "failed",
      paste("isolated worker exited with status", status)
    )
  }
  append_csv(output, file.path(args$out_dir, "jss_resource_memory_raw.csv"))
}

main()
