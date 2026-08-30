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

script_path <- function() {
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  normalizePath(sub("^--file=", "", arg[[1L]]), mustWork = TRUE)
}

positive_int <- function(x, default, name) {
  value <- suppressWarnings(as.integer(x %||% default))
  if (length(value) != 1L || is.na(value) || value < 1L) {
    stop("`", name, "` must be a positive integer.", call. = FALSE)
  }
  value
}

load_helpers <- function(path) {
  helper_env <- new.env(parent = globalenv())
  Sys.setenv(FAISSR_JSS_REUSABLE_SOURCE_ONLY = "true")
  source(path, local = helper_env)
  needed <- c(
    "standardize", "remove_query_self", "load_dataset", "as_double_matrix",
    "load_reference", "quality", "dataset_path_column"
  )
  for (name in needed) {
    assign(name, get(name, envir = helper_env, inherits = FALSE),
           envir = globalenv())
  }
  invisible(NULL)
}

clear_faissr_cache <- function() {
  cache <- get(".faissR_fitted_nn_index_cache", envir = asNamespace("faissR"))
  entries <- setdiff(ls(cache, all.names = TRUE), ".keys")
  if (length(entries)) rm(list = entries, envir = cache)
  cache$.keys <- character()
  invisible(NULL)
}

subset_knn <- function(result, rows, k) {
  result <- standardize(result)
  list(
    indices = result$indices[rows, seq_len(k), drop = FALSE],
    distances = result$distances[rows, seq_len(k), drop = FALSE]
  )
}

route_package <- function(route) {
  switch(
    route,
    faissR_exact = "faissR",
    faissR_nndescent = "faissR",
    FNN_brute = "FNN",
    rnndescent_nnd = "rnndescent",
    stop("Unsupported route: ", route, call. = FALSE)
  )
}

run_route <- function(x, route, metric, k, threads, target_recall, seed) {
  set.seed(seed)
  if (route == "faissR_exact") {
    return(faissR::nn(
      x, k = k, exclude_self = TRUE, backend = "cpu", method = "exact",
      metric = metric, tuning = "auto", target_recall = target_recall,
      n_threads = threads, output = "double"
    ))
  }
  if (route == "faissR_nndescent") {
    return(faissR::nn(
      x, k = k, exclude_self = TRUE, backend = "cpu",
      method = "nndescent", metric = metric, tuning = "auto",
      target_recall = target_recall, n_threads = threads, output = "double"
    ))
  }
  if (route == "FNN_brute") {
    if (metric != "euclidean") stop("FNN brute is evaluated only for Euclidean distance.")
    return(remove_query_self(
      FNN::get.knn(x, k = k + 1L, algorithm = "brute"),
      seq_len(nrow(x)), k
    ))
  }
  if (route == "rnndescent_nnd") {
    return(remove_query_self(
      rnndescent::nnd_knn(
        x, k = k + 1L, metric = metric, n_threads = threads,
        verbose = FALSE
      ),
      seq_len(nrow(x)), k
    ))
  }
  stop("Unsupported route: ", route, call. = FALSE)
}

run_warmup <- function(x, route, metric, threads, target_recall, seed) {
  n <- min(128L, nrow(x))
  if (n < 4L) return(invisible(NULL))
  try(run_route(
    x[seq_len(n), , drop = FALSE], route, metric, min(5L, n - 1L),
    threads, target_recall, seed
  ), silent = TRUE)
  if (startsWith(route, "faissR_")) clear_faissr_cache()
  invisible(NULL)
}

base_result <- function(config, n, p) {
  values <- list(
    dataset = config$dataset, data_path = config$data_path,
    dataset_md5 = config$dataset_md5, n = n, p = p,
    comparison = config$comparison, route = config$route,
    comparator = config$comparator, metric = config$metric, k = config$k,
    target_recall = config$target_recall,
    validation_seed = config$validation_seed, repeat_id = config$repeat_id,
    pair_seed = config$pair_seed, pair_id = config$pair_id,
    order_position = config$order_position,
    order_scheme = "random_first_route_then_alternating_by_repeat",
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = "manual"),
    slurm_array_job_id = Sys.getenv("SLURM_ARRAY_JOB_ID", unset = "manual"),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "manual"),
    hostname = Sys.info()[["nodename"]], threads = config$threads,
    effective_thread_scope = if (config$route == "FNN_brute") {
      "FNN public interface exposes no thread argument"
    } else {
      "public package thread argument"
    },
    input_representation = "R_double_matrix_for_both_routes",
    warmup_scope = "untimed_128_row_call_then_faissR_cache_clear",
    elapsed_sec = NA_real_, recall_at_k = NA_real_,
    min_query_recall = NA_real_, query_n = NA_integer_,
    reference_path = NA_character_, status = "failed", error = "",
    faissR_version = as.character(utils::packageVersion("faissR")),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET")
  )
  as.data.frame(lapply(values, function(x) x[[1L]]),
                stringsAsFactors = FALSE, optional = TRUE)
}

run_worker <- function(config) {
  Sys.setenv(
    OMP_NUM_THREADS = config$threads,
    OPENBLAS_NUM_THREADS = config$threads,
    MKL_NUM_THREADS = config$threads,
    VECLIB_MAXIMUM_THREADS = config$threads
  )
  x <- as_double_matrix(load_dataset(config$data_path))
  result <- base_result(config, nrow(x), ncol(x))
  reference <- load_reference(
    config$data_path, config$metric, config$reference_k, config$quality_n,
    config$validation_seed, config$dataset_md5
  )
  rows <- as.integer(reference$rows)
  result$query_n <- length(rows)
  result$reference_path <- reference$path
  run_warmup(
    x, config$route, config$metric, config$threads,
    config$target_recall, config$algorithm_seed
  )
  if (startsWith(config$route, "faissR_")) clear_faissr_cache()
  gc()
  started <- proc.time()[["elapsed"]]
  answer <- run_route(
    x, config$route, config$metric, config$k, config$threads,
    config$target_recall, config$algorithm_seed
  )
  result$elapsed_sec <- proc.time()[["elapsed"]] - started
  observed <- quality(subset_knn(answer, rows, config$k), reference, config$k)
  result$recall_at_k <- observed$recall_at_k
  result$min_query_recall <- observed$min_query_recall
  result$status <- "success"
  result
}

worker_main <- function(args) {
  config <- readRDS(args$config)
  result <- tryCatch(
    run_worker(config),
    error = function(e) {
      out <- base_result(config, NA_integer_, NA_integer_)
      out$error <- conditionMessage(e)
      out
    }
  )
  saveRDS(result, args$result)
}

run_child <- function(config, timeout, script) {
  cfg <- tempfile("faissR_pair_cfg_", fileext = ".rds")
  result <- tempfile("faissR_pair_result_", fileext = ".rds")
  saveRDS(config, cfg)
  on.exit(unlink(c(cfg, result)), add = TRUE)
  command <- c(
    file.path(R.home("bin"), "Rscript"), "--vanilla", script,
    "--child=TRUE", paste0("--config=", cfg), paste0("--result=", result)
  )
  timeout_bin <- Sys.which("timeout")
  if (nzchar(timeout_bin)) command <- c(timeout_bin, timeout, command)
  status <- system2(
    command[[1L]], vapply(command[-1L], shQuote, character(1L)),
    env = paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = .Platform$path.sep)))
  )
  if (file.exists(result)) return(readRDS(result))
  out <- base_result(config, NA_integer_, NA_integer_)
  out$status <- if (identical(status, 124L)) "timeout" else "failed"
  out$error <- paste("isolated route worker exited with status", status)
  out
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
  if (tolower(args$child %||% "false") == "true") return(worker_main(args))
  load_helpers(normalizePath(args$helper, mustWork = TRUE))
  manifest <- read.csv(normalizePath(args$manifest, mustWork = TRUE),
                       stringsAsFactors = FALSE)
  path_col <- dataset_path_column(manifest)
  dataset <- args$dataset %||% stop("`--dataset` is required.", call. = FALSE)
  row <- manifest[manifest$dataset == dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset must match exactly one manifest row.")
  data_path <- row[[path_col]][[1L]]
  dataset_md5 <- unname(tools::md5sum(data_path)[[1L]])
  comparison <- args$comparison %||% stop("`--comparison` is required.")
  routes <- switch(
    comparison,
    exact_FNN = c("faissR_exact", "FNN_brute"),
    nndescent_rnndescent = c("faissR_nndescent", "rnndescent_nnd"),
    stop("Unsupported comparison: ", comparison)
  )
  for (package in unique(vapply(routes, route_package, character(1L)))) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("Required package is unavailable: ", package)
    }
  }
  metric <- tolower(args$metric %||% "euclidean")
  if (comparison == "exact_FNN" && metric != "euclidean") {
    stop("The exact/FNN comparison is prespecified for Euclidean distance.")
  }
  k <- positive_int(args$k, 30L, "k")
  repeats <- positive_int(args$repeats, 3L, "repeats")
  threads <- positive_int(args$threads, 12L, "threads")
  timeout <- positive_int(args$timeout, 4000L, "timeout")
  quality_n <- positive_int(args$quality_n, 1024L, "quality_n")
  reference_k <- positive_int(args$reference_k, 100L, "reference_k")
  seeds <- as.integer(strsplit(args$seeds %||% "20260706,20260807", ",",
                               fixed = TRUE)[[1L]])
  target_recall <- as.numeric(args$target_recall %||% "0.99")
  out_dir <- args$out_dir %||% file.path(getwd(), "paired_external_cpu")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  results_path <- file.path(out_dir, "jss_paired_external_cpu_raw.csv")
  script <- script_path()
  comparator <- routes[[2L]]
  for (seed in seeds) {
    pair_seed <- as.integer((sum(utf8ToInt(dataset)) + k * 101L + seed +
      sum(utf8ToInt(metric))) %% .Machine$integer.max)
    set.seed(pair_seed)
    first <- sample(routes, 1L)
    for (repeat_id in seq_len(repeats)) {
      order <- if (repeat_id %% 2L == 1L) {
        c(first, setdiff(routes, first))
      } else {
        rev(c(first, setdiff(routes, first)))
      }
      pair_id <- paste(dataset, comparison, metric, k, seed, repeat_id, sep = "|")
      for (position in seq_along(order)) {
        route <- order[[position]]
        message(pair_id, " / position ", position, " / ", route)
        result <- run_child(list(
          dataset = dataset, data_path = data_path, dataset_md5 = dataset_md5,
          comparison = comparison, comparator = comparator, route = route,
          metric = metric, k = k, target_recall = target_recall,
          validation_seed = seed, repeat_id = repeat_id,
          pair_seed = pair_seed, pair_id = pair_id, order_position = position,
          algorithm_seed = seed + repeat_id, threads = threads,
          quality_n = quality_n, reference_k = reference_k
        ), timeout, script)
        append_csv(result, results_path)
      }
    }
  }
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  message("DONE: ", results_path)
}

if (tolower(parse_args()$child %||% "false") == "true") {
  helper <- Sys.getenv("FAISSR_PAIRED_HELPER", unset = "")
  if (!nzchar(helper)) stop("FAISSR_PAIRED_HELPER is required in child workers.")
  load_helpers(helper)
}
main()
