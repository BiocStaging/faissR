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
      "true"
    }
  }
  out
}

script_path <- function() {
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  normalizePath(sub("^--file=", "", arg[[1L]]), mustWork = TRUE)
}

source_providers <- function(suite_root) {
  env <- new.env(parent = globalenv())
  Sys.setenv(
    FAISSR_JMLR_SOURCE_ONLY = "true",
    FAISSR_JSS_REUSABLE_SOURCE_ONLY = "true"
  )
  source(file.path(suite_root, "common", "benchmark_jmlr_tuned_methods.R"),
         local = env)
  source(file.path(suite_root, "common", "benchmark_reusable_external_indexes.R"),
         local = env)
  env
}

route_design <- function(metric) {
  faiss <- data.frame(
    route = c("faissR_auto", "faissR_exact", "faissR_nndescent"),
    package = "faissR", implementation = "faissR",
    public_method = c("auto", "exact", "nndescent"),
    comparison_class = c("overall", "exact", "nndescent"),
    stringsAsFactors = FALSE
  )
  if (metric %in% c("euclidean", "cosine")) {
    faiss <- rbind(faiss, data.frame(
      route = "faissR_hnsw", package = "faissR",
      implementation = "faissR", public_method = "hnsw",
      comparison_class = "hnsw", stringsAsFactors = FALSE
    ))
  }
  external <- switch(
    metric,
    euclidean = data.frame(
      route = c(
        "FNN_brute", "FNN_kd", "FNN_cover",
        "RANN_kd", "RANN_bd", "Rnanoflann_standard",
        "rnndescent_nnd",
        "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
        "BiocNeighbors_annoy", "RcppAnnoy_euclidean", "RcppHNSW_hnsw"
      ),
      package = c(
        rep("FNN", 3), rep("RANN", 2), "Rnanoflann", "rnndescent",
        rep("BiocNeighbors", 3), "RcppAnnoy", "RcppHNSW"
      ),
      comparison_class = c(
        rep("exact", 6), "nndescent", "exact", "hnsw",
        "annoy", "annoy", "hnsw"
      ), stringsAsFactors = FALSE
    ),
    cosine = data.frame(
      route = c(
        "rnndescent_nnd", "BiocNeighbors_exhaustive",
        "BiocNeighbors_hnsw", "BiocNeighbors_annoy",
        "RcppAnnoy_angular", "RcppHNSW_hnsw"
      ),
      package = c(
        "rnndescent", rep("BiocNeighbors", 3), "RcppAnnoy", "RcppHNSW"
      ),
      comparison_class = c(
        "nndescent", "exact", "hnsw", "annoy", "annoy", "hnsw"
      ), stringsAsFactors = FALSE
    ),
    correlation = data.frame(
      route = "rnndescent_nnd", package = "rnndescent",
      comparison_class = "nndescent", stringsAsFactors = FALSE
    )
  )
  external$implementation <- external$package
  external$public_method <- NA_character_
  rbind(faiss, external[, names(faiss), drop = FALSE])
}

reference_route <- function(comparison_class) {
  switch(
    comparison_class,
    exact = "faissR_exact",
    hnsw = "faissR_hnsw",
    nndescent = "faissR_nndescent",
    annoy = "faissR_auto",
    overall = "faissR_auto",
    "faissR_auto"
  )
}

clear_faissr_cache <- function() {
  cache <- get(".faissR_fitted_nn_index_cache", envir = asNamespace("faissR"))
  entries <- setdiff(ls(cache, all.names = TRUE), ".keys")
  if (length(entries)) rm(list = entries, envir = cache)
  cache$.keys <- character()
  invisible(NULL)
}

standardized_subset <- function(answer, rows, k, providers) {
  answer <- providers$standardize_knn(answer)
  list(
    indices = as.matrix(answer$indices)[rows, seq_len(k), drop = FALSE],
    distances = as.matrix(answer$distances)[rows, seq_len(k), drop = FALSE]
  )
}

base_row <- function(config, n = NA_integer_, p = NA_integer_) {
  data.frame(
    dataset = config$dataset, dataset_md5 = config$dataset_md5,
    n = n, p = p, metric = config$metric, k = config$k,
    target_recall = config$target_recall,
    validation_seed = config$validation_seed,
    repeat_id = config$repeat_id, order_position = config$order_position,
    order_seed = config$order_seed, route = config$route,
    package = config$package, comparison_class = config$comparison_class,
    reference_route = reference_route(config$comparison_class),
    status = "failed", elapsed_sec = NA_real_, peak_rss_gb = NA_real_,
    recall_at_k = NA_real_, min_query_recall = NA_real_,
    finite_distance = FALSE, sorted_distance = FALSE,
    query_n = NA_integer_, reference_path = NA_character_, error = "",
    input_representation = "R_double_matrix_for_every_route",
    execution_scope = "cold_full_self_search_public_interface",
    process_scope = "fresh_R_worker_per_route_and_repetition",
    order_scheme = "random_permutation_rotated_across_repetitions",
    threads_allocated = config$threads,
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = "manual"),
    slurm_array_job_id = Sys.getenv("SLURM_ARRAY_JOB_ID", unset = "manual"),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "manual"),
    hostname = Sys.info()[["nodename"]],
    faissR_version = as.character(packageVersion("faissR")),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
    package_version = tryCatch(
      as.character(packageVersion(config$package)), error = function(e) NA_character_
    ), stringsAsFactors = FALSE
  )
}

run_route <- function(x, config, providers) {
  if (startsWith(config$route, "faissR_")) {
    method <- data.frame(
      method_id = config$route, implementation = "faissR", backend = "cpu",
      public_method = sub("^faissR_", "", config$route), kind = "knn_search",
      stringsAsFactors = FALSE
    )
    providers$run_faissr_method(
      x, method, config$k, config$metric, config$threads,
      config$target_recall, "double"
    )
  } else {
    providers$run_external_method(
      x, config$route, config$k, config$metric, config$threads,
      config$algorithm_seed
    )
  }
}

run_worker <- function(config) {
  Sys.setenv(
    OMP_NUM_THREADS = config$threads,
    OPENBLAS_NUM_THREADS = config$threads,
    MKL_NUM_THREADS = config$threads,
    VECLIB_MAXIMUM_THREADS = config$threads
  )
  providers <- source_providers(config$suite_root)
  x <- providers$as_double_matrix(providers$load_dataset(config$data_path))
  out <- base_row(config, nrow(x), ncol(x))
  reference <- providers$load_reference(
    config$data_path, config$metric, config$reference_k,
    config$quality_n, config$validation_seed, config$dataset_md5
  )
  rows <- as.integer(reference$rows)
  out$query_n <- length(rows)
  out$reference_path <- reference$path
  set.seed(config$algorithm_seed)
  if (startsWith(config$route, "faissR_")) clear_faissr_cache()
  gc()
  started <- proc.time()[["elapsed"]]
  answer <- run_route(x, config, providers)
  out$elapsed_sec <- proc.time()[["elapsed"]] - started
  out$peak_rss_gb <- providers$peak_rss_gb()
  observed <- providers$quality(
    standardized_subset(answer, rows, config$k, providers),
    reference, config$k
  )
  out$recall_at_k <- observed$recall_at_k
  out$min_query_recall <- observed$min_query_recall
  out$finite_distance <- observed$finite_distance
  out$sorted_distance <- observed$sorted_distance
  out$status <- "success"
  out
}

worker_main <- function(args) {
  config <- readRDS(args$config)
  result <- tryCatch(run_worker(config), error = function(e) {
    out <- base_row(config)
    out$error <- conditionMessage(e)
    out
  })
  saveRDS(result, args$result)
}

run_child <- function(config, timeout, script, log_file) {
  cfg <- tempfile("faissR_comprehensive_", fileext = ".rds")
  result <- tempfile("faissR_comprehensive_result_", fileext = ".rds")
  saveRDS(config, cfg)
  on.exit(unlink(c(cfg, result)), add = TRUE)
  command <- c(
    file.path(R.home("bin"), "Rscript"), "--vanilla", script,
    "--child=true", paste0("--config=", cfg), paste0("--result=", result)
  )
  timeout_bin <- Sys.which("timeout")
  if (nzchar(timeout_bin)) command <- c(timeout_bin, timeout, command)
  status <- system2(
    command[[1L]], vapply(command[-1L], shQuote, character(1L)),
    stdout = log_file, stderr = log_file,
    env = paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = .Platform$path.sep)))
  )
  if (file.exists(result)) return(readRDS(result))
  out <- base_row(config)
  out$status <- if (identical(status, 124L)) "timeout" else "failed"
  out$elapsed_sec <- if (identical(status, 124L)) as.numeric(timeout) else NA_real_
  out$error <- paste("isolated worker exited with status", status)
  out
}

main <- function() {
  args <- parse_args()
  if (tolower(args$child %||% "false") == "true") return(worker_main(args))
  required <- c("dataset", "metric", "k", "validation_seed", "manifest",
                "suite_root", "out_dir")
  missing <- required[!vapply(required, function(x) nzchar(args[[x]] %||% ""), logical(1L))]
  if (length(missing)) stop("Missing argument(s): ", paste(missing, collapse = ", "))
  providers <- source_providers(args$suite_root)
  manifest <- read.csv(args$manifest, stringsAsFactors = FALSE)
  path_col <- providers$dataset_path_column(manifest)
  manifest_row <- manifest[manifest$dataset == args$dataset, , drop = FALSE]
  if (nrow(manifest_row) != 1L) stop("Dataset does not match one manifest row.")
  data_path <- manifest_row[[path_col]][[1L]]
  dataset_md5 <- unname(tools::md5sum(data_path)[[1L]])
  metric <- tolower(args$metric)
  k <- as.integer(args$k)
  validation_seed <- as.integer(args$validation_seed)
  repeats <- as.integer(args$repeats %||% "3")
  threads <- as.integer(args$threads %||% "12")
  timeout <- as.integer(args$timeout %||% "1200")
  target <- as.numeric(args$target_recall %||% "0.99")
  quality_n <- as.integer(args$quality_n %||% "1024")
  reference_k <- as.integer(args$reference_k %||% "100")
  design <- route_design(metric)
  dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(args$out_dir, "worker_logs"), showWarnings = FALSE)
  write.csv(design, file.path(args$out_dir, "route_design.csv"), row.names = FALSE)
  rows <- list()
  order_seed <- as.integer((sum(utf8ToInt(args$dataset)) + validation_seed +
    k * 1009L + sum(utf8ToInt(metric))) %% .Machine$integer.max)
  set.seed(order_seed)
  base_order <- sample(design$route)
  script <- script_path()
  for (repeat_id in seq_len(repeats)) {
    shift <- (repeat_id - 1L) %% length(base_order)
    order <- if (shift == 0L) base_order else c(
      base_order[(shift + 1L):length(base_order)], base_order[seq_len(shift)]
    )
    for (position in seq_along(order)) {
      route <- order[[position]]
      route_row <- design[design$route == route, , drop = FALSE]
      config <- list(
        dataset = args$dataset, data_path = data_path, dataset_md5 = dataset_md5,
        metric = metric, k = k, target_recall = target,
        validation_seed = validation_seed, repeat_id = repeat_id,
        order_position = position, order_seed = order_seed, route = route,
        package = route_row$package[[1L]],
        comparison_class = route_row$comparison_class[[1L]],
        threads = threads, algorithm_seed = validation_seed + repeat_id,
        suite_root = args$suite_root, quality_n = quality_n,
        reference_k = reference_k
      )
      log_file <- file.path(
        args$out_dir, "worker_logs",
        sprintf("%02d_%s_repeat%d.log", position, route, repeat_id)
      )
      message(args$dataset, "/", metric, "/k", k, "/seed", validation_seed,
              "/repeat", repeat_id, "/", route)
      rows[[length(rows) + 1L]] <- run_child(config, timeout, script, log_file)
    }
  }
  result <- do.call(rbind, rows)
  write.csv(result, file.path(args$out_dir, "jss_comprehensive_r_raw.csv"),
            row.names = FALSE)
  writeLines(capture.output(sessionInfo()), file.path(args$out_dir, "sessionInfo.txt"))
  cat("Rows:", nrow(result), "\n")
}

main()
