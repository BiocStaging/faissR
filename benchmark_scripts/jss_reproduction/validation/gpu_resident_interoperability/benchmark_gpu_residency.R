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
    } else "TRUE"
  }
  out
}

load_matrix <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  for (name in c("dataset", ls(env))) {
    if (!exists(name, env, inherits = FALSE)) next
    value <- get(name, env, inherits = FALSE)
    if (is.list(value) && !is.null(value$data)) return(as.matrix(value$data))
  }
  stop("No list containing `$data` was found in ", path, call. = FALSE)
}

proc_kib <- function(field) {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  line <- grep(paste0("^", field, ":"), readLines(path, warn = FALSE), value = TRUE)
  if (!length(line)) return(NA_real_)
  suppressWarnings(as.numeric(gsub("[^0-9]", "", line[[1L]])))
}

gpu_memory_mib <- function() {
  if (!nzchar(Sys.which("nvidia-smi"))) return(NA_real_)
  output <- suppressWarnings(system2(
    "nvidia-smi",
    c("--query-compute-apps=pid,used_gpu_memory", "--format=csv,noheader,nounits"),
    stdout = TRUE, stderr = FALSE
  ))
  if (!length(output)) return(NA_real_)
  fields <- strsplit(output, ",", fixed = TRUE)
  rows <- lapply(fields, trimws)
  hit <- vapply(rows, function(z) length(z) >= 2L && z[[1L]] == Sys.getpid(), logical(1))
  values <- suppressWarnings(as.numeric(vapply(rows[hit], `[[`, character(1), 2L)))
  values <- values[is.finite(values)]
  if (length(values)) sum(values) else 0
}

start_gpu_sampler <- function(interval = 0.05) {
  sample <- tempfile("faissR_gpu_mem_", fileext = ".txt")
  stop <- tempfile("faissR_gpu_stop_")
  command <- sprintf(
    "while [ ! -f %s ]; do nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | awk -F, '$1 + 0 == %d {gsub(/ /,\"\",$2); print $2}' >> %s; sleep %.2f; done",
    shQuote(stop), Sys.getpid(), shQuote(sample), interval
  )
  system2("/bin/sh", c("-c", shQuote(command)), wait = FALSE,
          stdout = FALSE, stderr = FALSE)
  list(sample = sample, stop = stop)
}

stop_gpu_sampler <- function(x) {
  file.create(x$stop)
  Sys.sleep(0.1)
  values <- if (file.exists(x$sample)) {
    suppressWarnings(as.numeric(readLines(x$sample, warn = FALSE)))
  } else numeric()
  values <- values[is.finite(values)]
  unlink(c(x$sample, x$stop), force = TRUE)
  if (length(values)) max(values) else NA_real_
}

timed <- function(code) {
  started <- proc.time()[["elapsed"]]
  value <- force(code)
  list(value = value, elapsed = proc.time()[["elapsed"]] - started)
}

append_csv <- function(x, path) {
  write.table(
    x, path, sep = ",", row.names = FALSE,
    col.names = !file.exists(path), append = file.exists(path),
    quote = TRUE, na = ""
  )
}

main <- function() {
  args <- parse_args()
  manifest <- read.csv(args$manifest, stringsAsFactors = FALSE)
  row <- manifest[manifest$dataset == args$dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset must match one manifest row.")
  path_name <- intersect(c("path", "output", "file_path"), names(row))[[1L]]
  x <- load_matrix(row[[path_name]][[1L]])
  storage.mode(x) <- "double"
  requested_m <- as.integer(args$query_size)
  actual_m <- min(requested_m, nrow(x))
  k <- as.integer(args$k %||% 30L)
  repeats <- as.integer(args$repeats %||% 5L)
  seed <- as.integer(args$seed %||% 20260807L)
  set.seed(seed + sum(utf8ToInt(args$dataset)) + requested_m)
  rows <- sample.int(nrow(x), actual_m, replace = FALSE)
  q <- x[rows, , drop = FALSE]
  out_dir <- args$out_dir
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  output <- file.path(out_dir, "jss_gpu_resident_interoperability_raw.csv")

  stopifnot(faissR::cuda_available())
  stopifnot(requireNamespace("faissRGpuConsumer", quietly = TRUE))
  warm <- faissR::nn_gpu(x[seq_len(min(128L, nrow(x))), , drop = FALSE],
                         k = min(5L, nrow(x) - 1L), method = "exact")
  invisible(faissRGpuConsumer::gpu_result_device_checksum(warm))
  rm(warm); invisible(gc())

  api_test <- faissRGpuConsumer::gpu_knn_via_c_api(
    x[seq_len(min(128L, nrow(x))), , drop = FALSE],
    min(5L, nrow(x) - 1L), method = "exact", metric = "euclidean",
    include_self = TRUE, target_recall = 0.99
  )
  api_checksum <- faissRGpuConsumer::gpu_result_device_checksum(api_test)
  c_api_pass <- inherits(api_test, "faissR_gpu_knn") &&
    identical(api_test$result_residency, "cuda") &&
    identical(as.integer(api_test$device_to_host_result_copies), 0L) &&
    is.finite(api_checksum$distance_checksum)
  rm(api_test); invisible(gc())

  for (repeat_id in seq_len(repeats)) {
    invisible(gc())
    host_rss_before_kib <- proc_kib("VmRSS")
    device_before_mib <- gpu_memory_mib()
    sampler <- start_gpu_sampler()
    result <- tryCatch({
      search <- timed(faissR::nn_gpu(
        x, points = q, k = k, exclude_self = FALSE,
        method = "auto", metric = "euclidean",
        tuning = "auto", target_recall = 0.99
      ))
      device_after_search_mib <- gpu_memory_mib()
      order <- if ((repeat_id %% 2L) == 1L) c("consumer", "host") else c("host", "consumer")
      consumer <- host <- NULL
      for (operation in order) {
        if (operation == "consumer") {
          consumer <- timed(
            faissRGpuConsumer::gpu_result_device_checksum(search$value)
          )
        } else {
          host <- timed(faissR::gpu_knn_to_host(search$value))
        }
      }
      peak_device_mib <- stop_gpu_sampler(sampler)
      row_out <- data.frame(
        dataset = args$dataset, n = nrow(x), p = ncol(x),
        requested_query_n = requested_m, query_n = actual_m,
        k = k, repeat_id = repeat_id,
        operation_order = paste(order, collapse = "_then_"),
        search_sec = search$elapsed,
        resident_consumer_sec = consumer$elapsed,
        explicit_host_copy_sec = host$elapsed,
        resident_plus_consumer_sec = search$elapsed + consumer$elapsed,
        resident_plus_host_copy_sec = search$elapsed + host$elapsed,
        result_residency_before_copy = search$value$result_residency,
        device_to_host_copies_before_copy =
          search$value$device_to_host_result_copies,
        backend_used = search$value$backend_used,
        method_used = search$value$method,
        device = search$value$device,
        device_result_bytes = actual_m * k * 8,
        host_materialized_bytes = actual_m * k * 12,
        consumer_host_bytes = consumer$value$consumer_host_bytes,
        checksum_index = consumer$value$index_checksum,
        checksum_distance = consumer$value$distance_checksum,
        host_result_dimensions_pass =
          identical(dim(host$value$indices), c(actual_m, k)) &&
          identical(dim(host$value$distances), c(actual_m, k)),
        host_rss_before_kib = host_rss_before_kib,
        host_peak_rss_kib = proc_kib("VmHWM"),
        device_before_mib = device_before_mib,
        device_after_search_mib = device_after_search_mib,
        device_peak_mib = peak_device_mib,
        c_api_version = if (c_api_pass) 1L else NA_integer_,
        c_api_consumer_pass = c_api_pass,
        status = "success", error = "",
        faissR_version = as.character(packageVersion("faissR")),
        package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
        image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
        stringsAsFactors = FALSE
      )
      rm(host, consumer, search); invisible(gc())
      row_out$device_after_gc_mib <- gpu_memory_mib()
      row_out
    }, error = function(e) {
      peak <- stop_gpu_sampler(sampler)
      data.frame(
        dataset = args$dataset, n = nrow(x), p = ncol(x),
        requested_query_n = requested_m, query_n = actual_m, k = k,
        repeat_id = repeat_id, operation_order = NA_character_,
        search_sec = NA_real_, resident_consumer_sec = NA_real_,
        explicit_host_copy_sec = NA_real_, resident_plus_consumer_sec = NA_real_,
        resident_plus_host_copy_sec = NA_real_,
        result_residency_before_copy = NA_character_,
        device_to_host_copies_before_copy = NA_integer_,
        backend_used = NA_character_, method_used = NA_character_, device = NA_integer_,
        device_result_bytes = actual_m * k * 8,
        host_materialized_bytes = actual_m * k * 12,
        consumer_host_bytes = NA_real_, checksum_index = NA_real_,
        checksum_distance = NA_real_, host_result_dimensions_pass = FALSE,
        host_rss_before_kib = host_rss_before_kib,
        host_peak_rss_kib = proc_kib("VmHWM"),
        device_before_mib = device_before_mib,
        device_after_search_mib = NA_real_, device_peak_mib = peak,
        c_api_version = NA_integer_, c_api_consumer_pass = FALSE,
        status = "failed", error = conditionMessage(e),
        faissR_version = as.character(packageVersion("faissR")),
        package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
        image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
        device_after_gc_mib = gpu_memory_mib(), stringsAsFactors = FALSE
      )
    })
    append_csv(result, output)
  }
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  message("DONE: ", output)
}

main()
