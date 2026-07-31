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

package_inventory <- function(packages) {
  rows <- lapply(packages, function(package) {
    available <- requireNamespace(package, quietly = TRUE)
    data.frame(
      package = package,
      role = if (identical(package, "faissR")) {
        "package_under_test"
      } else if (identical(package, "float")) {
        "float32_input_adapter"
      } else {
        "external_cpu_comparator"
      },
      required_for_campaign = TRUE,
      available = available,
      version = if (available) {
        as.character(utils::packageVersion(package))
      } else {
        NA_character_
      },
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

capability_contract <- function(capabilities, backend, method, metric) {
  rows <- capabilities[
    capabilities$backend == backend &
      capabilities$method == method &
      capabilities$metric == metric,
    ,
    drop = FALSE
  ]
  if (nrow(rows) != 1L) {
    stop(
      "Expected one capability row for backend=", backend,
      ", method=", method, ", metric=", metric,
      "; found ", nrow(rows), ".",
      call. = FALSE
    )
  }
  rows[1L, , drop = FALSE]
}

load_external_benchmark_helpers <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  candidate <- if (length(file_arg)) {
    sub("^--file=", "", file_arg[[1L]])
  } else {
    ""
  }
  script <- if (nzchar(candidate) && file.exists(candidate)) {
    normalizePath(candidate, mustWork = TRUE)
  } else {
    normalizePath(
      "benchmark_scripts/jmlr_mloss_publication/common/benchmark_package_route_qa.R",
      mustWork = TRUE
    )
  }
  helper_path <- file.path(dirname(script), "benchmark_jmlr_tuned_methods.R")
  if (!file.exists(helper_path)) {
    stop("External benchmark helper is missing: ", helper_path, call. = FALSE)
  }
  previous <- Sys.getenv("FAISSR_JMLR_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(previous)) {
      Sys.unsetenv("FAISSR_JMLR_SOURCE_ONLY")
    } else {
      Sys.setenv(FAISSR_JMLR_SOURCE_ONLY = previous)
    }
  }, add = TRUE)
  Sys.setenv(FAISSR_JMLR_SOURCE_ONLY = "true")
  helpers <- new.env(parent = globalenv())
  sys.source(helper_path, envir = helpers)
  helpers
}

external_comparator_route_qa <- function(x, out_dir, n_threads = 12L) {
  helpers <- load_external_benchmark_helpers()
  methods <- helpers$external_methods("cpu")
  methods <- methods[
    methods$kind == "knn_search" |
      methods$method_id == "uwot_nearest_neighbors",
    , drop = FALSE
  ]
  k <- 5L
  rows <- list()
  for (method in methods$method_id) {
    metrics <- "euclidean"
    if (isTRUE(helpers$metric_supported_external(method, "cosine"))) {
      metrics <- c(metrics, "cosine")
    }
    for (metric in metrics) {
      public_api_exposed <- !identical(method, "uwot_nearest_neighbors") ||
        "nearest_neighbors" %in% getNamespaceExports("uwot")
      if (!public_api_exposed) {
        rows[[length(rows) + 1L]] <- data.frame(
          method = method, metric = metric, status = "not_public_api",
          public_api_exposed = FALSE, dimensions_pass = NA,
          finite_distance_pass = NA, sorted_distance_pass = NA,
          self_exclusion_pass = NA, conformance_pass = TRUE,
          error = "uwot::nearest_neighbors is not exported by this build.",
          stringsAsFactors = FALSE
        )
        next
      }
      answer <- tryCatch(
        helpers$run_external_method(
          x, method, k, metric, as.integer(n_threads), 20260730L
        ),
        error = function(e) e
      )
      if (inherits(answer, "error")) {
        row <- data.frame(
          method = method, metric = metric, status = "failed",
          public_api_exposed = TRUE, dimensions_pass = FALSE,
          finite_distance_pass = FALSE, sorted_distance_pass = FALSE,
          self_exclusion_pass = FALSE, conformance_pass = FALSE,
          error = conditionMessage(answer), stringsAsFactors = FALSE
        )
      } else {
        indices <- as.matrix(answer$indices)
        distances <- as.matrix(answer$distances)
        dimensions_pass <- identical(dim(indices), c(nrow(x), k)) &&
          identical(dim(distances), c(nrow(x), k))
        self_exclusion_pass <- dimensions_pass && all(vapply(
          seq_len(nrow(indices)),
          function(i) !i %in% indices[i, ],
          logical(1L)
        ))
        sorted_distance_pass <- dimensions_pass && all(apply(
          distances, 1L,
          function(z) all(diff(z[is.finite(z)]) >= -1e-7)
        ))
        row <- data.frame(
          method = method, metric = metric, status = "success",
          public_api_exposed = TRUE,
          dimensions_pass = dimensions_pass,
          finite_distance_pass = all(is.finite(distances)),
          sorted_distance_pass = sorted_distance_pass,
          self_exclusion_pass = self_exclusion_pass,
          conformance_pass = dimensions_pass &&
            all(is.finite(distances)) && sorted_distance_pass &&
            self_exclusion_pass,
          error = "", stringsAsFactors = FALSE
        )
      }
      rows[[length(rows) + 1L]] <- row
    }
  }
  table <- do.call(rbind, rows)
  write.csv(
    table,
    file.path(out_dir, "jss_external_comparator_route_qa.csv"),
    row.names = FALSE
  )
  if (any(!table$conformance_pass)) {
    stop(
      sum(!table$conformance_pass),
      " external comparator route-QA cells failed; inspect ",
      "jss_external_comparator_route_qa.csv.",
      call. = FALSE
    )
  }
  invisible(table)
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
  expected_version <- Sys.getenv("EXPECTED_FAISSR_VERSION", unset = "")
  installed_version <- as.character(utils::packageVersion("faissR"))
  if (nzchar(expected_version) &&
      !identical(installed_version, expected_version)) {
    stop(
      "Frozen campaign requires faissR ", expected_version,
      ", but the Singularity image contains ", installed_version, ".",
      call. = FALSE
    )
  }

  required_packages <- c(
    "faissR", "float", "Rnanoflann", "RANN", "RcppAnnoy", "RcppHNSW",
    "rnndescent", "BiocNeighbors", "FNN", "nabor", "uwot"
  )
  inventory <- package_inventory(required_packages)
  write.csv(
    inventory,
    file.path(out_dir, "jss_environment_packages.csv"),
    row.names = FALSE
  )
  if (any(!inventory$available)) {
    stop(
      "Frozen benchmark image is missing required package(s): ",
      paste(inventory$package[!inventory$available], collapse = ", "),
      ". See jss_environment_packages.csv.",
      call. = FALSE
    )
  }

  if (!isTRUE(faissR::faiss_available())) {
    stop("Mandatory FAISS provider is unavailable.", call. = FALSE)
  }
  if (backend == "cuda") {
    cuda_requirements <- c(
      cuda = isTRUE(faissR::cuda_available()),
      faiss_gpu = isTRUE(faissR::faiss_gpu_available()),
      cuvs = isTRUE(faissR::cuvs_available())
    )
    if (any(!cuda_requirements)) {
      stop(
        "CUDA publication route QA requires CUDA, FAISS-GPU, and cuVS; ",
        "unavailable provider(s): ",
        paste(names(cuda_requirements)[!cuda_requirements], collapse = ", "),
        ".",
        call. = FALSE
      )
    }
  }

  set.seed(20260730)
  x <- matrix(rnorm(1024L * 19L), nrow = 1024L, ncol = 19L)
  rows <- seq_len(64L)
  capabilities <- faissR::nn_capabilities(runtime = FALSE)
  self_query_methods <- c("grid", "nndescent", "nsg", "vamana")

  if (backend == "cpu") {
    external_comparator_route_qa(
      x[seq_len(128L), seq_len(12L), drop = FALSE],
      out_dir,
      n_threads = 12L
    )
  }

  if (backend == "cuda") {
    gpu_input <- float::fl(x)
    gpu_answer <- faissR::nn_gpu(
      gpu_input,
      k = 15L,
      exclude_self = TRUE,
      method = "exact",
      metric = "euclidean",
      tuning = "auto",
      target_recall = 0.99
    )
    gpu_residency <- data.frame(
      backend = backend,
      method = "exact",
      metric = "euclidean",
      inherits_gpu_class = inherits(gpu_answer, "faissR_gpu_knn"),
      handle_externalptr = identical(typeof(gpu_answer$handle), "externalptr"),
      indices_externalptr = identical(
        typeof(gpu_answer$indices_ptr), "externalptr"
      ),
      distances_externalptr = identical(
        typeof(gpu_answer$distances_ptr), "externalptr"
      ),
      result_residency = as.character(
        gpu_answer$result_residency %||% NA_character_
      ),
      device_to_host_result_copies = as.integer(
        gpu_answer$device_to_host_result_copies %||% NA_integer_
      ),
      backend_used = as.character(
        gpu_answer$backend_used %||% NA_character_
      ),
      input_type = as.character(
        gpu_answer$input_type %||% NA_character_
      ),
      float32_compatibility_conversion = as.logical(
        gpu_answer$float32_compatibility_conversion %||% NA
      ),
      stringsAsFactors = FALSE
    )
    gpu_residency$conformance_pass <- with(
      gpu_residency,
      inherits_gpu_class & handle_externalptr & indices_externalptr &
        distances_externalptr & result_residency == "cuda" &
        device_to_host_result_copies == 0L &
        grepl("cuda|gpu|cuvs", backend_used, ignore.case = TRUE) &
        input_type == "float32" & !float32_compatibility_conversion
    )
    write.csv(
      gpu_residency,
      file.path(out_dir, "jss_gpu_residency_qa.csv"),
      row.names = FALSE
    )
    if (!isTRUE(gpu_residency$conformance_pass[[1L]])) {
      stop(
        "`nn_gpu()` failed the GPU-resident zero-host-copy contract; ",
        "inspect jss_gpu_residency_qa.csv.",
        call. = FALSE
      )
    }
    rm(gpu_answer, gpu_input)
    invisible(gc())

    set.seed(20261713L)
    lowdim <- matrix(rnorm(1024L), ncol = 2L)
    lowdim <- lowdim / sqrt(rowSums(lowdim * lowdim))
    lowdim <- float::fl(lowdim)
    lowdim_cpu <- faissR::nn(
      lowdim,
      k = 15L,
      exclude_self = TRUE,
      backend = "cpu",
      method = "flat",
      metric = "euclidean",
      n_threads = 2L
    )
    lowdim_gpu <- faissR::nn_gpu(
      lowdim,
      k = 15L,
      exclude_self = TRUE,
      method = "exact",
      metric = "euclidean"
    )
    lowdim_host <- faissR::gpu_knn_to_host(lowdim_gpu)
    per_query_recall <- vapply(seq_len(nrow(lowdim_cpu$indices)), function(i) {
      mean(lowdim_host$indices[i, ] %in% lowdim_cpu$indices[i, ])
    }, numeric(1))
    lowdim_qa <- data.frame(
      backend = backend,
      method = "exact",
      metric = "euclidean",
      n = nrow(lowdim),
      p = ncol(lowdim),
      k = 15L,
      backend_used = as.character(lowdim_gpu$backend_used %||% NA_character_),
      result_residency = as.character(lowdim_gpu$result_residency %||% NA_character_),
      device_to_host_result_copies_before_materialization = as.integer(
        lowdim_gpu$device_to_host_result_copies %||% NA_integer_
      ),
      mean_recall = mean(per_query_recall),
      min_recall = min(per_query_recall),
      max_distance_error = max(abs(
        as.numeric(lowdim_host$distances) - as.numeric(lowdim_cpu$distances)
      )),
      stringsAsFactors = FALSE
    )
    lowdim_qa$conformance_pass <- with(
      lowdim_qa,
      backend_used == "cuda_native_exact_gpu" &
        result_residency == "cuda" &
        device_to_host_result_copies_before_materialization == 0L &
        mean_recall == 1 & min_recall == 1 & max_distance_error <= 1e-6
    )
    write.csv(
      lowdim_qa,
      file.path(out_dir, "jss_gpu_lowdim_exact_qa.csv"),
      row.names = FALSE
    )
    if (!isTRUE(lowdim_qa$conformance_pass[[1L]])) {
      stop(
        "The cancellation-resistant 2D CUDA exact route failed QA; ",
        "inspect jss_gpu_lowdim_exact_qa.csv.",
        call. = FALSE
      )
    }
    rm(lowdim, lowdim_cpu, lowdim_gpu, lowdim_host)
    invisible(gc())
  }

  results <- list()
  for (method in methods) {
    for (metric in metrics) {
      capability <- capability_contract(
        capabilities, backend, method, metric
      )
      route_source <- if (identical(method, "grid")) {
        x[, seq_len(2L), drop = FALSE]
      } else {
        x
      }
      route_x <- float::fl(route_source)
      self_query <- method %in% self_query_methods
      query_mode <- if (self_query) "self" else "separate"
      expected_rows <- if (self_query) nrow(route_x) else length(rows)
      if (!isTRUE(capability$supported[[1L]])) {
        results[[length(results) + 1L]] <- data.frame(
          backend = backend, method = method, metric = metric,
          query_mode = query_mode, expected_supported = FALSE,
          status = "unsupported", elapsed_sec = 0,
          dimensions_pass = NA, finite_distance_pass = NA,
          sorted_distance_pass = NA, route_pass = NA,
          resolved_backend = NA_character_, requested_method = method,
          capability_notes = capability$notes[[1L]] %||% "",
          error = "", stringsAsFactors = FALSE
        )
        next
      }
      route_points <- if (self_query) {
        NULL
      } else {
        float::fl(route_source[rows, , drop = FALSE])
      }
      started <- proc.time()[["elapsed"]]
      answer <- tryCatch(
        faissR::nn(
          route_x,
          points = route_points,
          k = 15L,
          exclude_self = self_query,
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
          query_mode = query_mode, expected_supported = TRUE,
          status = "failed", elapsed_sec = elapsed,
          dimensions_pass = FALSE, finite_distance_pass = FALSE,
          sorted_distance_pass = FALSE, route_pass = FALSE,
          resolved_backend = NA_character_, requested_method = method,
          capability_notes = capability$notes[[1L]] %||% "",
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
          query_mode = query_mode, expected_supported = TRUE,
          status = "success", elapsed_sec = elapsed,
          dimensions_pass = identical(
            dim(indices), c(as.integer(expected_rows), 15L)
          ) && identical(
            dim(distances), c(as.integer(expected_rows), 15L)
          ),
          finite_distance_pass = all(is.finite(distances)),
          sorted_distance_pass = all(apply(
            distances, 1L,
            function(z) all(diff(z[is.finite(z)]) >= -1e-7)
          )),
          route_pass = route_pass,
          resolved_backend = resolved,
          requested_method = method,
          capability_notes = capability$notes[[1L]] %||% "",
          error = "", stringsAsFactors = FALSE
        )
      }
      results[[length(results) + 1L]] <- row
    }
  }
  table <- do.call(rbind, results)
  table$conformance_pass <- with(
    table,
    status == "unsupported" |
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
  writeLines(
    c(
      sprintf("expected_faissR_version=%s", expected_version),
      sprintf("installed_faissR_version=%s", installed_version),
      sprintf("backend=%s", backend)
    ),
    file.path(out_dir, "jss_package_route_qa_metadata.txt")
  )
  if (any(!table$conformance_pass)) {
    stop(
      sum(!table$conformance_pass),
      " package route-QA cells failed; inspect jss_package_route_qa.csv.",
      call. = FALSE
    )
  }
}

if (!identical(Sys.getenv("FAISSR_JMLR_SOURCE_ONLY", unset = ""), "true")) {
  main()
}
