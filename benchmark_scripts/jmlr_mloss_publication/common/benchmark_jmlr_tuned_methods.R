#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    kv <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    key <- kv[[1L]]
    value <- if (length(kv) > 1L) paste(kv[-1L], collapse = "=") else "TRUE"
    out[[key]] <- value
  }
  out
}

split_arg <- function(value, default = NULL) {
  raw <- value %||% default
  if (is.null(raw) || length(raw) != 1L || is.na(raw) || !nzchar(raw)) return(character())
  trimws(strsplit(raw, ",", fixed = TRUE)[[1L]])
}

logical_arg <- function(value, default = FALSE, arg = "value") {
  raw <- value
  if (is.null(raw) || length(raw) != 1L || is.na(raw)) return(isTRUE(default))
  raw <- tolower(trimws(as.character(raw)))
  if (raw %in% c("true", "t", "1", "yes", "y", "on")) return(TRUE)
  if (raw %in% c("false", "f", "0", "no", "n", "off")) return(FALSE)
  stop("`", arg, "` must be TRUE or FALSE.", call. = FALSE)
}

positive_ints <- function(value, default, arg = "value") {
  vals <- split_arg(value, default)
  parsed <- suppressWarnings(as.numeric(vals))
  bad <- vals[is.na(parsed) | !is.finite(parsed) | parsed < 1L |
    abs(parsed - round(parsed)) > sqrt(.Machine$double.eps)]
  if (length(bad) || !length(parsed)) {
    stop("`", arg, "` must contain positive integers. Invalid: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  unique(as.integer(round(parsed)))
}

numeric_values <- function(value, default, arg = "value") {
  vals <- split_arg(value, default)
  parsed <- suppressWarnings(as.numeric(vals))
  bad <- vals[is.na(parsed) | !is.finite(parsed)]
  if (length(bad) || !length(parsed)) {
    stop("`", arg, "` must contain numeric values. Invalid: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  unique(parsed)
}

scalar_positive_int <- function(value, default, arg = "value") {
  positive_ints(value, default, arg)[[1L]]
}

scalar_positive_number <- function(value, default, arg = "value") {
  parsed <- numeric_values(value, default, arg)[[1L]]
  if (parsed <= 0) stop("`", arg, "` must be positive.", call. = FALSE)
  parsed
}

normalize_metric_values <- function(value, default = "euclidean") {
  vals <- tolower(split_arg(value, default))
  valid <- c("euclidean", "cosine", "correlation", "inner_product")
  bad <- setdiff(vals, valid)
  if (length(bad)) stop("Unsupported metric(s): ", paste(bad, collapse = ", "), call. = FALSE)
  unique(vals)
}

normalize_backend <- function(value) {
  backend <- tolower(value %||% "cpu")
  if (!backend %in% c("cpu", "cuda")) {
    stop("`backend` must be `cpu` or `cuda` for this benchmark.", call. = FALSE)
  }
  backend
}

configure_threads <- function(n_threads) {
  value <- as.character(as.integer(n_threads))
  Sys.setenv(
    OMP_NUM_THREADS = value,
    OPENBLAS_NUM_THREADS = value,
    MKL_NUM_THREADS = value,
    VECLIB_MAXIMUM_THREADS = value,
    RCPP_PARALLEL_NUM_THREADS = value
  )
  options(Ncpus = as.integer(n_threads))
  invisible(n_threads)
}

available_pkg <- function(pkg) requireNamespace(pkg, quietly = TRUE)

package_version_string <- function(pkg) {
  if (!available_pkg(pkg)) return(NA_character_)
  tryCatch(
    as.character(utils::packageVersion(pkg)),
    error = function(e) NA_character_
  )
}

read_peak_rss_gb <- function() {
  path <- "/proc/self/status"
  if (!file.exists(path)) return(NA_real_)
  x <- readLines(path, warn = FALSE)
  v <- x[grepl("^VmHWM:", x)]
  if (!length(v)) return(NA_real_)
  kb <- suppressWarnings(as.numeric(gsub("[^0-9]", "", v[[1L]])))
  if (is.finite(kb)) kb / 1024^2 else NA_real_
}

start_gpu_memory_sampler <- function(enabled, interval = 0.1) {
  if (!isTRUE(enabled) || !nzchar(Sys.which("nvidia-smi"))) {
    return(list(enabled = FALSE, sample = NA_character_, stop = NA_character_))
  }
  sample_path <- tempfile("faissR_gpu_memory_", fileext = ".csv")
  stop_path <- tempfile("faissR_gpu_memory_stop_")
  pid <- Sys.getpid()
  command <- sprintf(
    "while [ ! -f %s ]; do nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null | awk -F, '$1 + 0 == %d {print}' >> %s; sleep %.2f; done",
    shQuote(stop_path), pid, shQuote(sample_path), interval
  )
  system2("/bin/sh", c("-c", shQuote(command)), wait = FALSE, stdout = FALSE, stderr = FALSE)
  Sys.sleep(min(interval, 0.1))
  list(enabled = TRUE, sample = sample_path, stop = stop_path)
}

stop_gpu_memory_sampler <- function(sampler) {
  if (!isTRUE(sampler$enabled)) {
    return(list(peak_mib = NA_real_, source = "not_applicable"))
  }
  file.create(sampler$stop)
  Sys.sleep(0.2)
  values <- numeric()
  if (file.exists(sampler$sample)) {
    lines <- readLines(sampler$sample, warn = FALSE)
    if (length(lines)) {
      values <- suppressWarnings(as.numeric(trimws(sub("^[^,]*,", "", lines))))
      values <- values[is.finite(values)]
    }
  }
  unlink(c(sampler$sample, sampler$stop), force = TRUE)
  list(
    peak_mib = if (length(values)) max(values) else NA_real_,
    source = if (length(values)) "nvidia-smi_process_sampled_100ms" else "nvidia-smi_no_process_sample"
  )
}

script_file <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) return(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
  normalizePath("benchmark_scripts/benchmark_jmlr_tuned_methods.R", mustWork = FALSE)
}

find_data_object <- function(env) {
  if (exists("dataset", envir = env, inherits = FALSE)) {
    x <- get("dataset", envir = env, inherits = FALSE)
    if (is.list(x) && !is.null(x$data)) {
      return(list(data = x$data, labels = x$labels %||% NULL, object_name = "dataset"))
    }
  }
  for (nm in ls(env)) {
    x <- get(nm, envir = env, inherits = FALSE)
    if (is.list(x) && !is.null(x$data)) {
      return(list(data = x$data, labels = x$labels %||% NULL, object_name = nm))
    }
  }
  stop("No list object with `$data` was found in dataset file.", call. = FALSE)
}

matrix_dims <- function(x) {
  d <- dim(x)
  if (is.null(d) && methods::is(x, "float32")) {
    d <- dim(methods::slot(x, "Data"))
  }
  if (is.null(d) || length(d) != 2L) stop("Data object is not two-dimensional.", call. = FALSE)
  as.integer(d)
}

is_float32_input <- function(x) {
  inherits(x, "float32") || inherits(x, "float")
}

as_double_matrix <- function(x) {
  if (is.data.frame(x)) x <- as.matrix(x)
  if (is_float32_input(x)) {
    if (!available_pkg("float")) stop("The float package is required to convert float32 input.", call. = FALSE)
    x <- float::dbl(x)
  }
  if (!is.matrix(x)) x <- as.matrix(x)
  storage.mode(x) <- "double"
  x
}

as_faissr_input <- function(x) {
  if (is_float32_input(x)) return(x)
  if (is.matrix(x) && identical(typeof(x), "double")) return(x)
  as_double_matrix(x)
}

load_dataset <- function(path) {
  if (available_pkg("float")) suppressPackageStartupMessages(requireNamespace("float", quietly = TRUE))
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  found <- find_data_object(env)
  d <- matrix_dims(found$data)
  list(
    data = found$data,
    labels = found$labels,
    object_name = found$object_name,
    n = d[[1L]],
    p = d[[2L]],
    input_type = if (is_float32_input(found$data)) "float32" else paste(class(found$data), collapse = "|")
  )
}

standardize_knn <- function(obj) {
  if (inherits(obj, "faissR_gpu_knn")) {
    obj <- faissR::gpu_knn_to_host(obj)
  }
  if (is.null(obj)) return(list(indices = NULL, distances = NULL))
  if (!is.null(obj$indices) && !is.null(obj$distances)) return(list(indices = obj$indices, distances = obj$distances))
  if (!is.null(obj$idx) && !is.null(obj$dist)) return(list(indices = obj$idx, distances = obj$dist))
  if (!is.null(obj$nn.idx) && !is.null(obj$nn.dists)) return(list(indices = obj$nn.idx, distances = obj$nn.dists))
  if (!is.null(obj$nn.index) && !is.null(obj$nn.dist)) return(list(indices = obj$nn.index, distances = obj$nn.dist))
  if (!is.null(obj$index) && !is.null(obj$distance)) return(list(indices = obj$index, distances = obj$distance))
  list(indices = NULL, distances = NULL)
}

remove_self <- function(obj, k) {
  sx <- standardize_knn(obj)
  idx <- as.matrix(sx$indices)
  dst <- as.matrix(sx$distances)
  if (is.null(idx) || is.null(dst) || !length(idx) || !length(dst)) return(sx)
  out_i <- matrix(NA_integer_, nrow(idx), k)
  out_d <- matrix(NA_real_, nrow(idx), k)
  for (i in seq_len(nrow(idx))) {
    keep <- which(!is.na(idx[i, ]) & idx[i, ] != i)
    take <- head(keep, k)
    if (length(take)) {
      out_i[i, seq_along(take)] <- as.integer(idx[i, take])
      out_d[i, seq_along(take)] <- as.numeric(dst[i, take])
    }
  }
  list(indices = out_i, distances = out_d)
}

shape_group <- function(n, p) {
  if (n < 5000) return("small_n")
  if (p <= 3) return("large_spatial_low_dim")
  if (n >= 50000 && p >= 100) return("large_high_dim")
  if (p < 100) return("large_low_dim")
  "medium_high_dim"
}

metric_supported_external <- function(method, metric) {
  if (identical(method, "RcppAnnoy_angular")) {
    return(identical(metric, "cosine"))
  }
  if (identical(method, "RcppAnnoy_dot_product")) {
    return(identical(metric, "inner_product"))
  }
  if (metric == "euclidean") return(TRUE)
  if (startsWith(method, "rnndescent_") &&
      metric %in% c("cosine", "correlation")) return(TRUE)
  if (method %in% c(
        "RcppAnnoy_angular",
        "RcppHNSW_hnsw",
        "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
        "BiocNeighbors_annoy"
      ) &&
      metric == "cosine") return(TRUE)
  if (identical(method, "RcppHNSW_hnsw") &&
      identical(metric, "inner_product")) return(TRUE)
  FALSE
}

canonicalize_biocneighbors_distances <- function(distances, metric) {
  distances <- as.matrix(distances)
  if (identical(metric, "cosine")) pmax(distances, 0)^2 / 2 else distances
}

canonicalize_annoy_angular_distances <- function(distances) {
  pmax(as.matrix(distances), 0)^2 / 2
}

canonicalize_annoy_dot_product_scores <- function(scores) {
  scores <- as.matrix(scores)
  result <- matrix(NA_real_, nrow(scores), ncol(scores))
  for (i in seq_len(nrow(scores))) {
    valid <- is.finite(scores[i, ])
    if (any(valid)) {
      result[i, valid] <- max(scores[i, valid]) - scores[i, valid]
    }
  }
  result
}

canonicalize_hnsw_inner_product_distances <- function(distances) {
  distances <- as.matrix(distances)
  result <- matrix(NA_real_, nrow(distances), ncol(distances))
  for (i in seq_len(nrow(distances))) {
    valid <- is.finite(distances[i, ])
    if (any(valid)) {
      result[i, valid] <- distances[i, valid] - min(distances[i, valid])
    }
  }
  result
}

stochastic_external_methods <- function() {
  c(
    "rnndescent_rpf", "rnndescent_rnnd", "rnndescent_nnd",
    "RcppAnnoy_euclidean", "RcppAnnoy_angular",
    "RcppAnnoy_dot_product", "RcppHNSW_hnsw",
    "BiocNeighbors_hnsw", "BiocNeighbors_annoy"
  )
}

algorithm_seed_for <- function(method_id, seed) {
  if (method_id %in% stochastic_external_methods()) {
    as.integer(seed)
  } else {
    NA_integer_
  }
}

external_methods <- function(backend) {
  if (backend == "cuda") {
    return(data.frame(
      method_id = "cuda_ml_knn",
      implementation = "cuda.ml",
      backend = "cuda",
      public_method = NA_character_,
      kind = "not_standalone",
      detail = paste(
        "The current cuda.ml public KNN API fits supervised models and does",
        "not return self-KNN indices and distances."
      ),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    method_id = c(
      "Rnanoflann_standard", "RANN_kd", "RANN_bd",
      "rnndescent_rpf", "rnndescent_rnnd", "rnndescent_nnd", "rnndescent_bruteforce",
      "RcppAnnoy_euclidean", "RcppAnnoy_angular",
      "RcppAnnoy_dot_product", "RcppHNSW_hnsw",
      "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw", "BiocNeighbors_annoy",
      "FNN_kd", "FNN_cover", "FNN_brute",
      "nabor_auto", "nabor_brute",
      "uwot_nearest_neighbors", "Rtsne_neighbors", "umap_umap"
    ),
    implementation = c(
      "Rnanoflann", "RANN", "RANN",
      "rnndescent", "rnndescent", "rnndescent", "rnndescent",
      "RcppAnnoy", "RcppAnnoy", "RcppAnnoy", "RcppHNSW",
      "BiocNeighbors", "BiocNeighbors", "BiocNeighbors",
      "FNN", "FNN", "FNN",
      "nabor", "nabor",
      "uwot", "Rtsne", "umap"
    ),
    backend = "cpu",
    public_method = NA_character_,
    kind = c(
      rep("knn_search", 19),
      "not_standalone", "not_standalone", "embedding_consumer"
    ),
    detail = c(
      "Rnanoflann standard KNN", "RANN kd tree", "RANN bd tree",
      "rnndescent random projection forest", "rnndescent random-pair NN-descent",
      "rnndescent NN-descent", "rnndescent brute force",
      "RcppAnnoy Euclidean Annoy", "RcppAnnoy angular cosine Annoy",
      "RcppAnnoy dot-product Annoy",
      "RcppHNSW hnswlib HNSW",
      "BiocNeighbors exhaustive", "BiocNeighbors HNSW", "BiocNeighbors Annoy",
      "FNN kd tree", "FNN cover tree", "FNN brute force",
      "nabor automatic search", "nabor brute-force search",
      "uwot does not export a standalone nearest-neighbor result API",
      "Rtsne consumes precomputed neighbours",
      "umap package embedding, not standalone KNN"
    ),
    stringsAsFactors = FALSE
  )
}

faissr_methods <- function(backend, include_gpu_resident = TRUE) {
  common <- c("auto", "exact", "flat", "bruteforce", "grid", "hnsw", "ivf",
              "ivfpq", "ivfpq_fastscan", "nndescent", "nsg", "vamana")
  methods <- if (backend == "cuda") c(common, "cagra") else common
  rows <- data.frame(
    method_id = paste0("faissR_", backend, "_", methods),
    implementation = "faissR",
    backend = backend,
    public_method = methods,
    kind = "knn_search",
    detail = paste("faissR public nn() method", methods),
    stringsAsFactors = FALSE
  )
  if (backend == "cuda" && isTRUE(include_gpu_resident)) {
    gpu <- data.frame(
      method_id = paste0("faissR_cuda_gpu_resident_", c("auto", "exact", "flat", "bruteforce")),
      implementation = "faissR",
      backend = "cuda",
      public_method = c("auto", "exact", "flat", "bruteforce"),
      kind = "gpu_resident_knn",
      detail = "faissR nn_gpu() GPU-resident exact-family route",
      stringsAsFactors = FALSE
    )
    rows <- rbind(rows, gpu)
  }
  rows
}

method_table <- function(backend, include_external = TRUE, include_gpu_resident = TRUE) {
  rows <- faissr_methods(backend, include_gpu_resident = include_gpu_resident)
  if (isTRUE(include_external)) rows <- rbind(rows, external_methods(backend))
  rows
}

run_faissr_method <- function(x, row, k, metric, threads, target_recall, output) {
  x <- as_faissr_input(x)
  if (row$kind == "gpu_resident_knn") {
    return(faissR::nn_gpu(
      x,
      k = k,
      exclude_self = TRUE,
      method = row$public_method,
      metric = metric,
      tuning = "auto",
      target_recall = target_recall
    ))
  }
  faissR::nn(
    x,
    k = k,
    exclude_self = TRUE,
    backend = row$backend,
    method = row$public_method,
    metric = metric,
    tuning = "auto",
    target_recall = target_recall,
    n_threads = threads,
    output = output
  )
}

annoy_knn <- function(x, k, metric = "euclidean", n_trees = 50L,
                      n_threads = 1L, seed = 4L) {
  if (!available_pkg("RcppAnnoy")) stop("RcppAnnoy unavailable")
  p <- ncol(x)
  index <- if (identical(metric, "cosine")) {
    new(RcppAnnoy::AnnoyAngular, p)
  } else if (identical(metric, "inner_product")) {
    new(RcppAnnoy::AnnoyDotProduct, p)
  } else {
    new(RcppAnnoy::AnnoyEuclidean, p)
  }
  index$setSeed(as.integer(seed))
  for (i in seq_len(nrow(x))) index$addItem(i - 1L, x[i, ])
  index$build(as.integer(n_trees))
  query_one <- function(i) {
    ans <- index$getNNsByItemList(
      i - 1L,
      k + 1L,
      -1L,
      TRUE
    )
    list(indices = as.integer(ans$item + 1L), distances = as.numeric(ans$distance))
  }
  rows <- seq_len(nrow(x))
  if (n_threads > 1L && .Platform$OS.type != "windows") {
    chunks <- split(rows, cut(rows, breaks = min(n_threads, length(rows)), labels = FALSE))
    pieces <- parallel::mclapply(chunks, function(ii) lapply(ii, query_one), mc.cores = min(n_threads, length(chunks)))
    res <- unlist(pieces, recursive = FALSE, use.names = FALSE)
  } else {
    res <- lapply(rows, query_one)
  }
  result <- list(
    indices = do.call(rbind, lapply(res, `[[`, "indices")),
    distances = do.call(rbind, lapply(res, `[[`, "distances"))
  )
  if (identical(metric, "cosine")) {
    result$distances <- canonicalize_annoy_angular_distances(result$distances)
  }
  result
}

run_external_method <- function(x_input, method, k, metric, threads, seed) {
  if (!metric_supported_external(method, metric)) {
    stop("External method does not expose a validated `", metric, "` route in this benchmark.", call. = FALSE)
  }
  algorithm_seed <- algorithm_seed_for(method, seed)
  if (!is.na(algorithm_seed)) set.seed(algorithm_seed)
  x <- as_double_matrix(x_input)
  out <- switch(
    method,
    Rnanoflann_standard = {
      if (!available_pkg("Rnanoflann")) stop("Rnanoflann unavailable")
      out <- Rnanoflann::nn(x, x, k + 1L, parallel = TRUE, cores = threads, sorted = TRUE)
      remove_self(out, k)
    },
    RANN_kd = {
      if (!available_pkg("RANN")) stop("RANN unavailable")
      remove_self(RANN::nn2(x, x, k = k + 1L, treetype = "kd"), k)
    },
    RANN_bd = {
      if (!available_pkg("RANN")) stop("RANN unavailable")
      remove_self(RANN::nn2(x, x, k = k + 1L, treetype = "bd"), k)
    },
    rnndescent_rpf = {
      if (!available_pkg("rnndescent")) stop("rnndescent unavailable")
      remove_self(rnndescent::rpf_knn(
        x, k = k + 1L, metric = metric, n_threads = threads,
        include_self = TRUE, verbose = FALSE
      ), k)
    },
    rnndescent_rnnd = {
      if (!available_pkg("rnndescent")) stop("rnndescent unavailable")
      remove_self(rnndescent::rnnd_knn(
        x, k = k + 1L, metric = metric,
        n_threads = threads, verbose = FALSE
      ), k)
    },
    rnndescent_nnd = {
      if (!available_pkg("rnndescent")) stop("rnndescent unavailable")
      remove_self(rnndescent::nnd_knn(
        x, k = k + 1L, metric = metric,
        n_threads = threads, verbose = FALSE
      ), k)
    },
    rnndescent_bruteforce = {
      if (!available_pkg("rnndescent")) stop("rnndescent unavailable")
      remove_self(rnndescent::brute_force_knn(
        x, k = k + 1L, metric = metric, n_threads = threads
      ), k)
    },
    RcppAnnoy_euclidean = remove_self(
      annoy_knn(x, k, metric = "euclidean", n_threads = threads, seed = seed),
      k
    ),
    RcppAnnoy_angular = remove_self(
      annoy_knn(x, k, metric = "cosine", n_threads = threads, seed = seed),
      k
    ),
    RcppAnnoy_dot_product = {
      result <- remove_self(
        annoy_knn(
          x, k, metric = "inner_product", n_threads = threads, seed = seed
        ),
        k
      )
      result$distances <- canonicalize_annoy_dot_product_scores(
        result$distances
      )
      result
    },
    RcppHNSW_hnsw = {
      if (!available_pkg("RcppHNSW")) stop("RcppHNSW unavailable")
      result <- remove_self(
        RcppHNSW::hnsw_knn(
          x,
          k = k + 1L,
          distance = if (identical(metric, "inner_product")) "ip" else metric,
          M = 16L,
          ef_construction = 200L,
          ef = max(50L, 3L * k),
          verbose = FALSE,
          progress = "none",
          n_threads = threads,
          grain_size = 1L,
          byrow = TRUE,
          random_seed = as.integer(seed)
        ),
        k
      )
      if (identical(metric, "inner_product")) {
        result$distances <- canonicalize_hnsw_inner_product_distances(
          result$distances
        )
      }
      result
    },
    BiocNeighbors_exhaustive = {
      if (!available_pkg("BiocNeighbors")) stop("BiocNeighbors unavailable")
      dist <- if (metric == "cosine") "Cosine" else "Euclidean"
      remove_self(BiocNeighbors::findKNN(x, k = k + 1L, BNPARAM = BiocNeighbors::ExhaustiveParam(distance = dist), num.threads = threads), k)
    },
    BiocNeighbors_hnsw = {
      if (!available_pkg("BiocNeighbors")) stop("BiocNeighbors unavailable")
      dist <- if (metric == "cosine") "Cosine" else "Euclidean"
      remove_self(BiocNeighbors::findKNN(x, k = k + 1L, BNPARAM = BiocNeighbors::HnswParam(distance = dist, nlinks = 16, ef.construction = 200, ef.search = max(50, 3 * k)), num.threads = threads), k)
    },
    BiocNeighbors_annoy = {
      if (!available_pkg("BiocNeighbors")) stop("BiocNeighbors unavailable")
      dist <- if (metric == "cosine") "Cosine" else "Euclidean"
      remove_self(BiocNeighbors::findKNN(x, k = k + 1L, BNPARAM = BiocNeighbors::AnnoyParam(distance = dist, ntrees = 50), num.threads = threads), k)
    },
    FNN_kd = {
      if (!available_pkg("FNN")) stop("FNN unavailable")
      remove_self(FNN::get.knn(x, k = k + 1L, algorithm = "kd_tree"), k)
    },
    FNN_cover = {
      if (!available_pkg("FNN")) stop("FNN unavailable")
      remove_self(FNN::get.knn(x, k = k + 1L, algorithm = "cover_tree"), k)
    },
    FNN_brute = {
      if (!available_pkg("FNN")) stop("FNN unavailable")
      remove_self(FNN::get.knn(x, k = k + 1L, algorithm = "brute"), k)
    },
    nabor_auto = {
      if (!available_pkg("nabor")) stop("nabor unavailable")
      remove_self(nabor::knn(x, x, k = k + 1L, searchtype = "auto"), k)
    },
    nabor_brute = {
      if (!available_pkg("nabor")) stop("nabor unavailable")
      remove_self(nabor::knn(x, x, k = k + 1L, searchtype = "brute"), k)
    },
    uwot_nearest_neighbors = {
      if (!available_pkg("uwot")) stop("uwot unavailable")
      if (!"nearest_neighbors" %in% getNamespaceExports("uwot")) {
        stop("uwot::nearest_neighbors is not exported in this uwot build.", call. = FALSE)
      }
      fn <- get("nearest_neighbors", envir = asNamespace("uwot"))
      remove_self(fn(x, n_neighbors = k + 1L, metric = metric, n_threads = threads, verbose = FALSE), k)
    },
    cuda_ml_knn = stop(
      "cuda.ml exposes supervised KNN model fitting, not a standalone self-KNN result.",
      call. = FALSE
    ),
    Rtsne_neighbors = stop("Rtsne::Rtsne_neighbors consumes precomputed neighbours and is not a standalone NN search.", call. = FALSE),
    umap_umap = stop("umap::umap is an embedding consumer, not a standalone NN search returning indices/distances.", call. = FALSE),
    stop("Unknown external method: ", method, call. = FALSE)
  )
  if (startsWith(method, "BiocNeighbors_") && identical(metric, "cosine")) {
    out$distances <- canonicalize_biocneighbors_distances(
      out$distances, metric
    )
  }
  out
}

compute_reference <- function(x, rows, k, metric, threads) {
  x <- as_faissr_input(x)
  q <- tryCatch(x[rows, , drop = FALSE], error = function(e) NULL)
  if (is.null(q)) {
    q <- as_double_matrix(x)[rows, , drop = FALSE]
  }
  ref <- faissR::nn(
    x,
    points = q,
    k = min(k + 1L, matrix_dims(x)[[1L]]),
    exclude_self = FALSE,
    backend = "cpu",
    method = "exact",
    metric = metric,
    tuning = "auto",
    n_threads = threads,
    output = "double"
  )
  sx <- standardize_knn(ref)
  idx <- as.matrix(sx$indices)
  dst <- as.matrix(sx$distances)
  out_i <- matrix(NA_integer_, length(rows), k)
  out_d <- matrix(NA_real_, length(rows), k)
  for (ii in seq_along(rows)) {
    keep <- which(!is.na(idx[ii, ]) & idx[ii, ] != rows[[ii]])
    take <- head(keep, k)
    if (length(take)) {
      out_i[ii, seq_along(take)] <- as.integer(idx[ii, take])
      out_d[ii, seq_along(take)] <- as.numeric(dst[ii, take])
    }
  }
  list(indices = out_i, distances = out_d)
}

choose_quality_rows <- function(n, p, max_n, max_ops, seed) {
  if (n < 2L) return(integer())
  by_ops <- floor(max_ops / max(1, as.double(n) * as.double(p)))
  size <- min(max_n, n, max(8L, as.integer(by_ops)))
  if (!is.finite(size) || size < 1L) return(integer())
  set.seed(as.integer(seed) + n + p)
  sort(sample.int(n, size))
}

load_precomputed_reference <- function(data_path, reference_k, quality_n, seed, metric, k,
                                       dataset_md5) {
  path <- file.path(
    dirname(data_path),
    sprintf(
      "faissR_exact_reference_%s_k%d_q%d_seed%d.RData",
      metric, as.integer(reference_k), as.integer(quality_n), as.integer(seed)
    )
  )
  if (!file.exists(path)) return(NULL)
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  if (!exists("faissR_reference", envir = env, inherits = FALSE)) return(NULL)
  ref <- get("faissR_reference", envir = env, inherits = FALSE)
  if (!identical(ref$status %||% "success", "success") ||
      !identical(as.character(ref$dataset_md5 %||% NA_character_), as.character(dataset_md5)) ||
      is.null(ref$rows) || is.null(ref$indices) || ncol(ref$indices) < k) {
    return(NULL)
  }
  ref$indices <- ref$indices[, seq_len(k), drop = FALSE]
  if (!is.null(ref$distances) && ncol(ref$distances) >= k) {
    ref$distances <- ref$distances[, seq_len(k), drop = FALSE]
  } else {
    ref$distances <- matrix(NA_real_, nrow(ref$indices), k)
  }
  ref$path <- path
  ref
}

finite_mean <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) NA_real_ else mean(x)
}

quality_metrics <- function(obj, ref, rows, k) {
  empty <- data.frame(
    recall_at_k = NA_real_,
    median_recall_at_k = NA_real_,
    min_recall_at_k = NA_real_,
    rank_correlation = NA_real_,
    mean_relative_distance_error = NA_real_,
    quality_status = "not_evaluated",
    quality_error = "",
    stringsAsFactors = FALSE
  )
  sx <- standardize_knn(obj)
  if (is.null(sx$indices) || is.null(sx$distances)) {
    empty$quality_status <- "failed"
    empty$quality_error <- "method did not return indices and distances"
    return(empty)
  }
  idx <- as.matrix(sx$indices)
  dst <- as.matrix(sx$distances)
  if (nrow(idx) < max(rows)) {
    empty$quality_status <- "failed"
    empty$quality_error <- "method returned fewer rows than the original dataset"
    return(empty)
  }
  kk <- min(k, ncol(idx), ncol(ref$indices))
  recalls <- numeric(length(rows))
  ranks <- rep(NA_real_, length(rows))
  matched_reference_distances <- numeric()
  matched_distance_errors <- numeric()
  for (ii in seq_along(rows)) {
    a_all <- idx[rows[[ii]], seq_len(kk)]
    b_all <- ref$indices[ii, seq_len(kk)]
    candidate_distances <- dst[rows[[ii]], seq_len(kk)]
    reference_distances <- ref$distances[ii, seq_len(kk)]
    common <- intersect(
      a_all[!is.na(a_all) & is.finite(a_all)],
      b_all[!is.na(b_all) & is.finite(b_all)]
    )
    if (length(common)) {
      candidate_positions <- match(common, a_all)
      reference_positions <- match(common, b_all)
      candidate_values <- candidate_distances[candidate_positions]
      reference_values <- reference_distances[reference_positions]
      valid_distances <- is.finite(candidate_values) &
        is.finite(reference_values)
      if (any(valid_distances)) {
        matched_reference_distances <- c(
          matched_reference_distances,
          abs(reference_values[valid_distances])
        )
        matched_distance_errors <- c(
          matched_distance_errors,
          abs(candidate_values[valid_distances] -
                reference_values[valid_distances])
        )
      }
    }
    a <- a_all
    b <- b_all
    a <- a[!is.na(a) & is.finite(a)]
    b <- b[!is.na(b) & is.finite(b)]
    recalls[[ii]] <- if (length(b)) sum(a %in% b) / length(b) else NA_real_
    universe <- unique(c(a, b))
    if (length(universe) > 1L) {
      ra <- match(universe, a)
      rb <- match(universe, b)
      ra[is.na(ra)] <- kk + 1L
      rb[is.na(rb)] <- kk + 1L
      if (length(unique(ra)) > 1L && length(unique(rb)) > 1L) {
        ranks[[ii]] <- suppressWarnings(stats::cor(ra, rb, method = "spearman"))
      }
    }
  }
  abs_ref <- finite_mean(matched_reference_distances)
  abs_err <- finite_mean(matched_distance_errors)
  data.frame(
    recall_at_k = finite_mean(recalls),
    median_recall_at_k = if (any(is.finite(recalls))) median(recalls[is.finite(recalls)]) else NA_real_,
    min_recall_at_k = if (any(is.finite(recalls))) min(recalls[is.finite(recalls)]) else NA_real_,
    rank_correlation = finite_mean(ranks),
    mean_relative_distance_error = if (is.finite(abs_ref) && abs_ref > 0 && is.finite(abs_err)) abs_err / abs_ref else NA_real_,
    quality_status = "success",
    quality_error = "",
    stringsAsFactors = FALSE
  )
}

compact_value <- function(x) {
  if (is.null(x) || is.list(x) || is.data.frame(x) || is.matrix(x) || !length(x)) return(NA_character_)
  paste(as.character(x), collapse = "|")
}

result_metadata <- function(obj) {
  auto <- attr(obj, "auto_selection", exact = TRUE)
  approx <- attr(obj, "approximation", exact = TRUE)
  gpu <- attr(obj, "gpu_residency", exact = TRUE)
  if (is.null(auto)) auto <- list()
  if (is.null(approx)) approx <- list()
  if (is.null(gpu)) gpu <- list()
  data.frame(
    result_backend = attr(obj, "backend") %||% NA_character_,
    resolved_backend = attr(obj, "resolved_backend") %||% attr(obj, "backend") %||% NA_character_,
    requested_backend = attr(obj, "requested_backend") %||% NA_character_,
    requested_method = attr(obj, "requested_method") %||% NA_character_,
    result_tuning = attr(obj, "tuning") %||% NA_character_,
    exact = attr(obj, "exact") %||% NA,
    auto_predicted_method = auto$predicted_method %||% NA_character_,
    auto_predicted_device = auto$predicted_device %||% NA_character_,
    auto_reason = auto$reason %||% auto$method_decision %||% NA_character_,
    tuning_rule = approx$tuning_rule %||% approx$tuning_policy %||% approx$policy %||% NA_character_,
    tuning_target_met = approx$tuning_benchmark_target_met %||% NA,
    tuning_basis = approx$tuning_benchmark_basis %||% approx$recommendation_basis %||% NA_character_,
    result_residency = gpu$result_residency %||% obj$result_residency %||% attr(obj, "result_residency") %||% NA_character_,
    device_to_host_result_copies = gpu$device_to_host_result_copies %||% obj$device_to_host_result_copies %||% attr(obj, "device_to_host_result_copies") %||% NA,
    stringsAsFactors = FALSE
  )
}

empty_metadata <- function() {
  data.frame(
    result_backend = NA_character_, resolved_backend = NA_character_,
    requested_backend = NA_character_, requested_method = NA_character_,
    result_tuning = NA_character_, exact = NA,
    auto_predicted_method = NA_character_, auto_predicted_device = NA_character_,
    auto_reason = NA_character_, tuning_rule = NA_character_,
    tuning_target_met = NA, tuning_basis = NA_character_,
    result_residency = NA_character_, device_to_host_result_copies = NA,
    stringsAsFactors = FALSE
  )
}

method_thread_metadata <- function(method, threads) {
  id <- as.character(method$method_id[[1L]])
  implementation <- as.character(method$implementation[[1L]])
  kind <- as.character(method$kind[[1L]])
  if (identical(implementation, "faissR")) {
    if (identical(kind, "gpu_resident_knn")) {
      return(list(
        requested = NA_integer_,
        scope = "CUDA provider; nn_gpu() exposes no CPU thread argument"
      ))
    }
    return(list(
      requested = as.integer(threads),
      scope = "faissR n_threads argument"
    ))
  }
  if (id %in% c("RANN_kd", "RANN_bd", "FNN_kd", "FNN_cover", "FNN_brute",
                "nabor_auto", "nabor_brute")) {
    return(list(
      requested = 1L,
      scope = "public interface exposes no thread-count argument"
    ))
  }
  if (id %in% c(
    "RcppAnnoy_euclidean", "RcppAnnoy_angular", "RcppAnnoy_dot_product"
  )) {
    return(list(
      requested = as.integer(threads),
      scope = "serial build; item queries use parallel::mclapply"
    ))
  }
  if (id %in% c("Rnanoflann_standard", "rnndescent_rpf", "rnndescent_rnnd",
                "rnndescent_nnd", "rnndescent_bruteforce",
                "RcppHNSW_hnsw",
                "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
                "BiocNeighbors_annoy", "uwot_nearest_neighbors")) {
    return(list(
      requested = as.integer(threads),
      scope = "public package thread-count argument"
    ))
  }
  list(requested = NA_integer_, scope = "not applicable")
}

method_parameter_string <- function(method, k, metric, target_recall, threads,
                                    output, seed) {
  id <- as.character(method$method_id[[1L]])
  implementation <- as.character(method$implementation[[1L]])
  if (identical(implementation, "faissR")) {
    call_name <- if (identical(method$kind[[1L]], "gpu_resident_knn")) {
      "nn_gpu"
    } else {
      "nn"
    }
    return(sprintf(
      "%s(method=%s,backend=%s,metric=%s,k=%d,exclude_self=TRUE,tuning=auto,target_recall=%s,n_threads=%s,output=%s)",
      call_name,
      method$public_method[[1L]],
      method$backend[[1L]],
      metric,
      as.integer(k),
      format(target_recall, trim = TRUE),
      if (identical(call_name, "nn_gpu")) "not_exposed" else as.integer(threads),
      output
    ))
  }
  switch(
    id,
    Rnanoflann_standard = sprintf(
      "Rnanoflann::nn(query=data,k=%d,parallel=TRUE,cores=%d,sorted=TRUE);remove_self",
      k + 1L, threads
    ),
    RANN_kd = sprintf(
      "RANN::nn2(data,query=data,k=%d,treetype=kd);remove_self", k + 1L
    ),
    RANN_bd = sprintf(
      "RANN::nn2(data,query=data,k=%d,treetype=bd);remove_self", k + 1L
    ),
    rnndescent_rpf = sprintf(
      "rnndescent::rpf_knn(k=%d,metric=%s,n_threads=%d,include_self=TRUE,verbose=FALSE);remove_self",
      k + 1L, metric, threads
    ),
    rnndescent_rnnd = sprintf(
      "rnndescent::rnnd_knn(k=%d,metric=%s,n_threads=%d,verbose=FALSE);remove_self",
      k + 1L, metric, threads
    ),
    rnndescent_nnd = sprintf(
      "rnndescent::nnd_knn(k=%d,metric=%s,n_threads=%d,verbose=FALSE);remove_self",
      k + 1L, metric, threads
    ),
    rnndescent_bruteforce = sprintf(
      "rnndescent::brute_force_knn(k=%d,metric=%s,n_threads=%d);remove_self",
      k + 1L, metric, threads
    ),
    RcppAnnoy_euclidean = sprintf(
      "AnnoyEuclidean(build_trees=50,seed=%d,getNNsByItemList(k=%d));remove_self",
      seed, k + 1L
    ),
    RcppAnnoy_angular = sprintf(
      "AnnoyAngular(build_trees=50,seed=%d,getNNsByItemList(k=%d));remove_self;distance=(angular^2)/2",
      seed, k + 1L
    ),
    RcppAnnoy_dot_product = sprintf(
      "AnnoyDotProduct(build_trees=50,seed=%d,getNNsByItemList(k=%d));remove_self;distance=row_max(score)-score",
      seed, k + 1L
    ),
    RcppHNSW_hnsw = sprintf(
      "RcppHNSW::hnsw_knn(k=%d,distance=%s,M=16,ef_construction=200,ef=%d,n_threads=%d,random_seed=%d);remove_self",
      k + 1L, if (metric == "inner_product") "ip" else metric,
      max(50L, 3L * k), threads, seed
    ),
    BiocNeighbors_exhaustive = sprintf(
      "BiocNeighbors::findKNN(k=%d,ExhaustiveParam(distance=%s),num.threads=%d);remove_self%s",
      k + 1L, if (metric == "cosine") "Cosine" else "Euclidean", threads,
      if (metric == "cosine") ";distance=(normalized_L2^2)/2" else ""
    ),
    BiocNeighbors_hnsw = sprintf(
      "BiocNeighbors::findKNN(k=%d,HnswParam(nlinks=16,ef.construction=200,ef.search=%d,distance=%s),num.threads=%d);remove_self%s",
      k + 1L, max(50L, 3L * k),
      if (metric == "cosine") "Cosine" else "Euclidean", threads,
      if (metric == "cosine") ";distance=(normalized_L2^2)/2" else ""
    ),
    BiocNeighbors_annoy = sprintf(
      "BiocNeighbors::findKNN(k=%d,AnnoyParam(ntrees=50,distance=%s),num.threads=%d);remove_self%s",
      k + 1L, if (metric == "cosine") "Cosine" else "Euclidean", threads,
      if (metric == "cosine") ";distance=(normalized_L2^2)/2" else ""
    ),
    FNN_kd = sprintf(
      "FNN::get.knn(k=%d,algorithm=kd_tree);remove_self", k + 1L
    ),
    FNN_cover = sprintf(
      "FNN::get.knn(k=%d,algorithm=cover_tree);remove_self", k + 1L
    ),
    FNN_brute = sprintf(
      "FNN::get.knn(k=%d,algorithm=brute);remove_self", k + 1L
    ),
    nabor_auto = sprintf(
      "nabor::knn(data,query=data,k=%d,searchtype=auto);remove_self", k + 1L
    ),
    nabor_brute = sprintf(
      "nabor::knn(data,query=data,k=%d,searchtype=brute);remove_self", k + 1L
    ),
    uwot_nearest_neighbors = sprintf(
      "uwot::nearest_neighbors(n_neighbors=%d,metric=%s,n_threads=%d,verbose=FALSE);remove_self",
      k + 1L, metric, threads
    ),
    cuda_ml_knn = "not_standalone: supervised model API; no neighbor matrices",
    Rtsne_neighbors = "not_standalone: consumes precomputed neighbors",
    umap_umap = "embedding consumer; no standalone neighbor result",
    "unrecorded"
  )
}

write_one <- function(path, row) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(row, path, row.names = FALSE)
}

aggregate_success_rows <- function(success) {
  group_cols <- c(
    "dataset", "dataset_md5", "backend", "metric", "k", "target_recall",
    "implementation", "implementation_version", "faissR_version",
    "faissR_package_commit",
    "faissR_image_commit", "method_id", "public_method",
    "kind", "n_threads", "threads_requested", "threading_scope"
  )
  for (name in setdiff(group_cols, names(success))) success[[name]] <- NA
  key_frame <- lapply(success[group_cols], function(x) {
    value <- as.character(x)
    value[is.na(value)] <- "<NA>"
    value
  })
  key <- interaction(key_frame, drop = TRUE, lex.order = TRUE)
  pieces <- lapply(split(success, key), function(x) {
    target <- suppressWarnings(as.numeric(x$target_recall[[1L]]))
    recalls <- suppressWarnings(as.numeric(x$recall_at_k))
    times <- suppressWarnings(as.numeric(x$time_sec))
    copies <- suppressWarnings(as.numeric(x$host_copy_sec))
    rss <- suppressWarnings(as.numeric(x$peak_rss_gb))
    gpu_memory <- if ("gpu_memory_peak_mib" %in% names(x)) {
      suppressWarnings(as.numeric(x$gpu_memory_peak_mib))
    } else {
      numeric()
    }
    data.frame(
      x[1L, group_cols, drop = FALSE],
      n_runs = nrow(x),
      n_validation_seeds = length(unique(x$validation_seed)),
      median_time_sec = if (any(is.finite(times))) stats::median(times[is.finite(times)]) else NA_real_,
      iqr_time_sec = if (sum(is.finite(times)) > 1L) stats::IQR(times[is.finite(times)]) else 0,
      median_host_copy_sec = if (any(is.finite(copies))) stats::median(copies[is.finite(copies)]) else NA_real_,
      median_peak_rss_gb = if (any(is.finite(rss))) stats::median(rss[is.finite(rss)]) else NA_real_,
      median_gpu_memory_peak_mib = if (any(is.finite(gpu_memory))) stats::median(gpu_memory[is.finite(gpu_memory)]) else NA_real_,
      mean_recall_at_k = if (any(is.finite(recalls))) mean(recalls[is.finite(recalls)]) else NA_real_,
      min_seed_recall_at_k = if (any(is.finite(recalls))) min(recalls[is.finite(recalls)]) else NA_real_,
      target_met_all_runs = if (is.finite(target)) all(is.finite(recalls) & recalls >= target) else NA,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, pieces)
  row.names(out) <- NULL
  out
}

read_rows <- function(files) {
  rows <- lapply(files, read.csv, stringsAsFactors = FALSE)
  cols <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    for (nm in setdiff(cols, names(x))) x[[nm]] <- NA
    x[, cols, drop = FALSE]
  })
  do.call(rbind, rows)
}

target_aware_external_comparison <- function(aggregate,
                                             target_recalls,
                                             expected_runs) {
  columns <- c(
    "dataset", "backend", "metric", "k", "target_recall",
    "faissr_method", "faissr_time_sec", "faissr_recall_at_k",
    "external_method", "external_package", "external_time_sec",
    "external_recall_at_k", "speedup_faissr_vs_external"
  )
  empty <- as.data.frame(
    setNames(replicate(length(columns), logical(), simplify = FALSE), columns),
    stringsAsFactors = FALSE
  )
  if (!nrow(aggregate)) return(empty)

  faissr <- aggregate[aggregate$implementation == "faissR", , drop = FALSE]
  external <- aggregate[aggregate$implementation != "faissR", , drop = FALSE]
  if (!nrow(faissr) || !nrow(external)) return(empty)

  target_recalls <- sort(unique(suppressWarnings(as.numeric(target_recalls))))
  target_recalls <- target_recalls[is.finite(target_recalls)]
  keys <- unique(aggregate[, c("dataset", "backend", "metric", "k"), drop = FALSE])
  rows <- list()
  for (target in target_recalls) {
    for (i in seq_len(nrow(keys))) {
      key <- keys[i, , drop = FALSE]
      same_cell <- function(x) {
        x$dataset == key$dataset &
          x$backend == key$backend &
          x$metric == key$metric &
          x$k == key$k
      }
      f <- faissr[
        same_cell(faissr) &
          is.finite(faissr$target_recall) &
          abs(faissr$target_recall - target) < 1e-12 &
          faissr$n_runs >= expected_runs &
          faissr$target_met_all_runs &
          is.finite(faissr$median_time_sec),
        ,
        drop = FALSE
      ]
      e <- external[
        same_cell(external) &
          external$n_runs >= expected_runs &
          is.finite(external$min_seed_recall_at_k) &
          external$min_seed_recall_at_k >= target &
          is.finite(external$median_time_sec),
        ,
        drop = FALSE
      ]
      if (!nrow(f) || !nrow(e)) next
      f <- f[order(f$median_time_sec, f$method_id), , drop = FALSE][1L, , drop = FALSE]
      e <- e[order(e$median_time_sec, e$method_id), , drop = FALSE][1L, , drop = FALSE]
      rows[[length(rows) + 1L]] <- data.frame(
        dataset = key$dataset,
        backend = key$backend,
        metric = key$metric,
        k = key$k,
        target_recall = target,
        faissr_method = f$method_id,
        faissr_time_sec = f$median_time_sec,
        faissr_recall_at_k = f$min_seed_recall_at_k,
        external_method = e$method_id,
        external_package = e$implementation,
        external_time_sec = e$median_time_sec,
        external_recall_at_k = e$min_seed_recall_at_k,
        speedup_faissr_vs_external = e$median_time_sec / f$median_time_sec,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

worker_main <- function(args) {
  configure_threads(scalar_positive_int(args$threads, "1", "threads"))
  if (!available_pkg("faissR")) stop("faissR is not available in this R library.", call. = FALSE)
  ds <- load_dataset(args$data_path)
  method <- read.csv(args$method_row, stringsAsFactors = FALSE)
  k <- scalar_positive_int(args$k, "15", "k")
  metric <- normalize_metric_values(args$metric, "euclidean")[[1L]]
  target_recall <- suppressWarnings(as.numeric(args$target_recall %||% NA_real_))
  threads <- scalar_positive_int(args$threads, "1", "threads")
  output <- args$output %||% "double"
  quality_n <- scalar_positive_int(args$quality_n, "512", "quality_n")
  quality_max_ops <- scalar_positive_number(args$quality_max_ops, "5e9", "quality_max_ops")
  seed <- scalar_positive_int(args$seed, "1", "seed")
  repeat_id <- scalar_positive_int(args$repeat_id, "1", "repeat_id")
  reference_k <- scalar_positive_int(args$reference_k, as.character(k), "reference_k")
  thread_meta <- method_thread_metadata(method, threads)

  base <- data.frame(
    dataset = args$dataset,
    data_path = args$data_path,
    dataset_md5 = args$dataset_md5,
    object_name = ds$object_name,
    n = ds$n,
    p = ds$p,
    shape_group = shape_group(ds$n, ds$p),
    input_type = ds$input_type,
    labels_present = !is.null(ds$labels),
    dataset_suite = args$dataset_suite %||% "real",
    norm_model = args$norm_model %||% NA_character_,
    norm_cv = suppressWarnings(as.numeric(args$norm_cv %||% NA_real_)),
    backend = method$backend,
    method_id = method$method_id,
    implementation = method$implementation,
    faissR_version = as.character(utils::packageVersion("faissR")),
    implementation_version = package_version_string(method$implementation[[1L]]),
    faissR_package_commit = Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
    faissR_image_commit = Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"),
    public_method = method$public_method,
    kind = method$kind,
    metric = metric,
    k = k,
    target_recall = target_recall,
    validation_seed = seed,
    algorithm_seed = algorithm_seed_for(method$method_id[[1L]], seed),
    repeat_id = repeat_id,
    n_threads = threads,
    threads_allocated = threads,
    threads_requested = thread_meta$requested,
    threading_scope = thread_meta$scope,
    method_parameters = method_parameter_string(
      method, k, metric, target_recall, threads, output, seed
    ),
    output = output,
    status = "failed",
    time_sec = NA_real_,
    host_copy_sec = NA_real_,
    peak_rss_gb = NA_real_,
    gpu_memory_peak_mib = NA_real_,
    gpu_memory_source = if (method$backend == "cuda") "pending" else "not_applicable",
    cuda_sync_mode = if (method$backend == "cuda")
      "provider_completion_before_return;explicit_host_copy_timed_separately" else "not_applicable",
    recall_at_k = NA_real_,
    median_recall_at_k = NA_real_,
    min_recall_at_k = NA_real_,
    rank_correlation = NA_real_,
    mean_relative_distance_error = NA_real_,
    quality_eval_n = NA_integer_,
    quality_exact_sec = NA_real_,
    quality_status = NA_character_,
    reference_source = NA_character_,
    reference_backend = NA_character_,
    reference_backend_used = NA_character_,
    reference_path = NA_character_,
    quality_error = "",
    error = "",
    stringsAsFactors = FALSE
  )

  meta <- empty_metadata()
  gpu_sampler <- list(enabled = FALSE, sample = NA_character_, stop = NA_character_)
  if (method$kind %in% c("not_standalone", "embedding_consumer")) {
    base$status <- "not_applicable"
    base$error <- method$detail
    base$quality_status <- "not_applicable"
    base$quality_error <- method$detail
    base$peak_rss_gb <- read_peak_rss_gb()
    write_one(args$result_path, cbind(base, meta))
    return(invisible(NULL))
  }
  tryCatch({
    if (identical(method$public_method[[1L]], "grid") && !(ds$p %in% c(2L, 3L))) {
      stop("grid is only applicable to 2D/3D datasets.", call. = FALSE)
    }
    reference <- load_precomputed_reference(
      args$data_path, reference_k, quality_n, seed, metric, k, args$dataset_md5
    )
    if (is.null(reference)) {
      rows <- choose_quality_rows(ds$n, ds$p, quality_n, quality_max_ops, seed)
      if (!length(rows)) stop("quality subset is empty.", call. = FALSE)
      ref_time <- proc.time()[["elapsed"]]
      reference <- compute_reference(ds$data, rows, k, metric, threads)
      base$quality_exact_sec <- proc.time()[["elapsed"]] - ref_time
      base$reference_source <- "computed_in_worker"
      base$reference_backend <- "cpu"
      base$reference_backend_used <- "faiss_cpu_exact"
    } else {
      rows <- as.integer(reference$rows)
      base$quality_exact_sec <- 0
      base$reference_backend <- as.character(reference$backend %||% NA_character_)
      base$reference_backend_used <- as.character(
        reference$backend_used %||% NA_character_
      )
      base$reference_source <- paste0(
        "precomputed_exact_",
        if (is.na(base$reference_backend) || !nzchar(base$reference_backend)) {
          "unknown"
        } else {
          base$reference_backend
        }
      )
      base$reference_path <- reference$path
    }
    base$quality_eval_n <- length(rows)

    gc()
    gpu_sampler <- start_gpu_memory_sampler(method$backend == "cuda")
    t0 <- proc.time()[["elapsed"]]
    if (method$implementation == "faissR") {
      obj <- run_faissr_method(ds$data, method, k, metric, threads, target_recall, output)
    } else {
      obj <- run_external_method(
        ds$data, method$method_id, k, metric, threads, seed
      )
    }
    base$time_sec <- proc.time()[["elapsed"]] - t0

    if (inherits(obj, "faissR_gpu_knn")) {
      copy_t0 <- proc.time()[["elapsed"]]
      host_obj <- faissR::gpu_knn_to_host(obj)
      base$host_copy_sec <- proc.time()[["elapsed"]] - copy_t0
      meta <- result_metadata(obj)
      obj <- host_obj
    } else {
      base$host_copy_sec <- 0
      if (method$implementation == "faissR") meta <- result_metadata(obj)
    }
    q <- quality_metrics(obj, reference, rows, k)
    base$recall_at_k <- q$recall_at_k
    base$median_recall_at_k <- q$median_recall_at_k
    base$min_recall_at_k <- q$min_recall_at_k
    base$rank_correlation <- q$rank_correlation
    base$mean_relative_distance_error <- q$mean_relative_distance_error
    base$quality_status <- q$quality_status
    base$quality_error <- q$quality_error
    base$status <- "success"
    base$peak_rss_gb <- read_peak_rss_gb()
    gpu_memory <- stop_gpu_memory_sampler(gpu_sampler)
    gpu_sampler$enabled <- FALSE
    base$gpu_memory_peak_mib <- gpu_memory$peak_mib
    base$gpu_memory_source <- gpu_memory$source
  }, error = function(e) {
    base$status <- "failed"
    base$error <- conditionMessage(e)
    base$quality_status <- "failed"
    base$quality_error <- conditionMessage(e)
    base$peak_rss_gb <- read_peak_rss_gb()
    gpu_memory <- stop_gpu_memory_sampler(gpu_sampler)
    gpu_sampler$enabled <- FALSE
    base$gpu_memory_peak_mib <- gpu_memory$peak_mib
    base$gpu_memory_source <- gpu_memory$source
  })
  write_one(args$result_path, cbind(base, meta))
}

summarize_results <- function(out_dir, methods, config) {
  files <- list.files(file.path(out_dir, "worker_results"), pattern = "[.]csv$", full.names = TRUE)
  if (!length(files)) stop("No worker result files were produced.", call. = FALSE)
  res <- read_rows(files)
  res$faissR_version <- rep(
    as.character(utils::packageVersion("faissR")), nrow(res)
  )
  res$faissR_package_commit <- rep(
    Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"), nrow(res)
  )
  res$faissR_image_commit <- rep(
    Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET"), nrow(res)
  )
  res <- res[order(res$dataset, res$backend, res$metric, res$k, res$target_recall, res$implementation, res$method_id), , drop = FALSE]
  utils::write.csv(res, file.path(out_dir, "jmlr_tuned_benchmark_results.csv"), row.names = FALSE)
  utils::write.csv(res[res$status != "success", , drop = FALSE], file.path(out_dir, "jmlr_tuned_benchmark_failures.csv"), row.names = FALSE)

  success <- res[res$status == "success", , drop = FALSE]
  if (nrow(success)) {
    aggregate <- aggregate_success_rows(success)
    utils::write.csv(
      aggregate,
      file.path(out_dir, "jmlr_repeated_run_summary.csv"),
      row.names = FALSE
    )
    eligible <- is.na(aggregate$target_recall) | aggregate$target_met_all_runs
    aggregate_ranked <- aggregate[eligible, , drop = FALSE]
    aggregate_ranked <- aggregate_ranked[order(
      aggregate_ranked$dataset, aggregate_ranked$backend,
      aggregate_ranked$metric, aggregate_ranked$k,
      aggregate_ranked$target_recall, aggregate_ranked$median_time_sec
    ), , drop = FALSE]
    aggregate_keys <- paste(
      aggregate_ranked$dataset, aggregate_ranked$backend,
      aggregate_ranked$metric, aggregate_ranked$k,
      aggregate_ranked$target_recall, sep = "\r"
    )
    utils::write.csv(
      aggregate_ranked[!duplicated(aggregate_keys), , drop = FALSE],
      file.path(out_dir, "jmlr_best_robust_by_dataset_backend_metric_k_target.csv"),
      row.names = FALSE
    )
    success$target_recall_rank <- ifelse(is.na(success$target_recall), -1, success$target_recall)
    success$recall_sort <- ifelse(is.finite(success$recall_at_k), -success$recall_at_k, Inf)
    success$rank_sort <- ifelse(is.finite(success$rank_correlation), -success$rank_correlation, Inf)
    success$err_sort <- ifelse(is.finite(success$mean_relative_distance_error), success$mean_relative_distance_error, Inf)
    success$time_sort <- ifelse(is.finite(success$time_sec), success$time_sec, Inf)
    ranked <- success[order(
      success$dataset, success$backend, success$metric, success$k, success$target_recall_rank,
      success$recall_sort, success$rank_sort, success$err_sort, success$time_sort
    ), , drop = FALSE]
    ranked <- ranked[, setdiff(names(ranked), c("target_recall_rank", "recall_sort", "rank_sort", "err_sort", "time_sort")), drop = FALSE]
    utils::write.csv(ranked, file.path(out_dir, "jmlr_ranked_speed_recall.csv"), row.names = FALSE)

    keys <- paste(ranked$dataset, ranked$backend, ranked$metric, ranked$k, ranked$target_recall, sep = "\r")
    best <- ranked[!duplicated(keys), , drop = FALSE]
    utils::write.csv(best, file.path(out_dir, "jmlr_best_by_dataset_backend_metric_k_target.csv"), row.names = FALSE)

    comparisons <- target_aware_external_comparison(
      aggregate,
      target_recalls = config$target_recalls,
      expected_runs = config$expected_runs
    )
    if (nrow(comparisons)) {
      utils::write.csv(
        comparisons,
        file.path(out_dir, "jmlr_faissr_vs_external_speed.csv"),
        row.names = FALSE
      )
    }
  }

  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  if (available_pkg("faissR")) {
    try(utils::write.csv(faissR::backend_info(), file.path(out_dir, "faissR_backend_info.csv"), row.names = FALSE), silent = TRUE)
    try(utils::write.csv(faissR::nn_capabilities(runtime = TRUE), file.path(out_dir, "faissR_nn_capabilities_runtime.csv"), row.names = FALSE), silent = TRUE)
  }

  md <- c(
    "# JMLR Benchmark Evidence",
    "",
    "This benchmark is designed to answer the manuscript-review concerns about speed evidence, method/library boundaries, autotuning provenance, validation, and GPU-resident KNN output.",
    "",
    "## Configuration",
    "",
    paste0("- Backend file: `", config$backend, "`."),
    paste0("- Metrics: `", paste(config$metrics, collapse = "`, `"), "`."),
    paste0("- k values: `", paste(config$k_values, collapse = "`, `"), "`."),
    paste0("- Target recall tiers for faissR methods: `", paste(config$target_recalls, collapse = "`, `"), "`."),
    paste0("- Threads: `", config$threads, "`."),
    paste0("- Timeout per method/dataset/k/metric/target combination: `", config$timeout, "` seconds."),
    paste0("- Input manifest: `", config$manifest, "`."),
    paste0("- Singularity image recorded by launcher: `", Sys.getenv("SINGULARITY_IMAGE", unset = ""), "`."),
    "",
    "## Output Files",
    "",
    "- `jmlr_tuned_benchmark_results.csv`: full per-combination result table.",
    "- `jmlr_tuned_benchmark_failures.csv`: failed, skipped, timeout, or not-standalone rows with error text.",
    "- `jmlr_repeated_run_summary.csv`: medians, timing IQRs, held-out-seed recall, and all-run target attainment.",
    "- `jmlr_best_robust_by_dataset_backend_metric_k_target.csv`: fastest method only after the target is met in every measured run.",
    "- `jmlr_ranked_speed_recall.csv`: successful rows ranked by recall, rank correlation, distance error, speed, and memory.",
    "- `jmlr_best_by_dataset_backend_metric_k_target.csv`: best method per dataset/backend/metric/k/target recall block.",
    "- `jmlr_faissr_vs_external_speed.csv`: fastest faissR row versus fastest external package row only where both complete all expected runs and reach the same recall tier.",
    "- `faissR_backend_info.csv`, `faissR_nn_capabilities_runtime.csv`, and `sessionInfo.txt`: reproducibility metadata.",
    "",
    "## Interpretation Rules",
    "",
    "- Exact methods are still evaluated against the exact subset reference; exactness is also recorded in result metadata when faissR reports it.",
    "- External package rows are not assigned faissR target-recall tiers; they are run once per dataset/metric/k.",
    "- Every raw row records the implementation version, exact call parameters, allocated threads, requested threads, and threading scope.",
    "- GPU-resident `nn_gpu()` rows record search time separately from `host_copy_sec`, so downstream CUDA pipelines can report no-copy timing while quality evaluation remains possible.",
    "- A low-recall fast method is not considered the best in the quality-aware ranking.",
    "- Unsupported metric/backend/provider combinations are failure evidence, not silent fallbacks."
  )
  writeLines(md, file.path(out_dir, "JMLR_BENCHMARK_README.md"))
  invisible(res)
}

main <- function() {
  args <- parse_args()
  if (logical_arg(args$worker, FALSE, "worker")) {
    worker_main(args)
    return(invisible(NULL))
  }

  backend <- normalize_backend(args$backend)
  manifest <- normalizePath(args$manifest %||% file.path(getwd(), "float32_dataset_manifest.csv"), mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(getwd(), paste0("faissR_JMLR_TUNED_", toupper(backend), "_", format(Sys.time(), "%Y%m%d_%H%M%S"))), mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "worker_results"), recursive = TRUE, showWarnings = FALSE)

  threads <- scalar_positive_int(args$threads, if (backend == "cpu") "12" else "2", "threads")
  timeout <- scalar_positive_int(args$timeout, "2000", "timeout")
  quality_n <- scalar_positive_int(args$quality_n, "512", "quality_n")
  quality_max_ops <- scalar_positive_number(args$quality_max_ops, "5e9", "quality_max_ops")
  seed <- scalar_positive_int(args$seed, "20260706", "seed")
  validation_seeds <- positive_ints(args$validation_seeds, as.character(seed), "validation_seeds")
  repeats <- scalar_positive_int(args$repeats, "3", "repeats")
  k_values <- positive_ints(args$k_values, "15,30,50,100", "k_values")
  metrics <- normalize_metric_values(args$metrics, "euclidean")
  target_recalls <- numeric_values(args$target_recalls, "0.9,0.95,0.99", "target_recalls")
  include_external <- logical_arg(args$include_external, TRUE, "include_external")
  include_gpu_resident <- logical_arg(args$include_gpu_resident, TRUE, "include_gpu_resident")
  output <- args$output %||% "double"
  if (!output %in% c("double", "float")) stop("`output` must be `double` or `float`.", call. = FALSE)

  configure_threads(threads)
  manifest_df <- read.csv(manifest, stringsAsFactors = FALSE)
  if (!"path" %in% names(manifest_df) && "output" %in% names(manifest_df)) manifest_df$path <- manifest_df$output
  if (!all(c("dataset", "path") %in% names(manifest_df))) {
    stop("Manifest must contain `dataset` and `path`/`output` columns.", call. = FALSE)
  }
  if (!"suite" %in% names(manifest_df)) manifest_df$suite <- "real"
  if (!"norm_model" %in% names(manifest_df)) manifest_df$norm_model <- NA_character_
  if (!"norm_cv" %in% names(manifest_df)) manifest_df$norm_cv <- NA_real_
  manifest_df <- manifest_df[file.exists(manifest_df$path), , drop = FALSE]
  datasets <- split_arg(args$datasets, "")
  if (length(datasets)) manifest_df <- manifest_df[manifest_df$dataset %in% datasets, , drop = FALSE]
  if (!nrow(manifest_df)) stop("No datasets selected from manifest.", call. = FALSE)
  manifest_df$dataset_md5 <- vapply(
    manifest_df$path,
    function(path) unname(tools::md5sum(path)[[1L]]),
    character(1)
  )

  methods <- method_table(backend, include_external = include_external, include_gpu_resident = include_gpu_resident)
  wanted_methods <- split_arg(args$methods, "")
  if (length(wanted_methods)) methods <- methods[methods$method_id %in% wanted_methods | methods$public_method %in% wanted_methods, , drop = FALSE]
  if (!nrow(methods)) stop("No methods selected.", call. = FALSE)

  utils::write.csv(manifest_df, file.path(out_dir, "jmlr_selected_datasets.csv"), row.names = FALSE)
  utils::write.csv(methods, file.path(out_dir, "jmlr_method_backend_matrix.csv"), row.names = FALSE)
  config <- data.frame(
    backend = backend,
    manifest = manifest,
    out_dir = out_dir,
    datasets = paste(manifest_df$dataset, collapse = ","),
    methods = paste(methods$method_id, collapse = ","),
    metrics = paste(metrics, collapse = ","),
    k_values = paste(k_values, collapse = ","),
    target_recalls = paste(target_recalls, collapse = ","),
    threads = threads,
    timeout = timeout,
    quality_n = quality_n,
    quality_max_ops = quality_max_ops,
    validation_seeds = paste(validation_seeds, collapse = ","),
    repeats = repeats,
    output = output,
    stringsAsFactors = FALSE
  )
  utils::write.csv(config, file.path(out_dir, "jmlr_benchmark_config.csv"), row.names = FALSE)

  total <- 0L
  script <- script_file()
  method_dir <- file.path(out_dir, "method_rows")
  dir.create(method_dir, recursive = TRUE, showWarnings = FALSE)

  for (validation_seed in validation_seeds) {
    for (repeat_id in seq_len(repeats)) {
      for (di in seq_len(nrow(manifest_df))) {
        for (mi in seq_len(nrow(methods))) {
      method <- methods[mi, , drop = FALSE]
      method_file <- file.path(method_dir, paste0(gsub("[^A-Za-z0-9_]+", "_", method$method_id), ".csv"))
      utils::write.csv(method, method_file, row.names = FALSE)
      method_targets <- if (method$implementation == "faissR") target_recalls else NA_real_
      for (metric in metrics) {
        for (kk in k_values) {
          for (target in method_targets) {
            total <- total + 1L
            result_path <- file.path(
              out_dir, "worker_results",
              sprintf(
                "%04d_%s__%s__%s__k%d__tr%s__seed%d__rep%d.csv",
                total,
                manifest_df$dataset[[di]],
                method$method_id,
                metric,
                kk,
                ifelse(is.na(target), "NA", gsub("[.]", "p", as.character(target))),
                validation_seed,
                repeat_id
              )
            )
            if (file.exists(result_path)) next
            cat(sprintf("[%s] %04d %s / %s / %s / k=%d / target=%s / seed=%d / rep=%d\n",
                        format(Sys.time(), "%Y-%m-%d %H:%M:%S"), total,
                        manifest_df$dataset[[di]], method$method_id, metric, kk,
                        ifelse(is.na(target), "NA", target), validation_seed, repeat_id))
            flush.console()
            rscript <- Sys.getenv("R_BIN", unset = "")
            if (nzchar(rscript)) {
              resolved_rscript <- unname(Sys.which(rscript))
              if (nzchar(resolved_rscript)) rscript <- resolved_rscript
            } else {
              rscript <- file.path(R.home("bin"), "Rscript")
            }
            if (!file.exists(rscript)) stop("Cannot find the worker Rscript binary: ", rscript, call. = FALSE)
            worker_env <- paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep))
            cmd <- c(
              as.character(timeout),
              rscript, script,
              "--worker=TRUE",
              paste0("--dataset=", manifest_df$dataset[[di]]),
              paste0("--data_path=", manifest_df$path[[di]]),
              paste0("--dataset_md5=", manifest_df$dataset_md5[[di]]),
              paste0("--dataset_suite=", manifest_df$suite[[di]] %||% "real"),
              paste0("--norm_model=", manifest_df$norm_model[[di]] %||% NA_character_),
              paste0("--norm_cv=", manifest_df$norm_cv[[di]] %||% NA_real_),
              paste0("--method_row=", method_file),
              paste0("--result_path=", result_path),
              paste0("--k=", kk),
              paste0("--metric=", metric),
              paste0("--target_recall=", target),
              paste0("--threads=", threads),
              paste0("--quality_n=", quality_n),
              paste0("--quality_max_ops=", quality_max_ops),
              paste0("--seed=", validation_seed),
              paste0("--repeat_id=", repeat_id),
              paste0("--reference_k=", max(k_values)),
              paste0("--output=", output)
            )
            status <- system2(
              "timeout",
              cmd,
              env = worker_env,
              stdout = file.path(out_dir, "worker_stdout.log"),
              stderr = file.path(out_dir, "worker_stderr.log")
            )
            if (!file.exists(result_path)) {
              thread_meta <- method_thread_metadata(method, threads)
              row <- data.frame(
                dataset = manifest_df$dataset[[di]],
                data_path = manifest_df$path[[di]],
                dataset_md5 = manifest_df$dataset_md5[[di]],
                object_name = NA_character_,
                n = manifest_df$n[[di]] %||% NA_integer_,
                p = manifest_df$p[[di]] %||% NA_integer_,
                shape_group = NA_character_,
                input_type = NA_character_,
                labels_present = NA,
                dataset_suite = manifest_df$suite[[di]] %||% "real",
                norm_model = manifest_df$norm_model[[di]] %||% NA_character_,
                norm_cv = manifest_df$norm_cv[[di]] %||% NA_real_,
                backend = method$backend,
                method_id = method$method_id,
                implementation = method$implementation,
                faissR_version = as.character(utils::packageVersion("faissR")),
                implementation_version = package_version_string(
                  method$implementation[[1L]]
                ),
                faissR_package_commit = Sys.getenv(
                  "FAISSR_PACKAGE_COMMIT", unset = "UNSET"
                ),
                faissR_image_commit = Sys.getenv(
                  "FAISSR_IMAGE_COMMIT", unset = "UNSET"
                ),
                public_method = method$public_method,
                kind = method$kind,
                metric = metric,
                k = kk,
                target_recall = target,
                validation_seed = validation_seed,
                algorithm_seed = algorithm_seed_for(
                  method$method_id[[1L]], validation_seed
                ),
                repeat_id = repeat_id,
                n_threads = threads,
                threads_allocated = threads,
                threads_requested = thread_meta$requested,
                threading_scope = thread_meta$scope,
                method_parameters = method_parameter_string(
                  method, kk, metric, target, threads, output, validation_seed
                ),
                output = output,
                status = if (identical(status, 124L)) "timeout" else "failed",
                time_sec = if (identical(status, 124L)) timeout else NA_real_,
                host_copy_sec = NA_real_,
                peak_rss_gb = NA_real_,
                recall_at_k = NA_real_,
                median_recall_at_k = NA_real_,
                min_recall_at_k = NA_real_,
                rank_correlation = NA_real_,
                mean_relative_distance_error = NA_real_,
                quality_eval_n = NA_integer_,
                quality_exact_sec = NA_real_,
                quality_status = "failed",
                reference_source = NA_character_,
                reference_backend = NA_character_,
                reference_backend_used = NA_character_,
                reference_path = NA_character_,
                quality_error = paste("worker did not produce result; exit status", status),
                error = paste("worker did not produce result; exit status", status),
                stringsAsFactors = FALSE
              )
              write_one(result_path, cbind(row, empty_metadata()))
          }
        }
      }
        }
      }
    }
  }
  }

  summarize_results(
    out_dir,
    methods,
    list(
      backend = backend, manifest = manifest, metrics = metrics, k_values = k_values,
      target_recalls = target_recalls,
      expected_runs = length(validation_seeds) * repeats,
      threads = threads, timeout = timeout
    )
  )
  cat("DONE: ", out_dir, "\n", sep = "")
}

if (!identical(Sys.getenv("FAISSR_JMLR_SOURCE_ONLY", unset = ""), "true")) {
  main()
}
