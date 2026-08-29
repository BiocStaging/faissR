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
    "standardize", "remove_query_self", "build_index", "query_index",
    "load_dataset", "as_double_matrix", "load_reference", "quality",
    "dataset_path_column"
  )
  for (name in needed) {
    assign(name, get(name, envir = helper_env, inherits = FALSE), envir = globalenv())
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

run_one_shot <- function(x, route, k, threads, target_recall, algorithm_seed) {
  if (identical(route, "faissR_hnsw")) {
    return(faissR::nn(
      x, k = k, exclude_self = TRUE, backend = "cpu", method = "hnsw",
      metric = "euclidean", tuning = "auto", target_recall = target_recall,
      n_threads = threads, output = "double"
    ))
  }
  if (identical(route, "RcppHNSW_hnsw")) {
    return(remove_query_self(
      RcppHNSW::hnsw_knn(
        x, k = k + 1L, distance = "euclidean", M = 16L,
        ef_construction = 200L, ef = max(50L, 3L * k), verbose = FALSE,
        progress = "none", n_threads = threads, grain_size = 1L,
        byrow = TRUE, random_seed = algorithm_seed
      ),
      seq_len(nrow(x)), k
    ))
  }
  if (identical(route, "BiocNeighbors_hnsw")) {
    return(remove_query_self(
      BiocNeighbors::findKNN(
        x, k = k + 1L,
        BNPARAM = BiocNeighbors::HnswParam(
          distance = "Euclidean", nlinks = 16L, ef.construction = 200L,
          ef.search = max(50L, 3L * k)
        ),
        num.threads = threads, get.index = TRUE, get.distance = TRUE
      ),
      seq_len(nrow(x)), k
    ))
  }
  stop("Unsupported route: ", route, call. = FALSE)
}

build_reusable <- function(x, route, k, threads, target_recall, algorithm_seed) {
  if (identical(route, "faissR_hnsw")) {
    labels <- factor(rep(c("a", "b"), length.out = nrow(x)))
    return(faissR::knn(
      x, labels, backend = "cpu", method = "hnsw", metric = "euclidean",
      tuning = "auto", target_recall = target_recall, k = k,
      n_threads = threads
    ))
  }
  build_index(
    x, route, "euclidean", k, threads, index_seed = algorithm_seed
  )
}

query_reusable <- function(index, x, route, rows, k, threads, target_recall) {
  if (identical(route, "faissR_hnsw")) {
    out <- faissR:::knn_predict_with_fitted_nn_index(
      object = index, query = x[rows, , drop = FALSE], k = k,
      backend = "cpu", tuning = "auto", target_recall = target_recall
    )
    if (is.null(out)) stop("faissR fitted HNSW index was not reused.", call. = FALSE)
    return(standardize(out))
  }
  query_index(index, route, x, rows, k, threads, "euclidean")
}

run_warmup <- function(x, route, threads, target_recall, algorithm_seed) {
  n <- min(128L, nrow(x))
  if (n < 4L) return(invisible(NULL))
  k <- min(5L, n - 1L)
  try(run_one_shot(
    x[seq_len(n), , drop = FALSE], route, k, threads,
    target_recall, algorithm_seed
  ), silent = TRUE)
  if (identical(route, "faissR_hnsw")) clear_faissr_cache()
  invisible(NULL)
}

base_result <- function(config, n, p) {
  fields <- list(
    dataset = config$dataset %||% NA_character_,
    data_path = config$data_path %||% NA_character_,
    dataset_md5 = config$dataset_md5 %||% NA_character_,
    n = n,
    p = p,
    metric = "euclidean",
    k = config$k %||% NA_integer_,
    target_recall = config$target_recall %||% NA_real_,
    validation_seed = config$validation_seed %||% NA_integer_,
    repeat_id = config$repeat_id %||% NA_integer_,
    pair_seed = config$pair_seed %||% NA_integer_,
    pair_id = config$pair_id %||% NA_character_,
    route = config$route %||% NA_character_,
    comparator = config$comparator %||% NA_character_,
    order_position = config$order_position %||% NA_integer_,
    order_scheme = "random_first_route_then_alternating_by_repeat",
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = "manual"),
    slurm_array_job_id = Sys.getenv("SLURM_ARRAY_JOB_ID", unset = "manual"),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "manual"),
    hostname = Sys.info()[["nodename"]],
    threads = config$threads %||% NA_integer_,
    input_representation = "R_double_matrix_for_both_routes",
    warmup_scope = "untimed_128_row_one_shot_then_faissR_cache_clear",
    cold_call_sec = NA_real_,
    cold_recall_at_k = NA_real_,
    cold_min_query_recall = NA_real_,
    fitted_build_sec = NA_real_,
    fitted_query_sec = NA_real_,
    fitted_recall_at_k = NA_real_,
    fitted_min_query_recall = NA_real_,
    query_n = NA_integer_,
    reference_path = NA_character_,
    status = "failed",
    error = "",
    faissR_version = as.character(utils::packageVersion("faissR")),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET")
  )
  lengths <- lengths(fields)
  if (any(lengths == 0L)) {
    stop(
      "Internal paired-benchmark row has empty fields: ",
      paste(names(fields)[lengths == 0L], collapse = ", "),
      call. = FALSE
    )
  }
  fields <- lapply(fields, function(x) x[[1L]])
  as.data.frame(fields, stringsAsFactors = FALSE, optional = TRUE)
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
    config$data_path, "euclidean", config$reference_k, config$quality_n,
    config$validation_seed, config$dataset_md5
  )
  rows <- as.integer(reference$rows)
  result$query_n <- length(rows)
  result$reference_path <- reference$path

  run_warmup(
    x, config$route, config$threads, config$target_recall,
    config$algorithm_seed
  )
  gc()
  if (identical(config$route, "faissR_hnsw")) clear_faissr_cache()
  started <- proc.time()[["elapsed"]]
  cold <- run_one_shot(
    x, config$route, config$k, config$threads, config$target_recall,
    config$algorithm_seed
  )
  result$cold_call_sec <- proc.time()[["elapsed"]] - started
  cold_quality <- quality(
    subset_knn(cold, rows, config$k), reference, config$k
  )
  result$cold_recall_at_k <- cold_quality$recall_at_k
  result$cold_min_query_recall <- cold_quality$min_query_recall

  if (identical(config$route, "faissR_hnsw")) clear_faissr_cache()
  gc()
  started <- proc.time()[["elapsed"]]
  index <- build_reusable(
    x, config$route, config$k, config$threads, config$target_recall,
    config$algorithm_seed
  )
  result$fitted_build_sec <- proc.time()[["elapsed"]] - started
  started <- proc.time()[["elapsed"]]
  fitted <- query_reusable(
    index, x, config$route, rows, config$k, config$threads,
    config$target_recall
  )
  result$fitted_query_sec <- proc.time()[["elapsed"]] - started
  fitted_quality <- quality(fitted, reference, config$k)
  result$fitted_recall_at_k <- fitted_quality$recall_at_k
  result$fitted_min_query_recall <- fitted_quality$min_query_recall
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
  cfg <- tempfile("faissR_paired_cfg_", fileext = ".rds")
  result <- tempfile("faissR_paired_result_", fileext = ".rds")
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

  helper <- normalizePath(
    args$helper %||% stop("`--helper` is required.", call. = FALSE),
    mustWork = TRUE
  )
  load_helpers(helper)

  manifest <- read.csv(
    normalizePath(args$manifest, mustWork = TRUE), stringsAsFactors = FALSE
  )
  path_col <- dataset_path_column(manifest)
  dataset <- args$dataset %||% stop("`--dataset` is required.", call. = FALSE)
  row <- manifest[manifest$dataset == dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset must match exactly one manifest row.", call. = FALSE)
  data_path <- row[[path_col]][[1L]]
  dataset_md5 <- unname(tools::md5sum(data_path)[[1L]])
  comparator <- args$comparator %||% "BiocNeighbors_hnsw"
  if (!comparator %in% c("BiocNeighbors_hnsw", "RcppHNSW_hnsw")) {
    stop("Unsupported comparator: ", comparator, call. = FALSE)
  }
  package <- sub("_.*$", "", comparator)
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Required comparator package is unavailable: ", package, call. = FALSE)
  }
  k <- positive_int(args$k, 30L, "k")
  repeats <- positive_int(args$repeats, 5L, "repeats")
  threads <- positive_int(args$threads, 12L, "threads")
  timeout <- positive_int(args$timeout, 4000L, "timeout")
  quality_n <- positive_int(args$quality_n, 1024L, "quality_n")
  reference_k <- positive_int(args$reference_k, 100L, "reference_k")
  seeds <- as.integer(strsplit(args$seeds %||% "20260706,20260807", ",", fixed = TRUE)[[1L]])
  target_recall <- as.numeric(args$target_recall %||% "0.99")
  out_dir <- args$out_dir %||% file.path(getwd(), "paired_cpu_comparison")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  results_path <- file.path(out_dir, "jss_paired_hnsw_raw.csv")
  script <- script_path()

  for (seed in seeds) {
    pair_seed <- as.integer((sum(utf8ToInt(dataset)) + k * 101L + seed) %% .Machine$integer.max)
    set.seed(pair_seed)
    first <- sample(c("faissR_hnsw", comparator), 1L)
    for (repeat_id in seq_len(repeats)) {
      order <- if ((repeat_id %% 2L) == 1L) {
        c(first, setdiff(c("faissR_hnsw", comparator), first))
      } else {
        rev(c(first, setdiff(c("faissR_hnsw", comparator), first)))
      }
      pair_id <- paste(dataset, comparator, k, seed, repeat_id, sep = "|")
      for (position in seq_along(order)) {
        route <- order[[position]]
        message(pair_id, " / position ", position, " / ", route)
        result <- run_child(list(
          dataset = dataset, data_path = data_path, dataset_md5 = dataset_md5,
          comparator = comparator, route = route, k = k,
          target_recall = target_recall, validation_seed = seed,
          repeat_id = repeat_id, pair_seed = pair_seed, pair_id = pair_id,
          order_position = position, algorithm_seed = seed + repeat_id,
          threads = threads, quality_n = quality_n,
          reference_k = reference_k
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
