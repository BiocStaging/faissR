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

positive_int <- function(x, default, name) {
  value <- suppressWarnings(as.integer(x %||% default))
  if (length(value) != 1L || is.na(value) || value < 1L) {
    stop("`", name, "` must be a positive integer.", call. = FALSE)
  }
  value
}

logical_value <- function(x, default = FALSE) {
  key <- tolower(as.character(x %||% default)[[1L]])
  if (key %in% c("true", "t", "1", "yes", "on")) return(TRUE)
  if (key %in% c("false", "f", "0", "no", "off")) return(FALSE)
  stop("Invalid logical value: ", key, call. = FALSE)
}

script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    return(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
  }
  normalizePath("benchmark_reusable_external_indexes.R", mustWork = TRUE)
}

dataset_path_column <- function(manifest) {
  found <- intersect(
    c("path", "output", "file", "file_path", "rdata_path"),
    names(manifest)
  )
  if (!length(found)) stop("Manifest has no dataset path column.", call. = FALSE)
  found[[1L]]
}

load_dataset <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  candidates <- if (exists("dataset", env, inherits = FALSE)) {
    c("dataset", setdiff(ls(env), "dataset"))
  } else {
    ls(env)
  }
  for (name in candidates) {
    value <- get(name, env, inherits = FALSE)
    if (is.list(value) && !is.null(value$data)) return(value$data)
  }
  stop("No list containing `$data` was found in ", path, call. = FALSE)
}

as_double_matrix <- function(x) {
  if (inherits(x, "float32") || inherits(x, "float")) {
    if (!requireNamespace("float", quietly = TRUE)) {
      stop("The float package is required to read this dataset.", call. = FALSE)
    }
    x <- float::dbl(x)
  }
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  x
}

reference_path <- function(data_path, metric, k, quality_n, seed) {
  file.path(
    dirname(data_path),
    sprintf(
      "faissR_exact_reference_%s_k%d_q%d_seed%d.RData",
      metric, as.integer(k), as.integer(quality_n), as.integer(seed)
    )
  )
}

load_reference <- function(data_path, metric, reference_k, quality_n, seed,
                           dataset_md5) {
  path <- reference_path(
    data_path, metric, reference_k, quality_n, seed
  )
  if (!file.exists(path)) {
    stop("Missing exact reference: ", path, call. = FALSE)
  }
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  if (!exists("faissR_reference", env, inherits = FALSE)) {
    stop("Reference object is absent from ", path, call. = FALSE)
  }
  ref <- get("faissR_reference", env, inherits = FALSE)
  if (!identical(ref$status, "success") ||
      !identical(as.character(ref$dataset_md5), dataset_md5) ||
      !isTRUE(ref$cpu_audit_pass) ||
      ncol(ref$indices) < reference_k) {
    stop("Reference failed status, fingerprint, audit, or width checks: ", path,
         call. = FALSE)
  }
  ref$path <- path
  ref
}

peak_rss_gb <- function() {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  line <- grep("^VmHWM:", readLines(path, warn = FALSE), value = TRUE)
  if (!length(line)) return(NA_real_)
  as.numeric(gsub("[^0-9]", "", line[[1L]])) / 1024^2
}

standardize <- function(x) {
  indices <- x$index %||% x$indices %||% x$idx %||% x$nn.idx
  distances <- x$distance %||% x$distances %||% x$dist %||% x$nn.dists
  if (is.null(indices) || is.null(distances)) {
    stop("KNN result does not expose indices and distances.", call. = FALSE)
  }
  list(indices = as.matrix(indices), distances = as.matrix(distances))
}

remove_annoy_self <- function(index, rows, k) {
  out_i <- matrix(NA_integer_, nrow = length(rows), ncol = k)
  out_d <- matrix(NA_real_, nrow = length(rows), ncol = k)
  for (i in seq_along(rows)) {
    item <- index$getNNsByItemList(rows[[i]] - 1L, k + 1L, -1L, TRUE)
    ids <- as.integer(item$item) + 1L
    dst <- as.numeric(item$distance)
    keep <- which(ids != rows[[i]])
    take <- head(keep, k)
    if (length(take)) {
      out_i[i, seq_along(take)] <- ids[take]
      out_d[i, seq_along(take)] <- dst[take]
    }
  }
  list(indices = out_i, distances = out_d)
}

query_index <- function(index, route, rows, k, threads) {
  if (identical(route, "RcppAnnoy_euclidean")) {
    return(remove_annoy_self(index, rows, k))
  }
  standardize(BiocNeighbors::findKNN(
    index,
    k = k,
    subset = rows,
    num.threads = threads,
    get.index = TRUE,
    get.distance = TRUE
  ))
}

build_index <- function(x, route, metric, k, threads, index_seed) {
  if (identical(route, "RcppAnnoy_euclidean")) {
    if (!identical(metric, "euclidean")) {
      stop("RcppAnnoy_euclidean supports only Euclidean in this campaign.",
           call. = FALSE)
    }
    if (!requireNamespace("RcppAnnoy", quietly = TRUE)) {
      stop("RcppAnnoy is unavailable.", call. = FALSE)
    }
    index <- new(RcppAnnoy::AnnoyEuclidean, ncol(x))
    index$setSeed(as.integer(index_seed))
    index$setVerbose(0L)
    for (i in seq_len(nrow(x))) index$addItem(i - 1L, x[i, ])
    index$build(50L)
    return(index)
  }

  if (!requireNamespace("BiocNeighbors", quietly = TRUE)) {
    stop("BiocNeighbors is unavailable.", call. = FALSE)
  }
  distance <- if (identical(metric, "cosine")) "Cosine" else "Euclidean"
  param <- switch(
    route,
    BiocNeighbors_exhaustive =
      BiocNeighbors::ExhaustiveParam(distance = distance),
    BiocNeighbors_hnsw =
      BiocNeighbors::HnswParam(
        distance = distance,
        nlinks = 16L,
        ef.construction = 200L,
        ef.search = max(50L, 3L * k)
      ),
    BiocNeighbors_annoy =
      BiocNeighbors::AnnoyParam(
        distance = distance,
        ntrees = 50L,
        search.mult = 50
      ),
    stop("Unsupported reusable-index route: ", route, call. = FALSE)
  )
  BiocNeighbors::buildIndex(
    x,
    BNPARAM = param,
    num.threads = threads,
    .check.nonfinite = TRUE
  )
}

reusable_thread_metadata <- function(route, threads) {
  if (identical(route, "RcppAnnoy_euclidean")) {
    return(list(
      requested = 1L,
      scope = "serial public build and item-query API"
    ))
  }
  list(
    requested = as.integer(threads),
    scope = "BiocNeighbors buildIndex/findKNN num.threads argument"
  )
}

reusable_parameter_string <- function(route, metric, k, threads, index_seed) {
  distance <- if (identical(metric, "cosine")) "Cosine" else "Euclidean"
  switch(
    route,
    RcppAnnoy_euclidean = sprintf(
      "AnnoyEuclidean(build_trees=50,index_seed=%d,getNNsByItemList(k=%d))",
      index_seed, k + 1L
    ),
    BiocNeighbors_exhaustive = sprintf(
      "buildIndex(ExhaustiveParam(distance=%s),num.threads=%d);findKNN(k=%d)",
      distance, threads, k
    ),
    BiocNeighbors_hnsw = sprintf(
      "buildIndex(HnswParam(distance=%s,nlinks=16,ef.construction=200,ef.search=%d),num.threads=%d);findKNN(k=%d)",
      distance, max(50L, 3L * k), threads, k
    ),
    BiocNeighbors_annoy = sprintf(
      "buildIndex(AnnoyParam(distance=%s,ntrees=50,search.mult=50),num.threads=%d);findKNN(k=%d)",
      distance, threads, k
    ),
    "unrecorded"
  )
}

quality <- function(result, reference, k) {
  result <- standardize(result)
  ref_i <- reference$indices[, seq_len(k), drop = FALSE]
  recalls <- vapply(seq_len(nrow(ref_i)), function(i) {
    truth <- ref_i[i, is.finite(ref_i[i, ])]
    found <- result$indices[i, is.finite(result$indices[i, ])]
    if (!length(truth)) return(NA_real_)
    sum(found %in% truth) / length(truth)
  }, numeric(1L))
  data.frame(
    recall_at_k = mean(recalls, na.rm = TRUE),
    min_query_recall = min(recalls, na.rm = TRUE),
    finite_distance = all(is.finite(result$distances)),
    sorted_distance = all(apply(
      result$distances, 1L,
      function(z) all(diff(z[is.finite(z)]) >= -1e-7)
    )),
    stringsAsFactors = FALSE
  )
}

base_row <- function(config, package_version, n, p, seed, phase, repeat_id) {
  thread_meta <- reusable_thread_metadata(config$route, config$threads)
  data.frame(
    dataset = config$dataset,
    data_path = config$data_path,
    dataset_md5 = config$dataset_md5,
    n = n,
    p = p,
    package = sub("_.*$", "", config$route),
    package_version = package_version,
    route = config$route,
    metric = config$metric,
    k = config$k,
    seed = seed,
    algorithm_seed = if (identical(config$route, "RcppAnnoy_euclidean")) {
      config$index_seed
    } else {
      NA_integer_
    },
    threads_allocated = config$threads,
    threads_requested = thread_meta$requested,
    threading_scope = thread_meta$scope,
    method_parameters = reusable_parameter_string(
      config$route, config$metric, config$k, config$threads, config$index_seed
    ),
    query_n = NA_integer_,
    phase = phase,
    repeat_id = repeat_id,
    conversion_sec = config$conversion_sec,
    build_sec = NA_real_,
    query_sec = NA_real_,
    elapsed_sec = NA_real_,
    peak_rss_gb = NA_real_,
    reference_path = NA_character_,
    recall_at_k = NA_real_,
    min_query_recall = NA_real_,
    finite_distance = NA,
    sorted_distance = NA,
    status = "failed",
    error = "",
    stringsAsFactors = FALSE
  )
}

run_worker <- function(config) {
  Sys.setenv(
    OMP_NUM_THREADS = config$threads,
    OPENBLAS_NUM_THREADS = config$threads,
    MKL_NUM_THREADS = config$threads,
    VECLIB_MAXIMUM_THREADS = config$threads
  )
  loaded <- load_dataset(config$data_path)
  converted <- system.time(x <- as_double_matrix(loaded))[["elapsed"]]
  config$conversion_sec <- converted
  n <- nrow(x)
  p <- ncol(x)
  package <- sub("_.*$", "", config$route)
  package_version <- tryCatch(
    as.character(utils::packageVersion(package)),
    error = function(e) NA_character_
  )

  build_started <- proc.time()[["elapsed"]]
  index <- build_index(
    x, config$route, config$metric, config$k, config$threads,
    config$index_seed
  )
  build_sec <- proc.time()[["elapsed"]] - build_started

  rows <- list()
  for (seed in config$seeds) {
    reference <- load_reference(
      config$data_path, config$metric, config$reference_k,
      config$quality_n, seed, config$dataset_md5
    )
    query_rows <- as.integer(reference$rows)

    for (repeat_id in 0:config$repeats) {
      phase <- if (repeat_id == 0L) "cold_build_plus_query" else "warm_query"
      row <- base_row(
        config, package_version, n, p, seed, phase,
        if (repeat_id == 0L) 1L else repeat_id
      )
      row$query_n <- length(query_rows)
      row$build_sec <- build_sec
      row$reference_path <- reference$path
      measured <- tryCatch({
        started <- proc.time()[["elapsed"]]
        answer <- query_index(
          index, config$route, query_rows, config$k, config$threads
        )
        query_sec <- proc.time()[["elapsed"]] - started
        list(answer = answer, query_sec = query_sec)
      }, error = function(e) e)
      if (inherits(measured, "error")) {
        row$error <- conditionMessage(measured)
      } else {
        q <- quality(measured$answer, reference, config$k)
        row$query_sec <- measured$query_sec
        row$elapsed_sec <- if (repeat_id == 0L) {
          converted + build_sec + measured$query_sec
        } else {
          measured$query_sec
        }
        row$peak_rss_gb <- peak_rss_gb()
        row[names(q)] <- q
        row$status <- "success"
      }
      rows[[length(rows) + 1L]] <- row
    }
  }
  do.call(rbind, rows)
}

worker_main <- function(args) {
  config <- readRDS(args$config)
  result <- tryCatch(
    run_worker(config),
    error = function(e) data.frame(
      dataset = config$dataset,
      data_path = config$data_path,
      dataset_md5 = config$dataset_md5,
      n = NA_integer_, p = NA_integer_,
      package = sub("_.*$", "", config$route),
      package_version = NA_character_,
      route = config$route, metric = config$metric, k = config$k,
      seed = NA_integer_,
      algorithm_seed = if (identical(config$route, "RcppAnnoy_euclidean")) {
        config$index_seed
      } else {
        NA_integer_
      },
      threads_allocated = config$threads,
      threads_requested = reusable_thread_metadata(
        config$route, config$threads
      )$requested,
      threading_scope = reusable_thread_metadata(
        config$route, config$threads
      )$scope,
      method_parameters = reusable_parameter_string(
        config$route, config$metric, config$k, config$threads,
        config$index_seed
      ),
      query_n = NA_integer_, phase = "worker",
      repeat_id = NA_integer_, conversion_sec = NA_real_,
      build_sec = NA_real_, query_sec = NA_real_, elapsed_sec = NA_real_,
      peak_rss_gb = NA_real_, reference_path = NA_character_,
      recall_at_k = NA_real_, min_query_recall = NA_real_,
      finite_distance = NA, sorted_distance = NA,
      status = "failed", error = conditionMessage(e),
      stringsAsFactors = FALSE
    )
  )
  saveRDS(result, args$result)
}

run_child <- function(config, timeout, script) {
  cfg <- tempfile("faissR_reusable_cfg_", fileext = ".rds")
  result <- tempfile("faissR_reusable_result_", fileext = ".rds")
  saveRDS(config, cfg)
  on.exit(unlink(c(cfg, result)), add = TRUE)
  rscript <- file.path(R.home("bin"), "Rscript")
  command <- c(
    rscript, "--vanilla", script, "--child=TRUE",
    paste0("--config=", cfg), paste0("--result=", result)
  )
  timeout_bin <- Sys.which("timeout")
  if (nzchar(timeout_bin)) command <- c(timeout_bin, timeout, command)
  status <- system2(
    command[[1L]], vapply(command[-1L], shQuote, character(1L)),
    env = paste0(
      "R_LIBS=",
      shQuote(paste(.libPaths(), collapse = .Platform$path.sep))
    )
  )
  if (file.exists(result)) return(readRDS(result))
  data.frame(
    dataset = config$dataset, data_path = config$data_path,
    dataset_md5 = config$dataset_md5, n = NA_integer_, p = NA_integer_,
    package = sub("_.*$", "", config$route), package_version = NA_character_,
    route = config$route, metric = config$metric, k = config$k,
    seed = NA_integer_,
    algorithm_seed = if (identical(config$route, "RcppAnnoy_euclidean")) {
      config$index_seed
    } else {
      NA_integer_
    },
    threads_allocated = config$threads,
    threads_requested = reusable_thread_metadata(
      config$route, config$threads
    )$requested,
    threading_scope = reusable_thread_metadata(
      config$route, config$threads
    )$scope,
    method_parameters = reusable_parameter_string(
      config$route, config$metric, config$k, config$threads,
      config$index_seed
    ),
    query_n = NA_integer_, phase = "worker", repeat_id = NA_integer_,
    conversion_sec = NA_real_, build_sec = NA_real_, query_sec = NA_real_,
    elapsed_sec = if (identical(status, 124L)) timeout else NA_real_,
    peak_rss_gb = NA_real_, reference_path = NA_character_,
    recall_at_k = NA_real_, min_query_recall = NA_real_,
    finite_distance = NA, sorted_distance = NA,
    status = if (identical(status, 124L)) "timeout" else "failed",
    error = paste("child process exited with status", status),
    stringsAsFactors = FALSE
  )
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
  if (logical_value(args$child, FALSE)) return(worker_main(args))
  manifest_path <- normalizePath(
    args$manifest %||% stop("`--manifest` is required.", call. = FALSE),
    mustWork = TRUE
  )
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE)
  path_col <- dataset_path_column(manifest)
  datasets <- split_values(args$datasets, paste(manifest$dataset, collapse = ","))
  manifest <- manifest[manifest$dataset %in% datasets, , drop = FALSE]
  if (!nrow(manifest)) stop("No requested datasets are in the manifest.", call. = FALSE)
  route <- args$route %||% stop("`--route` is required.", call. = FALSE)
  metric <- tolower(args$metric %||% "euclidean")
  valid <- list(
    RcppAnnoy_euclidean = "euclidean",
    BiocNeighbors_exhaustive = c("euclidean", "cosine"),
    BiocNeighbors_hnsw = c("euclidean", "cosine"),
    BiocNeighbors_annoy = c("euclidean", "cosine")
  )
  if (!route %in% names(valid) || !metric %in% valid[[route]]) {
    stop("Unsupported route/metric combination: ", route, " / ", metric,
         call. = FALSE)
  }
  k_values <- as.integer(split_values(args$k_values, "15,30,50,100"))
  seeds <- as.integer(split_values(args$seeds, "20260706,20260807"))
  if (anyNA(k_values) || any(k_values < 1L) || anyNA(seeds)) {
    stop("Invalid k or seed values.", call. = FALSE)
  }
  threads <- positive_int(args$threads, 12L, "threads")
  repeats <- positive_int(args$repeats, 3L, "repeats")
  timeout <- positive_int(args$timeout, 2000L, "timeout")
  quality_n <- positive_int(args$quality_n, 1024L, "quality_n")
  reference_k <- positive_int(args$reference_k, 100L, "reference_k")
  index_seed <- positive_int(args$index_seed, 4L, "index_seed")
  out_dir <- args$out_dir %||% file.path(getwd(), "reusable_external_indexes")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  results_path <- file.path(out_dir, "jss_reusable_external_index_results.csv")
  script <- script_path()

  for (i in seq_len(nrow(manifest))) {
    data_path <- manifest[[path_col]][[i]]
    dataset_md5 <- unname(tools::md5sum(data_path)[[1L]])
    for (k in k_values) {
      message(manifest$dataset[[i]], " / ", route, " / ", metric, " / k=", k)
      result <- run_child(list(
        dataset = manifest$dataset[[i]],
        data_path = data_path,
        dataset_md5 = dataset_md5,
        route = route,
        metric = metric,
        k = k,
        seeds = seeds,
        threads = threads,
        repeats = repeats,
        timeout = timeout,
        quality_n = quality_n,
        reference_k = reference_k,
        index_seed = index_seed
      ), timeout, script)
      append_csv(result, results_path)
    }
  }
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  message("DONE: ", results_path)
}

if (!identical(
  Sys.getenv("FAISSR_JSS_REUSABLE_SOURCE_ONLY", unset = ""),
  "true"
)) {
  main()
}
