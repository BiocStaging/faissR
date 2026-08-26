source_benchmark_helpers <- function(path, stop_marker) {
  if (!file.exists(path)) {
    testthat::skip("Benchmark scripts are not available in this installed-package test context.")
  }
  old_out <- Sys.getenv("FAISSR_BENCHMARK_OUT", unset = NA_character_)
  tmp_out <- tempfile("faissR_benchmark_test_")
  Sys.setenv(FAISSR_BENCHMARK_OUT = tmp_out)
  on.exit({
    if (is.na(old_out)) {
      Sys.unsetenv("FAISSR_BENCHMARK_OUT")
    } else {
      Sys.setenv(FAISSR_BENCHMARK_OUT = old_out)
    }
    unlink(tmp_out, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  lines <- readLines(path, warn = FALSE)
  stop_at <- grep(stop_marker, lines, fixed = TRUE)[1L] - 1L
  env <- new.env(parent = globalenv())
  conn <- textConnection(lines[seq_len(stop_at)])
  on.exit(close(conn), add = TRUE)
  old_wd <- getwd()
  setwd(dirname(path))
  on.exit(setwd(old_wd), add = TRUE)
  source(conn, local = env)
  env
}


test_that("NN metric benchmark isolates high-work CPU native timeout risks", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )

  large_x <- matrix(0, nrow = 50000L, ncol = 2L)
  cuda_feasible_x <- matrix(0, nrow = 70000L, ncol = 784L)
  giant_x <- matrix(0, nrow = 2000000L, ncol = 32L)
  small_x <- matrix(0, nrow = 100L, ncol = 2L)

  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "auto",
      method = "exact",
      preflight_route = "cpu",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "hnsw",
      preflight_route = "faiss_hnsw",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "auto",
      preflight_route = "cpu_auto",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "ivf",
      preflight_route = "faiss_ivf",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "nndescent",
      preflight_route = "cpu_nndescent",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_native_timeout(
      large_x,
      backend = "auto",
      method = "hnsw",
      preflight_route = "faiss_hnsw",
      isolate_native_timeout = TRUE
    )
  )
  expect_false(
    env$should_isolate_native_timeout(
      small_x,
      backend = "cpu",
      method = "hnsw",
      preflight_route = "faiss_hnsw",
      isolate_native_timeout = TRUE
    )
  )
  expect_false(
    env$should_isolate_native_timeout(
      small_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      isolate_native_timeout = TRUE
    )
  )
  expect_false(
    env$should_isolate_native_timeout(
      large_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      isolate_native_timeout = FALSE
    )
  )
  expect_true(
    env$should_preflight_cpu_exhaustive_timeout(
      large_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      preflight_cpu_exhaustive_timeout = TRUE,
      preflight_cpu_exhaustive_timeout_ops = 5e10
    )
  )
  expect_true(
    env$should_preflight_cpu_exhaustive_timeout(
      large_x,
      backend = "auto",
      method = "exact",
      preflight_route = "cpu",
      preflight_cpu_exhaustive_timeout = TRUE,
      preflight_cpu_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cpu_exhaustive_timeout(
      large_x,
      backend = "cpu",
      method = "hnsw",
      preflight_route = "faiss_hnsw",
      preflight_cpu_exhaustive_timeout = TRUE,
      preflight_cpu_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cpu_exhaustive_timeout(
      small_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      preflight_cpu_exhaustive_timeout = TRUE,
      preflight_cpu_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cpu_exhaustive_timeout(
      large_x,
      backend = "cpu",
      method = "flat",
      preflight_route = "faiss_flat_l2",
      preflight_cpu_exhaustive_timeout = FALSE,
      preflight_cpu_exhaustive_timeout_ops = 5e10
    )
  )
  expect_true(
    env$should_preflight_cuda_exhaustive_timeout(
      giant_x,
      backend = "auto",
      method = "exact",
      preflight_route = "faiss_gpu_flat_l2",
      preflight_cuda_exhaustive_timeout = TRUE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_true(
    env$should_preflight_cuda_exhaustive_timeout(
      giant_x,
      backend = "cuda",
      method = "bruteforce",
      preflight_route = "cuda_cuvs_bruteforce",
      preflight_cuda_exhaustive_timeout = TRUE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cuda_exhaustive_timeout(
      giant_x,
      backend = "cuda",
      method = "hnsw",
      preflight_route = "cuda_cuvs_hnsw",
      preflight_cuda_exhaustive_timeout = TRUE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cuda_exhaustive_timeout(
      cuda_feasible_x,
      backend = "cuda",
      method = "flat",
      preflight_route = "faiss_gpu_flat_l2",
      preflight_cuda_exhaustive_timeout = TRUE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cuda_exhaustive_timeout(
      small_x,
      backend = "cuda",
      method = "flat",
      preflight_route = "faiss_gpu_flat_l2",
      preflight_cuda_exhaustive_timeout = TRUE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_false(
    env$should_preflight_cuda_exhaustive_timeout(
      large_x,
      backend = "cuda",
      method = "flat",
      preflight_route = "faiss_gpu_flat_l2",
      preflight_cuda_exhaustive_timeout = FALSE,
      preflight_cuda_exhaustive_timeout_ops = 5e10
    )
  )
  expect_true(
    env$should_isolate_cuda_native_timeout(
      large_x,
      backend = "auto",
      method = "auto",
      preflight_route = "auto",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_cuda_native_timeout(
      large_x,
      backend = "cuda",
      method = "hnsw",
      preflight_route = "cuda_cuvs_hnsw",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_cuda_native_timeout(
      large_x,
      backend = "auto",
      method = "exact",
      preflight_route = "faiss_gpu_flat_l2",
      isolate_native_timeout = TRUE
    )
  )
  expect_true(
    env$should_isolate_cuda_native_timeout(
      large_x,
      backend = "cuda",
      method = "bruteforce",
      preflight_route = "cuda_cuvs_bruteforce",
      isolate_native_timeout = TRUE
    )
  )
  expect_false(
    env$should_isolate_cuda_native_timeout(
      large_x,
      backend = "cpu",
      method = "hnsw",
      preflight_route = "faiss_hnsw",
      isolate_native_timeout = TRUE
    )
  )
})

test_that("NN metric benchmark uses exported process cleanup for forked timeouts", {
  script <- test_path("../../benchmark_scripts/benchmark_nn_metrics.R")
  env <- source_benchmark_helpers(script, "args <- parse_args()")

  expect_equal(
    env$fork_job_pid(structure(list(pid = 12345L), class = "parallelJob")),
    12345L
  )
  expect_true(is.function(env$terminate_fork_job))
  expect_false(any(grepl("parallel::mckill", readLines(script), fixed = TRUE)))
})

test_that("NN metric benchmark treats system timeout exit codes as timeouts", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )

  expect_true(env$is_child_system_timeout(structure(character(), status = 124L), 124L))
  expect_true(env$is_child_system_timeout(structure(character(), timeout = TRUE), NA_integer_))
  expect_false(env$is_child_system_timeout(structure(character(), status = 1L), 1L))
})

test_that("benchmark materials document key row-level and summary outputs", {
  files <- list(
    nn = c(
      "nn_metric_benchmark_config.csv",
      "nn_metric_benchmark_results.csv",
      "nn_metric_capabilities.csv",
      "nn_metric_cagra_capabilities.csv",
      "nn_metric_cycle_summary.csv",
      "nn_metric_recommendations_from_cycles.csv",
      "nn_metric_auto_vs_cycle_recommendation.csv",
      "nn_metric_global_recommendations_from_cycles.csv",
      "nn_metric_auto_vs_global_recommendation.csv",
      "nn_metric_best_by_dataset_backend_metric_k.csv",
      "nn_metric_best_by_dataset_backend_metric_k_cycle.csv",
      "nn_metric_fastest_at_recall_threshold.csv",
      "nn_metric_auto_vs_fastest.csv",
      "MATERIALS_AND_METHODS_nn_metrics.md"
    ),
    kmeans = c(
      "kmeans_benchmark_config.csv",
      "kmeans_runtime_capabilities.csv",
      "kmeans_benchmark_results.csv",
      "kmeans_best_by_dataset.csv",
      "kmeans_best_by_dataset_centers.csv",
      "kmeans_cycle_summary.csv",
      "kmeans_recommendations_from_cycles.csv",
      "kmeans_backend_recommendations_from_cycles.csv",
      "kmeans_fast_vs_cycle_recommendation.csv",
      "kmeans_auto_vs_global_recommendation.csv",
      "kmeans_fast_vs_stats.csv",
      "MATERIALS_AND_METHODS_kmeans.md"
    )
  )
  scripts <- c(
    nn = test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    kmeans = test_path("../../benchmark_scripts/benchmark_kmeans.R")
  )
  docs_file <- test_path("../../docs/benchmarks.md")
  if (!all(file.exists(scripts)) || !file.exists(docs_file)) {
    skip("Benchmark scripts or GitHub benchmark documentation are not available in this installed-package test context.")
  }

  docs <- paste(readLines(docs_file, warn = FALSE), collapse = "\n")
  for (name in names(files)) {
    script <- paste(readLines(scripts[[name]], warn = FALSE), collapse = "\n")
    for (file in files[[name]]) {
      expect_true(grepl(file, script, fixed = TRUE), info = scripts[[name]])
      expect_true(grepl(file, docs, fixed = TRUE), info = docs_file)
    }
  }

  nn_script <- paste(readLines(scripts[["nn"]], warn = FALSE), collapse = "\n")
  expect_true(grepl("faissR_package_path", nn_script, fixed = TRUE))
  expect_true(grepl("faissR_namespace_path", nn_script, fixed = TRUE))
  expect_true(grepl("r_libpaths", nn_script, fixed = TRUE))
})

test_that("benchmark scripts parse before long-running execution", {
  scripts <- test_path("../../benchmark_scripts", c(
    "benchmark_nn_metrics.R",
    "benchmark_kmeans.R",
    "benchmark1_nn_speed.R"
  ))
  missing <- scripts[!file.exists(scripts)]
  if (length(missing)) {
    skip("Benchmark scripts are not available in this installed-package test context.")
  }

  for (script in scripts) {
    expect_error(parse(script), NA, info = basename(script))
  }
})

test_that("benchmark dataset defaults use the requested real and simulated datasets", {
  real_datasets <- c(
    "COIL20",
    "USPS",
    "FashionMNIST",
    "FlowRepository_FR-FCM-ZYRM_files",
    "flow18",
    "MNIST",
    "imagenet",
    "MetRef",
    "mass41"
  )
  scripts <- list(
    nn = list(
      path = test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
      stop = "args <- parse_args()",
      simulated = c("SimulatedUniform2D", "SimulatedUniform3D")
    ),
    kmeans = list(
      path = test_path("../../benchmark_scripts/benchmark_kmeans.R"),
      stop = "args <- parse_args()",
      simulated = "SimulatedTiny3Clusters"
    )
  )

  for (name in names(scripts)) {
    script <- scripts[[name]]
    env <- source_benchmark_helpers(script$path, script$stop)
    script_text <- paste(readLines(script$path, warn = FALSE), collapse = "\n")
    expect_equal(env$dataset_index("/data")$dataset, real_datasets, info = name)
    expect_true(grepl("- Default real datasets:", script_text, fixed = TRUE), info = name)
    expect_true(grepl("- Default simulated datasets:", script_text, fixed = TRUE), info = name)
    default_datasets <- env$split_arg(
      NULL,
      paste(c(env$dataset_index("/data")$dataset, script$simulated), collapse = ",")
    )
    expect_equal(default_datasets, c(real_datasets, script$simulated), info = name)
    expect_true(grepl("\"available_datasets\"", script_text, fixed = TRUE), info = name)
    expect_true(grepl("accepted by the dataset selector", script_text, fixed = TRUE), info = name)
  }
})



test_that("NN metric benchmark preflights every unsupported capability row", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  caps <- nn_capabilities()
  unsupported <- caps[!caps$supported, , drop = FALSE]
  expect_gt(nrow(unsupported), 0L)

  for (i in seq_len(nrow(unsupported))) {
    row <- unsupported[i, , drop = FALSE]
    label <- sprintf("%s/%s/%s", row$backend, row$method, row$metric)
    skip <- env$is_expected_skip(caps, row$backend, row$method, row$metric)
    expect_type(skip, "list")
    expect_true(
      isTRUE(skip$skip),
      info = label
    )
    expect_true(
      nzchar(skip$notes),
      info = label
    )
  }
})

test_that("NN metric benchmark preflights supported rows as runnable or runtime skips", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  caps <- nn_capabilities()
  supported <- caps[caps$supported, , drop = FALSE]
  expect_gt(nrow(supported), 0L)

  for (i in seq_len(nrow(supported))) {
    row <- supported[i, , drop = FALSE]
    label <- sprintf("%s/%s/%s", row$backend, row$method, row$metric)
    skip <- env$is_expected_skip(caps, row$backend, row$method, row$metric)
    if (is.null(skip)) {
      resolved <- faissR:::resolve_public_nn_backend(row$backend, row$method, row$metric)
      expect_type(resolved, "character")
      expect_true(nzchar(resolved), info = label)
    } else {
      expect_type(skip, "list")
      expect_true(isTRUE(skip$skip), info = label)
      expect_true(nzchar(skip$notes), info = label)
    }
  }
})

test_that("NN metric benchmark consumes runtime capability columns when present", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  caps <- nn_capabilities(runtime = TRUE)

  cpu_flat <- env$capability_status(caps, "cpu", "flat", "euclidean")
  expect_true(isTRUE(cpu_flat$supported))
  expect_equal(cpu_flat$resolved_backend, "faiss_flat_l2")
  expect_equal(cpu_flat$runtime_available, faiss_available())
  expect_equal(cpu_flat$runtime_reason, if (faiss_available()) "available" else "missing_faiss")
  expect_true(nzchar(cpu_flat$runtime_notes))

  cuda_flat <- env$is_expected_skip(caps, "cuda", "flat", "euclidean")
  if (isTRUE(faiss_gpu_available())) {
    expect_null(cuda_flat)
  } else {
    expect_type(cuda_flat, "list")
    expect_true(isTRUE(cuda_flat$skip))
    expect_equal(cuda_flat$route, "faiss_gpu_flat_l2")
    expect_match(cuda_flat$notes, "FAISS GPU|not available|unavailable", ignore.case = TRUE)
  }
})

test_that("NN metric benchmark recommendations are grouped by backend metric and k", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A", "A", "A", "A", "B", "B", "C", "C"),
    backend = c("cpu", "cpu", "cpu", "cpu", "cuda", "cuda", "cpu", "cpu", "cpu", "cpu"),
    method = c("exact", "hnsw", "exact", "hnsw", "flat", "cagra", "ivf", "hnsw", "flat", "ivf"),
    metric = c("euclidean", "euclidean", "cosine", "cosine", "euclidean", "euclidean", "euclidean", "euclidean", "euclidean", "euclidean"),
    k = c(15L, 15L, 15L, 15L, 50L, 50L, 15L, 15L, 100L, 100L),
    median_elapsed_sec = c(10, 2, 8, 3, 4, 1, 1, 3, 8, 2),
    median_recall_at_k = c(1.00, 0.99, 1.00, 0.97, 1.00, 0.99, 0.94, 0.96, NA, NA),
    min_recall_at_k = c(1.00, 0.98, 1.00, 0.96, 1.00, 0.98, 0.93, 0.95, NA, NA),
    median_min_recall_at_k = c(1.00, 0.98, 1.00, 0.96, 1.00, 0.98, 0.93, 0.95, NA, NA),
    recall_reference = c("exact", "exact", "exact", "exact", "exact", "exact", "exact", "exact", NA, NA),
    median_recall_query_n = c(100, 100, 100, 100, 100, 100, 100, 100, NA, NA),
    result_backend = c("cpu", "faiss_hnsw", "cpu", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_cagra", "faiss_ivf", "faiss_hnsw", "faiss_flat_l2", "faiss_ivf"),
    resolved_backend = c("cpu", "faiss_hnsw", "cpu", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_cagra", "faiss_ivf", "faiss_hnsw", "faiss_flat_l2", "faiss_ivf"),
    implementation_backend = c("cpu", "faiss_hnsw", "cpu", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_cagra", "faiss_ivf", "faiss_hnsw", "faiss_flat_l2", "faiss_ivf"),
    success_cycles = rep(2L, 10)
  )

  out <- env$recommend_nn_methods(cycle_summary, recall_threshold = 0.98)
  expect_equal(nrow(out), 5L)
  expect_equal(out$dataset, c("A", "A", "A", "B", "C"))
  expect_equal(out$backend, c("cpu", "cpu", "cuda", "cpu", "cpu"))
  expect_equal(out$metric, c("cosine", "euclidean", "euclidean", "euclidean", "euclidean"))
  expect_equal(as.integer(out$k), c(15L, 15L, 50L, 15L, 100L))
  expect_equal(out$method, c("exact", "hnsw", "cagra", "hnsw", "ivf"))
  expect_equal(
    out$recommendation_basis,
    c(
      "fastest_at_recall_threshold",
      "fastest_at_recall_threshold",
      "fastest_at_recall_threshold",
      "best_recall_below_threshold",
      "speed_only_no_recall"
    )
  )
})

test_that("NN metric benchmark recommendation ties prefer stronger recall stability", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "B", "B"),
    backend = c("cpu", "cpu", "cpu", "cpu"),
    method = c("lower_recall", "higher_recall", "lower_min_recall", "higher_min_recall"),
    metric = c("euclidean", "euclidean", "cosine", "cosine"),
    k = c(15L, 15L, 15L, 15L),
    median_elapsed_sec = c(1, 1, 1, 1),
    median_recall_at_k = c(0.985, 0.990, 0.960, 0.960),
    min_recall_at_k = c(0.980, 0.980, 0.940, 0.950),
    median_min_recall_at_k = c(0.980, 0.980, 0.940, 0.950),
    recall_reference = c("exact", "exact", "exact", "exact"),
    median_recall_query_n = c(100, 100, 100, 100),
    result_backend = c("cpu", "cpu", "cpu", "cpu"),
    resolved_backend = c("cpu", "cpu", "cpu", "cpu"),
    implementation_backend = c("cpu", "cpu", "cpu", "cpu"),
    success_cycles = c(2L, 2L, 2L, 2L)
  )

  out <- env$recommend_nn_methods(cycle_summary, recall_threshold = 0.98)
  expect_equal(out$method, c("higher_recall", "higher_min_recall"))
  expect_equal(
    out$recommendation_basis,
    c("fastest_at_recall_threshold", "best_recall_below_threshold")
  )
})

test_that("NN metric cycle summaries preserve route and thread metadata", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A"),
    backend = c("cpu", "cpu"),
    method = c("auto", "auto"),
    metric = c("euclidean", "euclidean"),
    k = c(50L, 50L),
    n = c(100L, 100L),
    p = c(10L, 10L),
    n_threads = c(2L, 2L),
    cycle = c(1L, 2L),
    elapsed_sec = c(1, 2),
    recall_at_k = c(0.99, 0.98),
    min_recall_at_k = c(0.97, 0.96),
    recall_query_n = c(100L, 100L),
    exact = c(FALSE, FALSE),
    result_backend = c("faiss_hnsw", "faiss_hnsw"),
    result_requested_backend = c("auto", "auto"),
    result_requested_method = c("auto", "auto"),
    result_tuning = c("auto", "auto"),
    resolved_backend = c("faiss_hnsw", "faiss_hnsw"),
    implementation_backend = c("faiss_hnsw", "faiss_hnsw"),
    preflight_route = c("faiss_hnsw", "faiss_hnsw"),
    recall_reference = c("sample", "sample")
  )

  out <- env$summarize_nn_cycles(ok)
  expect_equal(out$n_threads, 2L)
  expect_equal(out$result_requested_backend, "auto")
  expect_equal(out$result_requested_method, "auto")
  expect_equal(out$result_tuning, "auto")
  expect_equal(out$preflight_route, "faiss_hnsw")
  expect_equal(out$success_cycles, 2L)
  expect_true("median_mean_relative_distance_error" %in% names(out))
  expect_true("median_rank_correlation" %in% names(out))
  expect_true("min_rank_correlation" %in% names(out))
})

test_that("NN metric cycle summaries keep CAGRA providers separate", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A"),
    backend = c("cuda", "cuda"),
    method = c("cagra", "cagra"),
    cagra_implementation = c("faiss_gpu", "cuvs"),
    metric = c("euclidean", "euclidean"),
    k = c(50L, 50L),
    n = c(100L, 100L),
    p = c(10L, 10L),
    n_threads = c(2L, 2L),
    cycle = c(1L, 1L),
    elapsed_sec = c(1, 2),
    recall_at_k = c(0.99, 0.98),
    min_recall_at_k = c(0.97, 0.96),
    recall_query_n = c(100L, 100L),
    exact = c(FALSE, FALSE),
    result_backend = c("faiss_gpu_cagra", "cuda_cuvs_cagra"),
    result_requested_backend = c("cuda", "cuda"),
    result_requested_method = c("cagra", "cagra"),
    result_tuning = c("auto", "auto"),
    resolved_backend = c("faiss_gpu_cagra", "cuda_cuvs_cagra"),
    implementation_backend = c("faiss_gpu_cagra", "cuda_cuvs_cagra"),
    preflight_route = c("faiss_gpu_cagra", "cuda_cuvs_cagra"),
    recall_reference = c("sample", "sample")
  )

  out <- env$summarize_nn_cycles(ok)
  expect_equal(nrow(out), 2L)
  expect_equal(sort(out$cagra_implementation), c("cuvs", "faiss_gpu"))
  expect_equal(sort(out$implementation_backend), c("cuda_cuvs_cagra", "faiss_gpu_cagra"))
})

test_that("NN metric best-row ranking prefers recall stability before speed", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A", "A", "B", "B"),
    backend = c("cpu", "cpu", "cpu", "cuda", "cuda"),
    method = c("fast_unstable", "slow_stable", "lower_recall", "fast_missing_recall", "slow_missing_recall"),
    metric = c("euclidean", "euclidean", "euclidean", "cosine", "cosine"),
    k = c(50L, 50L, 50L, 15L, 15L),
    cycle = c(1L, 1L, 1L, 1L, 1L),
    recall_at_k = c(0.99, 0.99, 0.98, NA, NA),
    min_recall_at_k = c(0.80, 0.95, 0.98, NA, NA),
    elapsed_sec = c(1, 2, 0.5, 1, 2),
    stringsAsFactors = FALSE
  )

  ranked <- env$rank_nn_metric_success(ok)
  best <- ranked[!duplicated(paste(ranked$dataset, ranked$backend, ranked$metric, ranked$k, sep = "__")), ]
  expect_equal(best$method, c("slow_stable", "fast_missing_recall"))

  ranked_cycle <- env$rank_nn_metric_success(ok, include_cycle = TRUE)
  best_cycle <- ranked_cycle[!duplicated(paste(ranked_cycle$dataset, ranked_cycle$backend, ranked_cycle$metric, ranked_cycle$k, ranked_cycle$cycle, sep = "__")), ]
  expect_equal(best_cycle$method, c("slow_stable", "fast_missing_recall"))
})

test_that("NN metric best rows use threshold-aware speed and recall rules", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A", "B", "B", "C", "C", "D", "D"),
    backend = c("cpu", "cpu", "cpu", "cpu", "cuda", "cuda", "cuda", "cuda"),
    method = c(
      "slow_perfect", "fast_good",
      "lower_recall_fast", "higher_recall_slow",
      "fast_missing_recall", "slow_missing_recall",
      "cycle1_fast_good", "cycle2_fast_good"
    ),
    metric = c("euclidean", "euclidean", "cosine", "cosine", "correlation", "correlation", "euclidean", "euclidean"),
    k = c(50L, 50L, 15L, 15L, 10L, 10L, 5L, 5L),
    cycle = c(1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L),
    recall_at_k = c(1.00, 0.99, 0.94, 0.96, NA, NA, 0.99, 0.99),
    min_recall_at_k = c(1.00, 0.98, 0.93, 0.95, NA, NA, 0.98, 0.98),
    elapsed_sec = c(4, 1, 1, 3, 1, 2, 2, 1),
    stringsAsFactors = FALSE
  )

  best <- env$select_nn_metric_best_rows(ok, recall_threshold = 0.98)
  expect_equal(best$method, c("fast_good", "higher_recall_slow", "fast_missing_recall", "cycle2_fast_good"))

  best_cycle <- env$select_nn_metric_best_rows(ok, recall_threshold = 0.98, include_cycle = TRUE)
  expect_equal(best_cycle$method, c("fast_good", "higher_recall_slow", "fast_missing_recall", "cycle1_fast_good", "cycle2_fast_good"))
})


test_that("NN metric benchmark validates public backend labels", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )

  expect_equal(
    env$validate_backend_values(c("auto", "cpu", "cuda", "cpu")),
    c("auto", "cpu", "cuda")
  )
  expect_error(
    env$validate_backend_values(c("cpu", "gpu")),
    "Invalid value\\(s\\): gpu"
  )
  expect_error(
    env$validate_backend_values(character()),
    "at least one backend"
  )
})

test_that("NN metric benchmark requires canonical public method labels", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  caps <- nn_capabilities()

  expect_equal(
    env$canonical_method_values(c("exact", "hnsw", "cagra")),
    c("exact", "hnsw", "cagra")
  )
  expect_error(
    env$canonical_method_values(c("HNSW", "faiss_hnsw")),
    "canonical lowercase"
  )
  expect_error(
    env$canonical_method_values(c("HNSW", "faiss_hnsw")),
    "Valid value\\(s\\): auto, exact, flat, bruteforce, grid, hnsw, ivf, ivfpq, vamana, nsg, nndescent, ivfpq_fastscan, cagra"
  )
  expect_error(
    env$canonical_method_values(character()),
    "at least one method"
  )
  expect_false(isTRUE(env$capability_status(caps, "cpu", "HNSW", "euclidean")$supported))
  expect_false(isTRUE(env$capability_status(caps, "cpu", "faiss_hnsw", "euclidean")$supported))
})

test_that("NN metric benchmark validates dataset selectors", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  valid <- c("COIL20", "USPS", "SimulatedUniform2D", "SimulatedUniform3D", "SimulatedTiny3Clusters")

  expect_equal(
    env$validate_dataset_values(c("COIL20", "USPS", "COIL20"), valid),
    c("COIL20", "USPS")
  )
  expect_error(
    env$validate_dataset_values(c("COIL20", "bad_dataset"), valid),
    "Invalid value\\(s\\): bad_dataset"
  )
  expect_error(
    env$validate_dataset_values(character(), valid),
    "at least one dataset"
  )
})


test_that("NN metric benchmark reference policy records exact CPU and cap skips", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )

  x <- matrix(seq_len(30), nrow = 10L)
  ref <- env$metric_reference(
    x,
    k = 3L,
    metric = "euclidean",
    quality_n = 20L,
    quality_max_ops = 1e6,
    n_threads = 1L,
    seed = 1L
  )
  expect_equal(ref$mode, "full")
  expect_null(ref$rows)
  expect_equal(dim(ref$knn$indices), c(10L, 3L))

  old_cuda <- env$cuda_exact_reference_available
  env$cuda_exact_reference_available <- function(metric) FALSE
  on.exit(env$cuda_exact_reference_available <- old_cuda, add = TRUE)
  expect_null(env$metric_reference(
    matrix(0, nrow = 20L, ncol = 200L),
    k = 3L,
    metric = "euclidean",
    quality_n = 10L,
    quality_max_ops = 1,
    n_threads = 1L,
    seed = 1L
  ))
  expect_equal(env$cuda_reference_ops_limit(1), 100)
})

test_that("NN metric auto comparison preserves recommendation basis", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A"),
    backend = c("cpu", "cpu"),
    method = c("auto", "hnsw"),
    metric = c("euclidean", "euclidean"),
    k = c(50L, 50L),
    result_backend = c("faiss_hnsw", "faiss_hnsw"),
    result_requested_backend = c("auto", "cpu"),
    result_requested_method = c("auto", "hnsw"),
    result_tuning = c("auto", "auto"),
    auto_predicted_method = c("hnsw", NA_character_),
    auto_predicted_device = c("cpu", NA_character_),
    auto_explicit_backend = c(FALSE, NA),
    auto_explicit_method = c(FALSE, NA),
    auto_backend_decision = c("auto_cpu_fallback", NA_character_),
    auto_method_decision = c("auto_cpu_fallback", NA_character_),
    resolved_backend = c("faiss_hnsw", "faiss_hnsw"),
    implementation_backend = c("faiss_hnsw", "faiss_hnsw"),
    preflight_route = c("faiss_hnsw", "faiss_hnsw"),
    route_parameters = c("approximation.m=16;approximation.ef_search=150", "approximation.m=16;approximation.ef_search=150"),
    tuning_status = c(NA_character_, NA_character_),
    n_threads = c(2L, 2L),
    success_cycles = c(2L, 2L),
    median_elapsed_sec = c(5, 4),
    median_recall_at_k = c(0.99, 0.99),
    min_recall_at_k = c(0.98, 0.98),
    median_min_recall_at_k = c(0.98, 0.98),
    recall_reference = c("sample", "sample"),
    median_recall_query_n = c(512, 512)
  )
  recommendations <- cycle_summary[2, , drop = FALSE]
  recommendations$recommendation_basis <- "fastest_at_recall_threshold"

  out <- env$compare_auto_to_recommendations(cycle_summary, recommendations)

  expect_equal(anyDuplicated(names(out)), 0L)
  expect_equal(out$recommended_recommendation_basis, "fastest_at_recall_threshold")
  expect_true("recommended_recommendation_basis" %in% names(out))
  expect_equal(out$auto_result_requested_backend, "auto")
  expect_equal(out$recommended_result_requested_backend, "cpu")
  expect_equal(out$auto_result_requested_method, "auto")
  expect_equal(out$recommended_result_requested_method, "hnsw")
  expect_equal(out$auto_result_tuning, "auto")
  expect_equal(out$auto_auto_predicted_method, "hnsw")
  expect_equal(out$auto_auto_predicted_device, "cpu")
  expect_false(out$auto_auto_explicit_backend)
  expect_false(out$auto_auto_explicit_method)
  expect_equal(out$auto_auto_backend_decision, "auto_cpu_fallback")
  expect_equal(out$auto_auto_method_decision, "auto_cpu_fallback")
  expect_equal(out$auto_preflight_route, "faiss_hnsw")
  expect_equal(out$recommended_preflight_route, "faiss_hnsw")
  expect_equal(out$auto_route_parameters, "approximation.m=16;approximation.ef_search=150")
  expect_equal(out$recommended_route_parameters, "approximation.m=16;approximation.ef_search=150")
  expect_equal(out$auto_n_threads, 2L)
  expect_equal(out$recommended_n_threads, 2L)
})

test_that("NN metric global recommendations pool across requested backends", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A", "A"),
    backend = c("auto", "cpu", "cuda", "cuda"),
    method = c("auto", "hnsw", "flat", "ivf"),
    metric = c("euclidean", "euclidean", "euclidean", "euclidean"),
    k = c(50L, 50L, 50L, 50L),
    result_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_ivf_flat"),
    result_requested_backend = c("auto", "cpu", "cuda", "cuda"),
    result_requested_method = c("auto", "hnsw", "flat", "ivf"),
    result_tuning = c("auto", "auto", "auto", "auto"),
    auto_predicted_method = c("hnsw", NA_character_, NA_character_, NA_character_),
    auto_predicted_device = c("cpu", NA_character_, NA_character_, NA_character_),
    resolved_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_ivf_flat"),
    implementation_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_ivf_flat"),
    preflight_route = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_l2", "faiss_gpu_ivf_flat"),
    route_parameters = c("hnsw", "hnsw", "flat", "ivf"),
    tuning_status = c("balanced", "balanced", NA_character_, "fixed"),
    n_threads = c(2L, 2L, 2L, 2L),
    success_cycles = c(2L, 2L, 2L, 2L),
    median_elapsed_sec = c(4, 5, 2, 3),
    median_recall_at_k = c(0.99, 0.995, 0.99, 0.96),
    min_recall_at_k = c(0.98, 0.99, 0.98, 0.95),
    median_min_recall_at_k = c(0.98, 0.99, 0.98, 0.95),
    recall_reference = c("sample", "sample", "sample", "sample"),
    median_recall_query_n = c(512, 512, 512, 512)
  )

  rec <- env$recommend_nn_global_methods(cycle_summary, recall_threshold = 0.98)
  expect_equal(nrow(rec), 1L)
  expect_equal(rec$backend, "cuda")
  expect_equal(rec$method, "flat")
  expect_equal(rec$recommendation_basis, "global_fastest_at_recall_threshold")

  out <- env$compare_auto_to_global_recommendations(cycle_summary, rec)
  expect_equal(anyDuplicated(names(out)), 0L)
  expect_true("auto_backend" %in% names(out))
  expect_true("recommended_backend" %in% names(out))
  auto_row <- out[out$auto_method == "auto", , drop = FALSE]
  expect_equal(nrow(auto_row), 1L)
  expect_equal(auto_row$recommended_backend, "cuda")
  expect_false(auto_row$auto_uses_recommended_requested_backend)
  expect_false(auto_row$auto_uses_recommended_implementation)
  expect_equal(auto_row$auto_median_speed_ratio, 2)
  expect_equal(auto_row$auto_median_recall_gap, 0)
})

test_that("NN metric benchmark extracts compact backend route parameters", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  out <- list(indices = matrix(1L, 1L, 1L), distances = matrix(0, 1L, 1L))
  attr(out, "approximation") <- list(
    strategy = "faiss_IndexHNSWFlat",
    backend = "faiss_hnsw",
    library = "faiss",
    m = 16L,
    ef_search = 150L,
    tuning_policy = "auto_shape_metric",
    tuning_rule = "balanced_shape_metric",
    tuning_high_dim = TRUE,
    tuning_large_k = FALSE,
    pq_tuning_policy = "auto_pq_shape_metric",
    pq_tuning_rule = "pq_high_dim_shape",
    pq_tuning_high_dim = TRUE,
    tuning = list(status = "target_met", results = data.frame(recall = 0.99))
  )
  attr(out, "spatial_index") <- list(strategy = "ignored_grid", bins_per_dim = 32L)
  attr(out, "auto_selection") <- list(
    policy = "cpp_static_shape_k_metric_selector",
    explicit_backend = TRUE,
    explicit_method = FALSE,
    backend_decision = "explicit_cpu",
    method_decision = "cpu_auto_shape_selector",
    predicted_backend = "faiss_hnsw",
    predicted_method = "hnsw",
    predicted_device = "cpu",
    reason = "cpu_auto_shape_selector",
    slow_tuning = FALSE
  )
  attr(out, "metric_transform") <- "row_l2_normalize_then_euclidean_graph_search"
  attr(out, "distance_transform") <- "normalized_euclidean_squared_over_2_to_1_minus_similarity"

  params <- env$nn_route_parameters(out)
  expect_match(params, "approximation.strategy=faiss_IndexHNSWFlat", fixed = TRUE)
  expect_match(params, "approximation.m=16", fixed = TRUE)
  expect_match(params, "approximation.ef_search=150", fixed = TRUE)
  expect_match(params, "approximation.tuning_policy=auto_shape_metric", fixed = TRUE)
  expect_match(params, "approximation.tuning_rule=balanced_shape_metric", fixed = TRUE)
  expect_match(params, "approximation.tuning_high_dim=TRUE", fixed = TRUE)
  expect_match(params, "approximation.tuning_large_k=FALSE", fixed = TRUE)
  expect_match(params, "approximation.pq_tuning_policy=auto_pq_shape_metric", fixed = TRUE)
  expect_match(params, "approximation.pq_tuning_rule=pq_high_dim_shape", fixed = TRUE)
  expect_match(params, "approximation.pq_tuning_high_dim=TRUE", fixed = TRUE)
  expect_match(params, "spatial_index.bins_per_dim=32", fixed = TRUE)
  expect_match(params, "auto_selection.explicit_backend=TRUE", fixed = TRUE)
  expect_match(params, "auto_selection.explicit_method=FALSE", fixed = TRUE)
  expect_match(params, "auto_selection.backend_decision=explicit_cpu", fixed = TRUE)
  expect_match(params, "auto_selection.method_decision=cpu_auto_shape_selector", fixed = TRUE)
  expect_match(params, "auto_selection.predicted_method=hnsw", fixed = TRUE)
  expect_match(params, "auto_selection.predicted_device=cpu", fixed = TRUE)
  expect_match(params, "auto_selection.reason=cpu_auto_shape_selector", fixed = TRUE)
  expect_match(params, "nn_metric.metric_transform=row_l2_normalize_then_euclidean_graph_search", fixed = TRUE)
  expect_match(params, "nn_metric.distance_transform=normalized_euclidean_squared_over_2_to_1_minus_similarity", fixed = TRUE)
  expect_equal(env$nn_tuning_status(out), "target_met")

  attr(out, "approximation")$tuning <- NULL
  expect_equal(env$nn_tuning_status(out), "balanced_shape_metric")
})

test_that("NN metric auto comparison guards speed ratios and recall gaps", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "B", "B"),
    backend = c("cpu", "cpu", "cuda", "cuda"),
    method = c("auto", "hnsw", "auto", "flat"),
    metric = c("euclidean", "euclidean", "cosine", "cosine"),
    k = c(50L, 50L, 15L, 15L),
    result_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_cosine", "faiss_gpu_flat_cosine"),
    result_requested_backend = c("auto", "cpu", "auto", "cuda"),
    result_requested_method = c("auto", "hnsw", "auto", "flat"),
    result_tuning = c("auto", "auto", "auto", "auto"),
    resolved_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_cosine", "faiss_gpu_flat_cosine"),
    implementation_backend = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_cosine", "faiss_gpu_flat_cosine"),
    preflight_route = c("faiss_hnsw", "faiss_hnsw", "faiss_gpu_flat_cosine", "faiss_gpu_flat_cosine"),
    n_threads = c(2L, 2L, 2L, 2L),
    success_cycles = c(1L, 1L, 1L, 1L),
    median_elapsed_sec = c(1, 0, 1, 2),
    median_recall_at_k = c(0.99, 0.99, NA, 0.98),
    min_recall_at_k = c(0.98, 0.98, NA, 0.97),
    median_min_recall_at_k = c(0.98, 0.98, NA, 0.97),
    recall_reference = c("sample", "sample", NA, "sample"),
    median_recall_query_n = c(512, 512, NA, 512)
  )
  recommendations <- cycle_summary[c(2, 4), , drop = FALSE]
  recommendations$recommendation_basis <- c("fastest_at_recall_threshold", "fastest_at_recall_threshold")

  out <- env$compare_auto_to_recommendations(cycle_summary, recommendations)
  expect_true(is.na(out$auto_median_speed_ratio[out$dataset == "A"]))
  expect_true(is.na(out$auto_median_recall_gap[out$dataset == "B"]))
  expect_true(is.finite(out$auto_median_speed_ratio[out$dataset == "B"]))
})

test_that("NN metric auto-vs-fastest guards speed ratios and recall gaps", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "B"),
    backend = c("cpu", "cuda"),
    method = c("auto", "auto"),
    metric = c("euclidean", "cosine"),
    k = c(50L, 15L),
    cycle = c(1L, 1L),
    result_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    result_requested_backend = c("auto", "auto"),
    result_requested_method = c("auto", "auto"),
    result_tuning = c("auto", "auto"),
    resolved_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    implementation_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    elapsed_sec = c(1, 1),
    recall_at_k = c(0.99, NA),
    recall_reference = c("sample", NA),
    recall_query_n = c(512, NA)
  )
  fastest <- data.frame(
    dataset = c("A", "B"),
    backend = c("cpu", "cuda"),
    method = c("hnsw", "flat"),
    metric = c("euclidean", "cosine"),
    k = c(50L, 15L),
    cycle = c(1L, 1L),
    result_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    result_requested_backend = c("cpu", "cuda"),
    result_requested_method = c("hnsw", "flat"),
    result_tuning = c("auto", "auto"),
    resolved_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    implementation_backend = c("faiss_hnsw", "faiss_gpu_flat_cosine"),
    elapsed_sec = c(0, 2),
    recall_at_k = c(0.99, 0.98),
    recall_reference = c("sample", "sample"),
    recall_query_n = c(512, 512)
  )

  out <- env$compare_auto_to_fastest(ok, fastest)

  expect_equal(out$fastest_method, c("hnsw", "flat"))
  expect_equal(out$auto_result_requested_backend, c("auto", "auto"))
  expect_equal(out$fastest_result_requested_backend, c("cpu", "cuda"))
  expect_equal(out$auto_result_requested_method, c("auto", "auto"))
  expect_equal(out$fastest_result_requested_method, c("hnsw", "flat"))
  expect_true(is.na(out$auto_speed_ratio[out$dataset == "A"]))
  expect_true(is.na(out$auto_recall_gap[out$dataset == "B"]))
  expect_true(is.finite(out$auto_speed_ratio[out$dataset == "B"]))
})

test_that("NN metric benchmark accounts for data-shaped method skips", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )

  default_methods <- env$default_nn_method_values()
  expect_false("removed_method" %in% default_methods)
  expect_true("grid" %in% default_methods)
  expect_equal(
    env$validate_cagra_implementation_values(c("auto", "faiss", "direct-cuvs")),
    c("auto", "faiss_gpu", "cuvs")
  )
  expect_equal(
    env$cagra_implementation_values_for("cuda", "cagra", c("faiss_gpu", "cuvs")),
    c("faiss_gpu", "cuvs")
  )
  expect_true(is.na(env$cagra_implementation_values_for("cuda", "auto", c("faiss_gpu", "cuvs"))))
  expect_true(is.na(env$cagra_implementation_values_for("auto", "auto", c("faiss_gpu", "cuvs"))))
  expect_true(
    is.na(env$cagra_implementation_values_for(
      "cuda",
      "auto",
      c("faiss_gpu", "cuvs"),
      data = matrix(0, nrow = 20L, ncol = 4L),
      metric = "euclidean",
      k = 5L
    ))
  )
  expect_true(is.na(env$cagra_implementation_values_for("cpu", "auto", c("faiss_gpu", "cuvs"))))
  expect_true(is.na(env$cagra_implementation_values_for("cpu", "cagra", c("faiss_gpu", "cuvs"))))
  expect_error(
    env$validate_cagra_implementation_values("invalid_provider"),
    "cagra_implementations"
  )

  caps <- data.frame(
    backend = c("cuda", "cuda"),
    method = c("cagra", "auto"),
    metric = c("euclidean", "euclidean"),
    supported = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  )
  tagged <- env$tag_cagra_capabilities(list(faiss_gpu = caps, cuvs = caps))
  expect_equal(nrow(tagged), 4L)
  expect_equal(names(tagged)[[1L]], "cagra_implementation")
  expect_equal(sort(unique(tagged$cagra_implementation)), c("cuvs", "faiss_gpu"))

  dense <- matrix(rnorm(20), ncol = 4)
  grid_skip <- env$nn_data_expected_skip(dense, "grid")
  expect_type(grid_skip, "list")
  expect_true(isTRUE(grid_skip$skip))
  expect_equal(grid_skip$reason, "unsupported_shape")
  expect_match(grid_skip$notes, "two- or three-column")
  expect_match(grid_skip$notes, "4 columns")
  expect_null(env$nn_data_expected_skip(matrix(rnorm(20), ncol = 2), "grid"))
  expect_null(env$nn_data_expected_skip(matrix(rnorm(30), ncol = 3), "grid"))
  expect_null(env$nn_data_expected_skip(matrix(rnorm(80 * 4), ncol = 4), "nsg"))
  expect_null(env$nn_data_expected_skip(matrix(rnorm(120 * 4), ncol = 4), "nsg"))
  ivfpq_skip <- env$nn_data_expected_skip(matrix(rnorm(120 * 4), ncol = 4), "ivfpq", backend = "cpu")
  expect_equal(ivfpq_skip$reason, "insufficient_training_rows")
  expect_match(ivfpq_skip$notes, "at least 624 training rows")
  expect_null(env$nn_data_expected_skip(matrix(rnorm(120 * 4), ncol = 4), "ivfpq", backend = "cuda"))
  expect_null(env$nn_data_expected_skip(matrix(rnorm(700 * 4), ncol = 4), "ivfpq", backend = "cpu"))
  wide <- matrix(0, nrow = 10L, ncol = 12000L)
  nnd_skip <- env$nn_data_expected_skip(wide, "nndescent", backend = "cuda")
  expect_equal(nnd_skip$reason, "runtime_unavailable_shape")
  expect_equal(nnd_skip$route, "cuda_cuvs_nndescent")
  expect_match(nnd_skip$notes, "compact very-wide")
  expect_null(env$nn_data_expected_skip(matrix(rnorm(10L * 11999L), nrow = 10L), "nndescent", backend = "cuda"))
  expect_null(env$nn_data_expected_skip(matrix(rnorm(20), ncol = 4), "flat"))
})

test_that("NN metric benchmark preserves provider-specific CAGRA skip routes", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  caps <- data.frame(
    backend = rep("cuda", 2L),
    method = rep("cagra", 2L),
    metric = rep("euclidean", 2L),
    supported = c(TRUE, TRUE),
    notes = c("FAISS GPU CAGRA", "direct cuVS CAGRA"),
    resolved_backend = c("faiss_gpu_cagra", "cuda_cuvs_cagra"),
    runtime_available = c(FALSE, FALSE),
    runtime_reason = c("missing_faiss_gpu", "missing_cuvs"),
    runtime_notes = c("FAISS GPU unavailable", "cuVS unavailable"),
    stringsAsFactors = FALSE
  )

  faiss_skip <- env$is_expected_skip(caps[1L, , drop = FALSE], "cuda", "cagra", "euclidean")
  cuvs_skip <- env$is_expected_skip(caps[2L, , drop = FALSE], "cuda", "cagra", "euclidean")

  expect_true(isTRUE(faiss_skip$skip))
  expect_true(isTRUE(cuvs_skip$skip))
  expect_equal(faiss_skip$route, "faiss_gpu_cagra")
  expect_equal(cuvs_skip$route, "cuda_cuvs_cagra")
  expect_equal(faiss_skip$reason, "missing_faiss_gpu")
  expect_equal(cuvs_skip$reason, "missing_cuvs")
  expect_match(faiss_skip$notes, "FAISS GPU unavailable", fixed = TRUE)
  expect_match(cuvs_skip$notes, "cuVS unavailable", fixed = TRUE)
})

test_that("NN metric benchmark raw rows record expected-skip reason labels", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_nn_metrics.R"),
    "args <- parse_args()"
  )
  row <- env$result_row(
    dataset = "A",
    n = 100L,
    p = 4L,
    backend = "cpu",
    method = "grid",
    metric = "euclidean",
    k = 15L,
    cycle = 1L,
    n_threads = 2L,
    status = "expected_skip",
    error = "grid requires 2D/3D data",
    expected_skip = TRUE,
    expected_skip_reason = "unsupported_shape",
    capability_notes = "grid requires 2D/3D data",
    preflight_route = "cpu_grid"
  )

  expect_true("expected_skip_reason" %in% names(row))
  expect_true("cagra_implementation" %in% names(row))
  expect_true(isTRUE(row$expected_skip))
  expect_equal(row$expected_skip_reason, "unsupported_shape")
  expect_equal(row$preflight_route, "cpu_grid")
})




test_that("legacy Benchmark #1 extracts faissR result route and tuning metadata", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )
  out <- list(indices = matrix(1L, 1L, 1L), distances = matrix(0, 1L, 1L))
  attr(out, "backend") <- "cpu"
  attr(out, "requested_backend") <- "cpu"
  attr(out, "requested_method") <- "faiss_hnsw"
  attr(out, "resolved_backend") <- "faiss_hnsw"
  attr(out, "tuning") <- "auto"
  attr(out, "approximation") <- list(
    strategy = "faiss_IndexHNSWFlat",
    backend = "faiss_hnsw",
    m = 16L,
    ef_search = 150L,
    tuning_policy = "auto_shape_metric",
    tuning_rule = "balanced_shape_metric",
    pq_tuning_rule = "pq_high_dim_shape"
  )
  attr(out, "auto_selection") <- list(
    explicit_backend = TRUE,
    explicit_method = FALSE,
    backend_decision = "explicit_cpu",
    method_decision = "cpu_auto_shape_selector",
    predicted_method = "faiss_hnsw",
    predicted_device = "cpu",
    reason = "cpu_auto_shape_selector"
  )

  params <- env$benchmark1_route_parameters(out)
  expect_equal(env$benchmark1_implementation_backend(out), "faiss_hnsw")
  expect_match(params, "approximation.strategy=faiss_IndexHNSWFlat", fixed = TRUE)
  expect_match(params, "approximation.tuning_rule=balanced_shape_metric", fixed = TRUE)
  expect_match(params, "approximation.pq_tuning_rule=pq_high_dim_shape", fixed = TRUE)
  expect_match(params, "auto_selection.explicit_backend=TRUE", fixed = TRUE)
  expect_match(params, "auto_selection.backend_decision=explicit_cpu", fixed = TRUE)
  expect_match(params, "auto_selection.predicted_method=faiss_hnsw", fixed = TRUE)
  expect_match(params, "auto_selection.predicted_device=cpu", fixed = TRUE)
  expect_equal(env$benchmark1_tuning_status(out), "balanced_shape_metric")
})


test_that("legacy Benchmark #1 uses canonical direct cuVS IVF row", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  methods <- env$method_table()
  expect_false("faissR_cuda_ivf" %in% methods$method)
  expect_true("faissR_cuda_cuvs_ivf_flat" %in% methods$method)

  aliases <- env$benchmark_method_aliases(c("cuda_ivf", "faissR_cuda_ivf", "faissR_cuda_cuvs_ivf_flat"))
  expect_equal(aliases, "faissR_cuda_cuvs_ivf_flat")
})


test_that("legacy Benchmark #1 validates k-value grids", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  expect_equal(
    env$benchmark1_k_values(k_values = NULL, env_k_values = NA_character_),
    c(5L, 10L, 15L, 50L, 100L)
  )
  expect_equal(
    env$benchmark1_k_values("5,10,10", env_k_values = NA_character_),
    c(5L, 10L)
  )
  expect_equal(
    env$benchmark1_k_values(k_values = NULL, env_k_values = "15,50"),
    c(15L, 50L)
  )
  expect_error(
    env$benchmark1_k_values("5,bad", env_k_values = NA_character_),
    "Invalid value\\(s\\): bad"
  )
  expect_error(
    env$benchmark1_k_values("0", env_k_values = NA_character_),
    "Invalid value\\(s\\): 0"
  )
  expect_error(
    env$benchmark1_k_values("15.5", env_k_values = NA_character_),
    "Invalid value\\(s\\): 15.5"
  )
  expect_error(
    env$benchmark1_k_values("", env_k_values = ""),
    "at least one positive integer"
  )
})

test_that("legacy Benchmark #1 validates scalar numeric controls", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  expect_equal(env$benchmark1_positive_int_arg(NULL, "threads", "4"), 4L)
  expect_equal(env$benchmark1_positive_int_arg("12", "threads", "4"), 12L)
  expect_equal(env$benchmark1_positive_int_arg("50", "k", "15"), 50L)
  expect_equal(env$benchmark1_positive_int_arg("600", "timeout", "60"), 600L)
  expect_error(
    env$benchmark1_positive_int_arg("zero", "threads", "4"),
    "positive integer"
  )
  expect_error(
    env$benchmark1_positive_int_arg("bad", "k", "15"),
    "positive integer"
  )
  expect_error(
    env$benchmark1_positive_int_arg("15.5", "k", "15"),
    "positive integer"
  )
  expect_error(
    env$benchmark1_positive_int_arg(0, "timeout", "60"),
    "positive integer"
  )
  expect_equal(
    env$benchmark1_positive_numeric_arg(NULL, "quality_max_ops", "5e9"),
    5e9
  )
  expect_equal(
    env$benchmark1_positive_numeric_arg("1e6", "quality_max_ops", "5e9"),
    1e6
  )
  expect_error(
    env$benchmark1_positive_numeric_arg("many", "quality_max_ops", "5e9"),
    "positive numeric"
  )
  expect_error(
    env$benchmark1_positive_numeric_arg(0, "quality_max_ops", "5e9"),
    "positive numeric"
  )
})


test_that("legacy Benchmark #1 best ranking is quality-aware before speed", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  success <- data.frame(
    dataset = c("A", "A", "A", "B", "B"),
    metric = c("euclidean", "euclidean", "euclidean", "cosine", "cosine"),
    k = c(15L, 15L, 15L, 50L, 50L),
    method = c(
      "fast_low_recall",
      "slow_high_recall",
      "same_recall_better_rank",
      "fast_missing_quality",
      "slow_missing_quality"
    ),
    time_sec = c(1, 5, 4, 1, 2),
    peak_rss_gb = c(2, 1, 1, 1, 1),
    recall_at_k = c(0.80, 0.95, 0.95, NA, NA),
    rank_correlation = c(0.80, 0.90, 0.92, NA, NA),
    mean_relative_distance_error = c(0.20, 0.10, 0.08, NA, NA),
    stringsAsFactors = FALSE
  )

  ranked <- env$rank_benchmark1_success(success)
  best <- ranked[!duplicated(paste(ranked$dataset, ranked$metric, ranked$k, sep = "\r")), ]

  expect_equal(best$method, c("same_recall_better_rank", "fast_missing_quality"))
})

test_that("legacy Benchmark #1 writes faissR versus external speed summaries", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  success <- data.frame(
    dataset = c("A", "A", "A", "B"),
    metric = rep("euclidean", 4L),
    k = c(15L, 15L, 15L, 30L),
    backend = c("CPU", "CPU", "CPU", "CUDA"),
    implementation = c("faissR", "faissR", "RANN", "faissR"),
    method = c("faissR_hnsw", "faissR_flat", "RANN_kd", "faissR_cuda_cuvs_cagra"),
    backend_detail = c("FAISS HNSW", "FAISS Flat", "CPU", "Direct RAPIDS cuVS"),
    kind = rep("knn_search", 4L),
    status = rep("success", 4L),
    time_sec = c(4, 10, 5, 2),
    recall_at_k = c(0.99, 1, 1, 0.99),
    peak_rss_gb = c(2, 3, 1, 4),
    stringsAsFactors = FALSE
  )

  speed_ranked <- env$benchmark1_rank_speed_only(success)
  expect_equal(speed_ranked$method[1L], "faissR_hnsw")

  summary <- env$benchmark1_faissr_external_speed_summary(success)
  cpu <- summary[summary$dataset == "A", , drop = FALSE]
  cuda <- summary[summary$dataset == "B", , drop = FALSE]

  expect_equal(cpu$faissr_method, "faissR_hnsw")
  expect_equal(cpu$external_method, "RANN_kd")
  expect_equal(cpu$speedup_faissr_vs_external, 5 / 4)
  expect_equal(cpu$fastest_source, "faissR")
  expect_equal(cuda$faissr_method, "faissR_cuda_cuvs_cagra")
  expect_true(is.na(cuda$external_method))
  expect_equal(cuda$fastest_source, "faissR")
})

test_that("legacy Benchmark #1 quality metrics guard invalid finite means", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )

  candidate <- list(
    indices = matrix(c(NA_integer_, NA_integer_), nrow = 1),
    distances = matrix(c(Inf, NA_real_), nrow = 1)
  )
  reference <- list(
    indices = matrix(c(1L, 2L), nrow = 1),
    distances = matrix(c(Inf, NA_real_), nrow = 1)
  )

  expect_true(is.na(env$benchmark1_finite_mean(c(Inf, NA_real_, NaN))))
  expect_true(is.na(env$knn_rank_correlation(candidate, reference, k = 2L)))
})


test_that("benchmark KNN recall ignores missing neighbour padding", {
  source_file <- test_path("../../benchmark_scripts/source.R")
  if (!file.exists(source_file)) {
    skip("Benchmark scripts are not available in this installed-package test context.")
  }
  env <- new.env(parent = globalenv())
  source(source_file, local = env)

  approx <- list(indices = matrix(
    c(1L, NA_integer_, 2L, NA_integer_),
    nrow = 2L,
    byrow = TRUE
  ))
  exact <- list(indices = matrix(
    c(1L, NA_integer_, 3L, NA_integer_),
    nrow = 2L,
    byrow = TRUE
  ))

  out <- env$benchmark_knn_recall(approx, exact, k = 2L)

  expect_equal(out$recall_at_k, 0.5)
  expect_equal(out$median_recall_at_k, 0.5)
  expect_equal(out$min_recall_at_k, 0)
  quality <- env$benchmark_knn_quality(
    list(
      indices = matrix(c(1L, 2L, 2L, 4L), nrow = 2L, byrow = TRUE),
      distances = matrix(c(0, 1, 0, 2), nrow = 2L, byrow = TRUE)
    ),
    list(
      indices = matrix(c(1L, 2L, 3L, 2L), nrow = 2L, byrow = TRUE),
      distances = matrix(c(0, 1, 0, 1), nrow = 2L, byrow = TRUE)
    ),
    k = 2L
  )
  expect_equal(quality$recall_at_k, 0.75)
  expect_true(is.finite(quality$mean_relative_distance_error))
  expect_true(is.finite(quality$rank_correlation))
  expect_true(is.na(env$benchmark_finite_mean(c(Inf, NA_real_, NaN))))
  expect_error(
    env$benchmark_knn_recall(approx, exact, k = 1.5),
    "`k` must be a positive integer"
  )
  expect_error(
    env$benchmark_knn_recall(
      matrix(integer(), nrow = 2L, ncol = 0L),
      matrix(integer(), nrow = 2L, ncol = 0L)
    ),
    "at least one neighbour column"
  )
})

test_that("legacy Benchmark #1 quality evaluation handles short KNN outputs", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark1_nn_speed.R"),
    "if (worker)"
  )
  x <- matrix(seq_len(20), nrow = 5)
  obj <- list(
    indices = matrix(c(2L, 1L, 4L, 5L, 3L), ncol = 1),
    distances = matrix(rep(1, 5), ncol = 1)
  )

  out <- env$evaluate_knn_quality(x, obj, k = 3L, metric = "euclidean", exact = FALSE)

  expect_equal(out$quality_status, "success")
  expect_equal(out$quality_eval_n, nrow(x))
  expect_true(is.finite(out$recall_at_k))
})

test_that("k-means benchmark defaults cover fast_kmeans stats and public backends", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )

  expect_equal(
    env$default_kmeans_method_values(),
    c("fast_kmeans", "stats")
  )
  expect_equal(
    env$default_kmeans_backend_values(),
    c("auto", "cpu", "cuda")
  )
  expect_equal(env$default_kmeans_cycles(), 10L)
  expect_equal(
    env$valid_kmeans_tuning_values(),
    c("auto", "fixed", "off", "none")
  )
})

test_that("k-means benchmark records runtime capability preflight", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  caps <- env$kmeans_runtime_capabilities()

  expect_s3_class(caps, "data.frame")
  expect_true(all(c(
    "method", "backend", "runtime_available", "resolved_backend",
    "runtime_reason", "runtime_notes", "cuda_available",
    "faiss_gpu_available", "cuvs_available"
  ) %in% names(caps)))
  expect_equal(caps$backend, c("auto", "cpu", "cuda", "stats"))

  cuda <- env$kmeans_runtime_status("fast_kmeans", "cuda", caps)
  expect_equal(cuda$resolved_backend, "cuda")
  expect_equal(
    cuda$runtime_reason,
    env$kmeans_cuda_runtime_reason(
      cuda_available_value = faissR::cuda_available(),
      faiss_gpu_available_value = env$kmeans_faiss_gpu_available(),
      cuvs_available_value = faissR::cuvs_available()
    )
  )
  expect_equal(
    cuda$runtime_available,
    isTRUE(faissR::cuda_available()) &&
      (isTRUE(faissR::faiss_gpu_available()) || isTRUE(faissR::cuvs_available()))
  )

  skip_reason <- env$kmeans_expected_skip("fast_kmeans", "cuda")
  if (isTRUE(cuda$runtime_available)) {
    expect_null(skip_reason)
  } else {
    expect_match(skip_reason, "CUDA k-means")
  }

  expect_equal(
    env$kmeans_cuda_runtime_reason(
      cuda_available_value = FALSE,
      faiss_gpu_available_value = TRUE,
      cuvs_available_value = TRUE
    ),
    "missing_cuda_runtime"
  )
  expect_match(
    env$kmeans_cuda_runtime_notes("missing_cuda_runtime"),
    "CUDA runtime"
  )
  expect_equal(
    env$kmeans_cuda_runtime_reason(
      cuda_available_value = TRUE,
      faiss_gpu_available_value = FALSE,
      cuvs_available_value = FALSE
    ),
    "missing_gpu_kmeans_backend"
  )
  expect_match(
    env$kmeans_cuda_runtime_notes("missing_gpu_kmeans_backend"),
    "FAISS GPU k-means|cuVS k-means"
  )
})

test_that("k-means benchmark validates method and backend selectors", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )

  expect_equal(
    env$validate_choice_values(
      c("fast_kmeans", "stats", "fast_kmeans"),
      env$default_kmeans_method_values(),
      "methods"
    ),
    c("fast_kmeans", "stats")
  )
  expect_equal(
    env$validate_choice_values(
      c("auto", "cpu", "cuda"),
      env$default_kmeans_backend_values(),
      "backends"
    ),
    c("auto", "cpu", "cuda")
  )
  expect_error(
    env$validate_choice_values(c("fast_kmeans", "kmeanspp"), env$default_kmeans_method_values(), "methods"),
    "Invalid value\\(s\\): kmeanspp"
  )
  expect_error(
    env$validate_choice_values(c("gpu"), env$default_kmeans_backend_values(), "backends"),
    "Invalid value\\(s\\): gpu"
  )
  expect_error(
    env$validate_choice_values(character(), env$default_kmeans_backend_values(), "backends"),
    "at least one value"
  )
  expect_equal(env$validate_kmeans_tuning_value(" auto "), "auto")
  expect_equal(env$validate_kmeans_tuning_value("FIXED"), "fixed")
  expect_equal(env$validate_kmeans_tuning_value("off"), "off")
  expect_equal(env$validate_kmeans_tuning_value("none"), "none")
  expect_error(
    env$validate_kmeans_tuning_value("pilot"),
    "Invalid value: pilot"
  )
  expect_error(
    env$validate_kmeans_tuning_value(""),
    "must be one of"
  )
})

test_that("k-means benchmark validates dataset selectors", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  valid <- c("COIL20", "USPS", "SimulatedTiny3Clusters")

  expect_equal(
    env$validate_dataset_values(c("COIL20", "USPS", "COIL20"), valid),
    c("COIL20", "USPS")
  )
  expect_error(
    env$validate_dataset_values(c("COIL20", "bad_dataset"), valid),
    "Invalid value\\(s\\): bad_dataset"
  )
  expect_error(
    env$validate_dataset_values(character(), valid),
    "at least one dataset"
  )
})

test_that("k-means benchmark centers argument is explicit", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )

  expect_equal(env$required_positive_int_arg(10L, "centers"), 10L)
  expect_equal(env$required_positive_int_arg("3", "centers"), 3L)
  expect_error(env$required_positive_int_arg("auto", "centers"), "positive integer")
  expect_error(env$required_positive_int_arg(0L, "centers"), "positive integer")
  expect_equal(env$required_positive_int_arg("12", "threads"), 12L)
  expect_equal(env$required_positive_int_arg("600", "timeout"), 600L)
  expect_equal(env$required_positive_int_arg("10", "cycles"), 10L)
  expect_error(env$required_positive_int_arg("many", "cycles"), "positive integer")
  expect_error(env$required_positive_int_arg("1.5", "cycles"), "positive integer")
  expect_equal(env$required_positive_int_arg("42", "seed"), 42L)
  expect_error(env$required_positive_int_arg("many", "seed"), "positive integer")
  expect_error(env$required_positive_int_arg(0, "seed"), "positive integer")
  expect_equal(env$required_nonnegative_numeric_arg("0.01", "ari_tolerance"), 0.01)
  expect_equal(env$required_nonnegative_numeric_arg(0, "ari_tolerance"), 0)
  expect_error(
    env$required_nonnegative_numeric_arg("auto", "ari_tolerance"),
    "non-negative numeric"
  )
  expect_error(
    env$required_nonnegative_numeric_arg(-0.1, "ari_tolerance"),
    "non-negative numeric"
  )
  expect_equal(env$resolve_kmeans_int("auto", 25L), 25L)
  expect_equal(env$resolve_kmeans_int("25", 100L), 25L)
  expect_error(env$resolve_kmeans_int("25.5", 100L), "positive integers or `auto`")
  expect_error(env$resolve_kmeans_int("many", 100L), "positive integers or `auto`")
  expect_equal(env$resolve_kmeans_tol("auto", 1e-4), 1e-4)
  expect_equal(env$resolve_kmeans_tol("0.001", 1e-4), 0.001)
  expect_error(env$resolve_kmeans_tol("many", 1e-4), "non-negative numeric")
  expect_error(env$resolve_kmeans_tol("-0.1", 1e-4), "non-negative numeric")
  expect_true(env$kmeans_hit_max_iter(25L, 25L))
  expect_false(env$kmeans_hit_max_iter(24L, 25L))
  expect_true(is.na(env$kmeans_hit_max_iter(NA_integer_, 25L)))
})

test_that("k-means benchmark mirrors fast_kmeans auto CUDA shape gate", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )

  expect_false(env$kmeans_auto_prefers_cuda(n = 120L, p = 4L, centers = 3L))
  expect_true(env$kmeans_auto_prefers_cuda(n = 70000L, p = 784L, centers = 10L))
  expect_true(env$kmeans_auto_prefers_cuda(n = 500000L, p = 32L, centers = 10L))
  expect_true(env$kmeans_auto_prefers_cuda(n = NULL, p = NULL, centers = NULL))
  expect_false(env$kmeans_auto_prefers_cuda(n = 1000000L, p = 784L, centers = 1L))

  small_policy <- env$kmeans_auto_backend_policy(n = 120L, p = 4L, centers = 3L)
  expect_false(small_policy$prefer_cuda)
  expect_equal(small_policy$reason, "small_cpu_preferred")
  expect_equal(small_policy$work_threshold, 1e8)
  expect_equal(small_policy$nbytes, 3840)
  expect_equal(small_policy$gpu_transfer_nbytes, 1920)
  expect_equal(small_policy$nbytes_threshold, 256 * 1024^2)
  expect_equal(small_policy$large_n_threshold, 50000)
  expect_equal(small_policy$large_p_threshold, 128)
  expect_equal(small_policy$min_n_per_center, 20)

  work_policy <- env$kmeans_auto_backend_policy(n = 70000L, p = 784L, centers = 10L)
  expect_true(work_policy$prefer_cuda)
  expect_equal(work_policy$reason, "work_at_least_1e8")
  expect_true(work_policy$work >= work_policy$work_threshold)

  one_cluster <- env$kmeans_auto_backend_policy(n = 1000000L, p = 784L, centers = 1L)
  expect_false(one_cluster$prefer_cuda)
  expect_equal(one_cluster$reason, "single_cluster_exact_mean")
  expect_equal(one_cluster$n_per_center, 1000000)

  singleton <- env$kmeans_auto_backend_policy(n = 120L, p = 4L, centers = 120L)
  expect_false(singleton$prefer_cuda)
  expect_equal(singleton$reason, "singleton_exact_identity")
  expect_equal(singleton$n_per_center, 1)

  few_points <- env$kmeans_auto_backend_policy(n = 5000L, p = 512L, centers = 1000L)
  expect_false(few_points$prefer_cuda)
  expect_equal(few_points$reason, "few_points_per_center_cpu_preferred")
  expect_equal(few_points$n_per_center, 5)

  explicit_cuda <- env$kmeans_selection_metadata(
    backend = "cuda",
    n = 70000L,
    p = 784L,
    centers = 10L
  )
  expect_equal(explicit_cuda$resolved_backend, "cuda")
  expect_equal(explicit_cuda$backend_decision, "explicit_cuda")
  expect_equal(explicit_cuda$runtime_decision, "explicit_backend_no_auto_fallback")
  expect_equal(explicit_cuda$tuning_source, "cpp")
})

test_that("k-means benchmark fallback auto params mirror package metadata", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  env$getFromNamespace <- function(...) stop("simulate unavailable package helper")

  shapes <- list(
    list(n = 70000L, p = 784L, centers = 1L, tuning = "auto"),
    list(n = 120L, p = 4L, centers = 120L, tuning = "auto"),
    list(n = 70000L, p = 784L, centers = 10L, tuning = " Auto "),
    list(n = 50000L, p = 10L, centers = 100L, tuning = "auto"),
    list(n = 1000L, p = 10L, centers = 100L, tuning = "auto"),
    list(n = 200000L, p = 50L, centers = 100L, tuning = "FIXED"),
    list(n = 200000L, p = 50L, centers = 100L, tuning = "none")
  )
  for (shape in shapes) {
    fallback <- do.call(env$kmeans_auto_params, shape)
    expected <- do.call(faissR:::kmeans_auto_params, shape)
    expect_equal(fallback[names(expected)], expected, info = paste(shape, collapse = ","))
  }

  tiny_selection <- env$kmeans_selection_metadata(
    backend = "auto",
    n = 120L,
    p = 4L,
    centers = 3L
  )
  expect_equal(tiny_selection$resolved_backend, "cpu")
  expect_equal(tiny_selection$runtime_decision, "cpu_preferred_by_shape")
  expect_equal(tiny_selection$tuning_source, "cpp")
})

test_that("k-means benchmark records static selection metadata", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  row <- env$result_row(
    dataset = "A",
    n = 100L,
    p = 4L,
    method = "fast_kmeans",
    backend = "auto",
    centers = 3L,
    cycle = 1L,
    n_threads = 2L,
    status = "success",
    elapsed_sec = 1,
    backend_used = "faiss",
    requested_backend = "auto",
    resolved_backend = "cpu",
    iter = 5L,
    tot_withinss = 10,
    ari = 0.9,
    max_iter = 100L,
    converged = TRUE,
    hit_max_iter = FALSE,
    n_init = 5L,
    tol = 1e-4,
    tuning_policy = "auto",
    tuning_rule = "small_low_work_multistart",
    tuning_rule_detail = "n=100;p=4;centers=3;n_per_center=33.33;work=1.2e+03",
    tuning_work = 1200,
    tuning_n_per_center = 33.3,
    tuning_few_points_many_centers = FALSE,
    selection_policy = "static_shape_center_backend_selector",
    selection_slow_tuning = FALSE,
    selection_predicted_backend = "cpu",
    selection_reason = "small_cpu_preferred",
    selection_explicit_backend = TRUE,
    selection_backend_decision = "explicit_cpu",
    selection_work = 1200,
    selection_nbytes = 3200,
    selection_gpu_transfer_nbytes = 1600,
    selection_n_per_center = 33.3,
    selection_cuda_available = FALSE,
    selection_faiss_gpu_available = FALSE,
    selection_cuvs_available = FALSE,
    selection_cuda_kmeans_route_available = FALSE,
    selection_runtime_decision = "explicit_backend_no_auto_fallback",
    selection_tuning_source = "cpp",
    cuda_provider_selection = "direct_cuvs_after_faiss_gpu_unavailable_or_failed",
    faiss_gpu_error = "FAISS GPU k-means unavailable",
    backend_resolution_note = "CUDA k-means used direct cuVS after FAISS GPU failed."
  )
  expect_equal(row$selection_policy, "static_shape_center_backend_selector")
  expect_false(row$selection_slow_tuning)
  expect_equal(row$selection_predicted_backend, "cpu")
  expect_equal(row$selection_reason, "small_cpu_preferred")
  expect_true(row$selection_explicit_backend)
  expect_equal(row$selection_backend_decision, "explicit_cpu")
  expect_false(row$selection_cuda_kmeans_route_available)
  expect_equal(row$selection_runtime_decision, "explicit_backend_no_auto_fallback")
  expect_equal(row$selection_tuning_source, "cpp")
  expect_equal(row$cuda_provider_selection, "direct_cuvs_after_faiss_gpu_unavailable_or_failed")
  expect_equal(row$faiss_gpu_error, "FAISS GPU k-means unavailable")
  expect_equal(row$backend_resolution_note, "CUDA k-means used direct cuVS after FAISS GPU failed.")
  expect_true(row$converged)
  expect_false(row$hit_max_iter)

  summary <- env$summarize_kmeans_cycles(row)
  expect_equal(summary$tuning_rule, "small_low_work_multistart")
  expect_equal(summary$tuning_rule_detail, "n=100;p=4;centers=3;n_per_center=33.33;work=1.2e+03")
  expect_false(summary$tuning_few_points_many_centers)
  expect_equal(summary$selection_policy, "static_shape_center_backend_selector")
  expect_false(summary$selection_slow_tuning)
  expect_equal(summary$selection_predicted_backend, "cpu")
  expect_equal(summary$selection_reason, "small_cpu_preferred")
  expect_true(summary$selection_explicit_backend)
  expect_equal(summary$selection_backend_decision, "explicit_cpu")
  expect_equal(summary$median_selection_work, 1200)
  expect_equal(summary$median_selection_nbytes, 3200)
  expect_equal(summary$median_selection_gpu_transfer_nbytes, 1600)
  expect_equal(summary$median_selection_n_per_center, 33.3)
  expect_false(summary$selection_cuda_kmeans_route_available)
  expect_equal(summary$selection_runtime_decision, "explicit_backend_no_auto_fallback")
  expect_equal(summary$selection_tuning_source, "cpp")
  expect_equal(summary$cuda_provider_selection, "direct_cuvs_after_faiss_gpu_unavailable_or_failed")
  expect_equal(summary$faiss_gpu_error, "FAISS GPU k-means unavailable")
  expect_equal(summary$backend_resolution_note, "CUDA k-means used direct cuVS after FAISS GPU failed.")
  expect_false(summary$any_hit_max_iter)
  expect_true(summary$all_converged)
})

test_that("k-means benchmark recommendations are grouped by dataset and centers", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A", "A", "B", "B"),
    centers = c(2L, 2L, 3L, 3L, 2L, 2L),
    method = c("m1", "m2", "m1", "m2", "m1", "m2"),
    backend = c("cpu", "cpu", "cpu", "cpu", "cpu", "cpu"),
    metric = c("euclidean", "euclidean", "euclidean", "euclidean", "euclidean", "euclidean"),
    median_ari = c(0.90, 0.89, 0.70, 0.69, NA, NA),
    median_elapsed_sec = c(2, 1, 5, 3, 4, 2)
  )

  out <- env$recommend_kmeans_methods(cycle_summary, ari_tolerance = 0.02)
  expect_equal(nrow(out), 3L)
  expect_equal(out$dataset, c("A", "A", "B"))
  expect_equal(as.integer(out$centers), c(2L, 3L, 2L))
  expect_equal(out$method, c("m2", "m2", "m2"))
  expect_equal(
    out$recommendation_basis,
    c("fastest_within_ari_tolerance", "fastest_within_ari_tolerance", "speed_only_no_ari")
  )
})

test_that("k-means benchmark can recommend within backend groups", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A", "A"),
    centers = c(2L, 2L, 2L, 2L),
    method = c("fast_kmeans", "fast_kmeans", "stats", "stats"),
    backend = c("cpu", "cuda", "stats", "stats"),
    metric = rep("euclidean", 4L),
    median_ari = c(0.91, 0.90, 0.92, 0.89),
    median_elapsed_sec = c(3, 1, 5, 4),
    median_tot_withinss = c(10, 11, 9, 12)
  )

  overall <- env$recommend_kmeans_methods(cycle_summary, ari_tolerance = 0.02)
  by_backend <- env$recommend_kmeans_methods(
    cycle_summary,
    ari_tolerance = 0.02,
    group_cols = c("dataset", "centers", "backend")
  )

  expect_equal(nrow(overall), 1L)
  expect_equal(overall$backend, "cuda")
  expect_equal(nrow(by_backend), 3L)
  expect_equal(by_backend$backend, c("cpu", "cuda", "stats"))
  expect_equal(by_backend$method, c("fast_kmeans", "fast_kmeans", "stats"))
})

test_that("k-means benchmark recommendation ties prefer ARI stability then lower withinss", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "B", "B", "C", "C"),
    centers = c(2L, 2L, 2L, 2L, 2L, 2L),
    method = c(
      "lower_ari", "higher_ari",
      "lower_min_ari", "higher_min_ari",
      "higher_withinss", "lower_withinss"
    ),
    backend = rep("cpu", 6L),
    metric = rep("euclidean", 6L),
    median_ari = c(0.89, 0.90, 0.90, 0.90, 0.90, 0.90),
    min_ari = c(0.88, 0.88, 0.80, 0.85, 0.85, 0.85),
    median_elapsed_sec = c(1, 1, 1, 1, 1, 1),
    median_tot_withinss = c(10, 12, 10, 12, 20, 15)
  )

  out <- env$recommend_kmeans_methods(cycle_summary, ari_tolerance = 0.02)
  expect_equal(out$method, c("higher_ari", "higher_min_ari", "lower_withinss"))
})

test_that("k-means benchmark best-row ranking uses withinss after quality and speed", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A", "A", "B", "B"),
    method = c(
      "fast_high_withinss", "fast_low_withinss", "lower_ari",
      "fast_missing_quality", "slow_missing_quality"
    ),
    ari = c(0.95, 0.95, 0.94, NA, NA),
    elapsed_sec = c(1, 1, 0.5, 1, 2),
    tot_withinss = c(20, 10, 1, NA, NA),
    stringsAsFactors = FALSE
  )

  ranked <- env$rank_kmeans_success(ok)
  best <- ranked[!duplicated(ranked$dataset), , drop = FALSE]
  expect_equal(best$method, c("fast_low_withinss", "fast_missing_quality"))
})

test_that("k-means benchmark best rows can preserve centers dimension", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A", "A", "B"),
    centers = c(2L, 2L, 3L, 2L),
    method = c("fast_low_ari", "slow_high_ari", "centers3", "b_best"),
    ari = c(0.80, 0.90, 0.70, 0.95),
    elapsed_sec = c(1, 2, 1, 1),
    tot_withinss = c(20, 10, 5, 1),
    stringsAsFactors = FALSE
  )

  compact <- env$select_kmeans_best_rows(ok, group_cols = "dataset")
  by_centers <- env$select_kmeans_best_rows(ok, group_cols = c("dataset", "centers"))

  expect_equal(compact$method, c("slow_high_ari", "b_best"))
  expect_setequal(by_centers$method, c("slow_high_ari", "centers3", "b_best"))
  expect_equal(
    nrow(unique(by_centers[, c("dataset", "centers"), drop = FALSE])),
    3L
  )
})

test_that("k-means fast comparison is ordered by dataset centers and backend", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A", "A", "A", "A"),
    method = c("fast_kmeans", "fast_kmeans", "fast_kmeans", "fast_kmeans", "stats", "stats"),
    backend = c("cuda", "cpu", "cuda", "cpu", "stats", "stats"),
    backend_used = c("cuda_faiss", "faiss", "cuda_faiss", "faiss", "stats", "stats"),
    requested_backend = c("cuda", "cpu", "cuda", "cpu", "stats", "stats"),
    resolved_backend = c("cuda", "cpu", "cuda", "cpu", "stats", "stats"),
    n_threads = c(2L, 2L, 2L, 2L, 2L, 2L),
    centers = c(3L, 3L, 5L, 5L, 3L, 5L),
    success_cycles = c(1L, 1L, 1L, 1L, 1L, 1L),
    median_elapsed_sec = c(3, 4, 5, 6, 7, 8),
    median_ari = c(0.9, 0.91, 0.8, 0.81, 0.89, 0.79),
    min_ari = c(0.9, 0.91, 0.8, 0.81, 0.89, 0.79),
    median_tot_withinss = c(10, 11, 20, 21, 12, 22),
    median_iter = c(5, 5, 5, 5, 5, 5),
    median_max_iter = c(100, 100, 100, 100, 100, 100),
    median_n_init = c(3, 3, 3, 3, 1, 1),
    median_tol = c(1e-4, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4),
    tuning_policy = c("auto", "auto", "auto", "auto", "stats", "stats"),
    tuning_rule = c("medium", "medium", "medium", "medium", "stats_kmeans", "stats_kmeans"),
    tuning_rule_detail = c("fast3", "fast3", "fast5", "fast5", "stats3", "stats5"),
    median_tuning_work = c(300, 300, 500, 500, NA, NA),
    median_tuning_n_per_center = c(10, 10, 10, 10, NA, NA),
    tuning_high_dim = c(FALSE, FALSE, FALSE, FALSE, NA, NA),
    tuning_large_n = c(FALSE, FALSE, FALSE, FALSE, NA, NA),
    tuning_many_centers = c(FALSE, FALSE, FALSE, FALSE, NA, NA),
    tuning_small_many_centers = c(FALSE, FALSE, FALSE, FALSE, NA, NA),
    tuning_few_points_many_centers = c(FALSE, TRUE, FALSE, FALSE, NA, NA),
    selection_policy = c(
      rep("static_shape_center_backend_selector", 4),
      rep("stats", 2)
    ),
    selection_slow_tuning = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    selection_predicted_backend = c("cuda", "cpu", "cuda", "cpu", "stats", "stats"),
    selection_reason = c("work_at_least_1e8", "small_cpu_preferred", "work_at_least_1e8", "small_cpu_preferred", "stats_kmeans", "stats_kmeans"),
    selection_explicit_backend = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
    selection_backend_decision = c("explicit_cuda", "explicit_cpu", "explicit_cuda", "explicit_cpu", "stats_kmeans", "stats_kmeans"),
    median_selection_work = c(300, 300, 500, 500, NA, NA),
    median_selection_nbytes = c(2400, 2400, 4000, 4000, NA, NA),
    median_selection_gpu_transfer_nbytes = c(1200, 1200, 2000, 2000, NA, NA),
    median_selection_n_per_center = c(10, 10, 10, 10, NA, NA),
    selection_cuda_available = c(TRUE, TRUE, TRUE, TRUE, NA, NA),
    selection_faiss_gpu_available = c(TRUE, TRUE, TRUE, TRUE, NA, NA),
    selection_cuvs_available = c(FALSE, FALSE, FALSE, FALSE, NA, NA)
  )
  recommendations <- cycle_summary[cycle_summary$method == "stats", , drop = FALSE]
  recommendations$recommendation_basis <- "fastest_within_ari_tolerance"

  out <- env$compare_fast_kmeans_to_recommendations(cycle_summary, recommendations)
  expect_equal(anyDuplicated(names(out)), 0L)
  expect_equal(as.integer(out$centers), c(3L, 3L, 5L, 5L))
  expect_equal(out$fast_backend, c("cpu", "cuda", "cpu", "cuda"))
  expect_equal(out$fast_requested_backend, c("cpu", "cuda", "cpu", "cuda"))
  expect_equal(out$recommended_requested_backend, c("stats", "stats", "stats", "stats"))
  expect_equal(out$fast_n_threads, c(2L, 2L, 2L, 2L))
  expect_equal(out$recommended_n_threads, c(2L, 2L, 2L, 2L))
  expect_equal(out$fast_tuning_rule, rep("medium", 4))
  expect_equal(out$recommended_tuning_rule, rep("stats_kmeans", 4))
  expect_equal(out$fast_tuning_rule_detail, c("fast3", "fast3", "fast5", "fast5"))
  expect_equal(out$recommended_tuning_rule_detail, c("stats3", "stats3", "stats5", "stats5"))
  expect_equal(out$fast_tuning_few_points_many_centers, c(TRUE, FALSE, FALSE, FALSE))
  expect_true(all(is.na(out$recommended_tuning_few_points_many_centers)))
  expect_equal(out$fast_selection_policy, rep("static_shape_center_backend_selector", 4))
  expect_equal(out$recommended_selection_policy, rep("stats", 4))
  expect_equal(out$fast_selection_predicted_backend, c("cpu", "cuda", "cpu", "cuda"))
  expect_equal(out$fast_selection_backend_decision, c("explicit_cpu", "explicit_cuda", "explicit_cpu", "explicit_cuda"))
  expect_true(all(out$fast_selection_explicit_backend))
  expect_equal(unique(out$recommended_recommendation_basis), "fastest_within_ari_tolerance")
})

test_that("k-means auto comparison audits global recommendation", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "A"),
    method = c("fast_kmeans", "fast_kmeans", "stats"),
    backend = c("auto", "cuda", "stats"),
    backend_used = c("faiss", "cuda_faiss", "stats"),
    requested_backend = c("auto", "cuda", "stats"),
    resolved_backend = c("cpu", "cuda", "stats"),
    n_threads = c(2L, 2L, 2L),
    centers = c(3L, 3L, 3L),
    success_cycles = c(2L, 2L, 2L),
    median_elapsed_sec = c(4, 2, 6),
    median_ari = c(0.90, 0.90, 0.89),
    min_ari = c(0.89, 0.89, 0.88),
    median_tot_withinss = c(10, 10, 11),
    median_iter = c(5, 5, 5),
    median_max_iter = c(100, 100, 100),
    any_hit_max_iter = c(FALSE, FALSE, FALSE),
    all_converged = c(TRUE, TRUE, TRUE),
    median_n_init = c(3, 3, 1),
    median_tol = c(1e-4, 1e-4, 1e-4),
    tuning_policy = c("auto", "auto", "stats"),
    tuning_rule = c("medium", "medium", "stats_kmeans"),
    tuning_rule_detail = c("auto_cpu", "cuda_fast", "stats"),
    median_tuning_work = c(300, 300, NA),
    median_tuning_n_per_center = c(10, 10, NA),
    tuning_high_dim = c(FALSE, FALSE, NA),
    tuning_large_n = c(FALSE, FALSE, NA),
    tuning_many_centers = c(FALSE, FALSE, NA),
    tuning_small_many_centers = c(FALSE, FALSE, NA),
    tuning_few_points_many_centers = c(FALSE, FALSE, NA),
    selection_policy = c("static_shape_center_backend_selector", "explicit_backend", "stats"),
    selection_slow_tuning = c(FALSE, FALSE, FALSE),
    selection_predicted_backend = c("cpu", NA_character_, "stats"),
    selection_reason = c("small_cpu_preferred", "explicit_cuda", "stats_kmeans"),
    selection_explicit_backend = c(FALSE, TRUE, TRUE),
    selection_backend_decision = c("small_cpu_preferred", "explicit_cuda", "stats_kmeans"),
    median_selection_work = c(300, 300, NA),
    median_selection_nbytes = c(2400, 2400, NA),
    median_selection_gpu_transfer_nbytes = c(1200, 1200, NA),
    median_selection_n_per_center = c(10, 10, NA),
    selection_cuda_available = c(TRUE, TRUE, NA),
    selection_faiss_gpu_available = c(TRUE, TRUE, NA),
    selection_cuvs_available = c(FALSE, FALSE, NA)
  )
  recommendations <- cycle_summary[2, , drop = FALSE]
  recommendations$recommendation_basis <- "fastest_within_ari_tolerance"

  out <- env$compare_auto_kmeans_to_recommendations(cycle_summary, recommendations)
  expect_equal(anyDuplicated(names(out)), 0L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$recommended_backend, "cuda")
  expect_false(out$auto_uses_recommended_requested_backend)
  expect_false(out$auto_uses_recommended_resolved_backend)
  expect_false(out$auto_uses_recommended_implementation)
  expect_equal(out$auto_median_speed_ratio, 2)
  expect_equal(out$auto_median_ari_gap, 0)
  expect_equal(out$auto_selection_predicted_backend, "cpu")
  expect_false(out$auto_selection_explicit_backend)
  expect_equal(out$recommended_selection_backend_decision, "explicit_cuda")
  expect_equal(out$recommended_selection_reason, "explicit_cuda")
})

test_that("k-means fast comparison guards withinss ratios", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "B", "B"),
    method = c("fast_kmeans", "stats", "fast_kmeans", "stats"),
    backend = c("cpu", "stats", "cpu", "stats"),
    backend_used = c("faiss", "stats", "faiss", "stats"),
    requested_backend = c("cpu", "stats", "cpu", "stats"),
    resolved_backend = c("cpu", "stats", "cpu", "stats"),
    n_threads = c(2L, 2L, 2L, 2L),
    centers = c(3L, 3L, 3L, 3L),
    success_cycles = c(1L, 1L, 1L, 1L),
    median_elapsed_sec = c(1, 1, 1, 1),
    median_ari = c(0.9, 0.9, 0.9, 0.9),
    min_ari = c(0.9, 0.9, 0.9, 0.9),
    median_tot_withinss = c(10, 0, 10, NA),
    median_iter = c(5, 5, 5, 5),
    median_max_iter = c(100, 100, 100, 100),
    median_n_init = c(1, 1, 1, 1),
    median_tol = c(1e-4, 1e-4, 1e-4, 1e-4),
    tuning_policy = c("auto", "stats", "auto", "stats")
  )
  recommendations <- cycle_summary[cycle_summary$method == "stats", , drop = FALSE]
  recommendations$recommendation_basis <- "fastest_within_ari_tolerance"

  out <- env$compare_fast_kmeans_to_recommendations(cycle_summary, recommendations)
  expect_true(all(is.na(out$fast_withinss_ratio)))
  expect_true(all(is.finite(out$fast_median_speed_ratio)))
})

test_that("k-means fast comparison guards speed ratios and ARI gaps", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  cycle_summary <- data.frame(
    dataset = c("A", "A", "B", "B"),
    method = c("fast_kmeans", "stats", "fast_kmeans", "stats"),
    backend = c("cpu", "stats", "cpu", "stats"),
    backend_used = c("faiss", "stats", "faiss", "stats"),
    requested_backend = c("cpu", "stats", "cpu", "stats"),
    resolved_backend = c("cpu", "stats", "cpu", "stats"),
    n_threads = c(2L, 2L, 2L, 2L),
    centers = c(3L, 3L, 3L, 3L),
    success_cycles = c(1L, 1L, 1L, 1L),
    median_elapsed_sec = c(1, 0, 1, 1),
    median_ari = c(0.9, 0.9, NA, 0.9),
    min_ari = c(0.9, 0.9, NA, 0.9),
    median_tot_withinss = c(10, 10, 10, 10),
    median_iter = c(5, 5, 5, 5),
    median_max_iter = c(100, 100, 100, 100),
    median_n_init = c(1, 1, 1, 1),
    median_tol = c(1e-4, 1e-4, 1e-4, 1e-4),
    tuning_policy = c("auto", "stats", "auto", "stats")
  )
  recommendations <- cycle_summary[cycle_summary$method == "stats", , drop = FALSE]
  recommendations$recommendation_basis <- "fastest_within_ari_tolerance"

  out <- env$compare_fast_kmeans_to_recommendations(cycle_summary, recommendations)
  expect_true(is.na(out$fast_median_speed_ratio[out$dataset == "A"]))
  expect_true(is.na(out$fast_median_ari_gap[out$dataset == "B"]))
  expect_true(is.finite(out$fast_median_speed_ratio[out$dataset == "B"]))
})

test_that("k-means fast-vs-stats comparison guards derived metrics", {
  env <- source_benchmark_helpers(
    test_path("../../benchmark_scripts/benchmark_kmeans.R"),
    "args <- parse_args()"
  )
  ok <- data.frame(
    dataset = c("A", "A", "B", "B"),
    method = c("fast_kmeans", "stats", "fast_kmeans", "stats"),
    backend = c("cpu", "stats", "cuda", "stats"),
    backend_used = c("faiss", "stats", "cuda", "stats"),
    resolved_backend = c("cpu", "stats", "cuda", "stats"),
    centers = c(3L, 3L, 4L, 4L),
    cycle = c(1L, 1L, 1L, 1L),
    elapsed_sec = c(0, 1, 2, 4),
    tot_withinss = c(10, 0, 10, 20),
    ari = c(0.9, 0.9, NA, 0.8),
    iter = c(5L, 5L, 5L, 5L),
    status = "success"
  )

  out <- env$compare_fast_kmeans_to_stats(ok)

  expect_true(is.na(out$speedup_vs_stats[out$dataset == "A"]))
  expect_true(is.na(out$withinss_ratio_vs_stats[out$dataset == "A"]))
  expect_true(is.na(out$ari_delta_vs_stats[out$dataset == "B"]))
  expect_equal(out$speedup_vs_stats[out$dataset == "B"], 2)
  expect_equal(out$withinss_ratio_vs_stats[out$dataset == "B"], 0.5)
})

test_that("publication aggregator requires complete held-out recall", {
  path <- test_path(
    "../../benchmark_scripts/jss_reproduction/analysis/aggregate_publication_results.R"
  )
  if (!file.exists(path)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }
  old <- Sys.getenv("FAISSR_JSS_AGGREGATE_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("FAISSR_JSS_AGGREGATE_SOURCE_ONLY") else
      Sys.setenv(FAISSR_JSS_AGGREGATE_SOURCE_ONLY = old)
  }, add = TRUE)
  Sys.setenv(FAISSR_JSS_AGGREGATE_SOURCE_ONLY = "true")
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)

  rows <- expand.grid(validation_seed = c(20260706, 20260807), repeat_id = 1:3)
  rows$dataset <- "MNIST"
  rows$dataset_suite <- "real"
  rows$backend <- "cpu"
  rows$metric <- "euclidean"
  rows$k <- 30L
  rows$target_recall <- 0.99
  rows$implementation <- "faissR"
  rows$method_id <- "faissR_cpu_hnsw"
  rows$public_method <- "hnsw"
  rows$kind <- "knn_search"
  rows$n_threads <- 12L
  rows$status <- "success"
  rows$time_sec <- seq_len(nrow(rows))
  rows$peak_rss_gb <- 1
  rows$host_copy_sec <- 0
  rows$recall_at_k <- c(rep(0.995, 5), 0.98)

  summary <- env$robust_summary(rows, expected_seeds = 2L, expected_repeats = 3L)
  expect_true(summary$complete_validation)
  expect_false(summary$target_met_all_runs)
  expect_equal(summary$min_recall_at_k, 0.98)
  expect_equal(summary$target_recall_statistic, "mean_query_recall_at_k")
  expect_equal(
    summary$target_recall_replicate_rule,
    "all_prespecified_validation_replicates"
  )
  expect_equal(summary$min_query_recall_role, "diagnostic_only")
  expect_false(summary$target_attained_all_validation_replicates)
  expect_equal(summary$n_valid_host_memory_measurements, 0L)
  expect_true(is.na(summary$median_peak_rss_gb))

  isolated_rows <- rows
  isolated_rows$memory_process_isolated <- TRUE
  isolated_rows$memory_valid_for_comparison <- TRUE
  isolated_summary <- env$robust_summary(
    isolated_rows, expected_seeds = 2L, expected_repeats = 3L
  )
  expect_equal(isolated_summary$n_valid_host_memory_measurements, 6L)
  expect_equal(isolated_summary$median_peak_rss_gb, 1)

  rows$recall_at_k <- 0.995
  summary <- env$robust_summary(rows, expected_seeds = 2L, expected_repeats = 3L)
  expect_true(summary$target_met_all_runs)
  expect_true(summary$target_attained_all_validation_replicates)

  exact_rows <- rows
  exact_rows$method_id <- "faissR_cpu_flat"
  exact_rows$public_method <- "flat"
  exact_rows$recall_at_k <- 0.98
  exact_summary <- env$robust_summary(
    exact_rows, expected_seeds = 2L, expected_repeats = 3L
  )
  expect_false(exact_summary$set_overlap_target_met_all_runs)
  expect_true(exact_summary$exact_audited)
  expect_true(is.na(exact_summary$approximate_target_met))
  expect_true(exact_summary$selection_eligible)
  expect_identical(exact_summary$quality_class, "exact-audited")

  missing_repeat <- rows[
    !(rows$validation_seed == 20260807 & rows$repeat_id == 3L),
    ,
    drop = FALSE
  ]
  duplicated_repeat <- rbind(missing_repeat, missing_repeat[1L, , drop = FALSE])
  expect_false(env$robust_summary(
    missing_repeat,
    expected_seeds = 2L,
    expected_repeats = 3L
  )$complete_validation)
  expect_false(env$robust_summary(
    duplicated_repeat,
    expected_seeds = 2L,
    expected_repeats = 3L
  )$complete_validation)

  runs <- data.frame(
    backend = "cpu",
    method_id = "faissR_cpu_hnsw",
    dataset_suite = "real",
    dataset = c("COIL20", "TabulaMuris", "TabulaMuris"),
    dataset_md5 = c("coil-v1", "tabula-v1", "tabula-v2"),
    run_root = c("old", "old", "new"),
    source_mtime = c(1, 1, 2),
    stringsAsFactors = FALSE
  )
  newest <- env$latest_method_runs(runs)
  expect_setequal(newest$dataset, c("COIL20", "TabulaMuris"))
  expect_equal(newest$dataset_md5[newest$dataset == "TabulaMuris"], "tabula-v2")

  result_root <- tempfile("faissR-held-out-reruns-")
  old_dir <- file.path(result_root, "old_run")
  new_dir <- file.path(result_root, "new_run")
  dir.create(old_dir, recursive = TRUE)
  dir.create(new_dir, recursive = TRUE)
  old_file <- file.path(old_dir, "jmlr_tuned_benchmark_results.csv")
  new_file <- file.path(new_dir, "jmlr_tuned_benchmark_results.csv")
  write.csv(runs[2L, setdiff(names(runs), c("run_root", "source_mtime"))],
            old_file, row.names = FALSE)
  write.csv(runs[3L, setdiff(names(runs), c("run_root", "source_mtime"))],
            new_file, row.names = FALSE)
  Sys.setFileTime(old_file, Sys.time() - 60)
  Sys.setFileTime(new_file, Sys.time())
  reread <- env$read_union(c(old_file, new_file))
  expect_setequal(reread$run_root, c(old_dir, new_dir))
  expect_equal(
    env$latest_method_runs(reread)$dataset_md5,
    "tabula-v2"
  )

  selector_rows <- data.frame(
    dataset = "MNIST",
    dataset_md5 = "mnist-v1",
    dataset_suite = "real",
    backend = "cpu",
    metric = "euclidean",
    k = 30L,
    target_recall = 0.99,
    complete_validation = TRUE,
    target_met_all_runs = TRUE,
    median_time_sec = c(0.5, 0.4, 1, 1.5),
    min_recall_at_k = c(0.995, 0.995, 0.995, 0.995),
    implementation = c("FNN", "nabor", "faissR", "faissR"),
    method_id = c(
      "FNN_kd", "nabor_auto", "faissR_cpu_hnsw", "faissR_cpu_auto"
    ),
    public_method = c(NA, NA, "hnsw", "auto"),
    result_backend = c(NA, NA, "faiss_hnsw", "faiss_hnsw"),
    stringsAsFactors = FALSE
  )
  selector <- env$rank_qualifying(selector_rows)
  expect_identical(selector$fastest_method, "nabor_auto")
  expect_identical(selector$faissr_oracle_method, "faissR_cpu_hnsw")
  expect_equal(selector$auto_over_oracle, 1.5)
  expect_true(selector$auto_provider_agreement)

  selector_rows$exact_audited <- c(TRUE, TRUE, FALSE, FALSE)
  selector_rows$approximate_target_met <- c(NA, NA, TRUE, TRUE)
  selector_rows$selection_eligible <- TRUE
  selector_rows$n_timeout <- c(0L, 2L, 0L, 0L)
  selector_rows$n_out_of_memory <- 0L
  external_pairs <- env$pair_auto_with_external(selector_rows)
  expect_equal(nrow(external_pairs), 2L)
  expect_equal(
    external_pairs$paired_ratio[external_pairs$comparator_method == "FNN_kd"],
    0.5 / 1.5
  )
  expect_identical(
    unique(external_pairs$ratio_definition),
    "comparator_time/faissR_auto_time"
  )
  expect_equal(
    external_pairs$comparator_timeouts[
      external_pairs$comparator_method == "nabor_auto"
    ],
    2L
  )

  oracle_pairs <- env$pair_auto_with_oracle(selector)
  expect_equal(oracle_pairs$paired_ratio, 1.5)
  expect_identical(
    oracle_pairs$ratio_definition,
    "faissR_auto_time/faissR_oracle_time"
  )
  all_pairs <- rbind(external_pairs, oracle_pairs)
  by_dataset <- env$summarize_pairs_by_dataset(all_pairs)
  across_datasets <- env$summarize_pairs_across_datasets(by_dataset)
  expect_true(all(c(
    "n_datasets_paired", "n_cells_paired", "n_cells_unpaired",
    "median_dataset_paired_ratio", "q1_dataset_paired_ratio",
    "q3_dataset_paired_ratio", "min_dataset_paired_ratio",
    "max_dataset_paired_ratio", "n_comparator_timeouts"
  ) %in% names(across_datasets)))
  expect_true(all(by_dataset$n_expected_cells == by_dataset$n_paired_cells))
})



test_that("RcppAnnoy angular comparison obeys the cosine-distance contract", {
  skip_if_not_installed("RcppAnnoy")
  path <- test_path(
    "../../benchmark_scripts/jss_reproduction/common/benchmark_jmlr_tuned_methods.R"
  )
  if (!file.exists(path)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }
  old <- Sys.getenv("FAISSR_JMLR_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("FAISSR_JMLR_SOURCE_ONLY") else
      Sys.setenv(FAISSR_JMLR_SOURCE_ONLY = old)
  }, add = TRUE)
  Sys.setenv(FAISSR_JMLR_SOURCE_ONLY = "true")
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)

  set.seed(20260801)
  x <- matrix(rnorm(64L * 7L), nrow = 64L)
  result <- env$run_external_method(
    x, "RcppAnnoy_angular", k = 5L, metric = "cosine",
    threads = 1L, seed = 17L
  )
  expect_equal(dim(result$indices), c(64L, 5L))
  expect_equal(dim(result$distances), c(64L, 5L))
  expect_true(all(is.finite(result$distances)))
  expect_true(all(vapply(seq_len(nrow(x)), function(i) {
    !i %in% result$indices[i, ]
  }, logical(1L))))

  expected <- matrix(NA_real_, nrow(x), 5L)
  norms <- sqrt(rowSums(x^2))
  for (i in seq_len(nrow(x))) {
    ids <- result$indices[i, ]
    expected[i, ] <- 1 - drop(x[ids, , drop = FALSE] %*% x[i, ]) /
      (norms[ids] * norms[[i]])
  }
  expect_equal(result$distances, expected, tolerance = 2e-5)
})



test_that("publication systems-ablation scripts retain backend-specific headers", {
  root <- test_path("../../benchmark_scripts/jss_reproduction")
  if (!dir.exists(root)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }
  cpu <- readLines(file.path(root, "ablations", "run_systems_ablations_cpu12.sh"), warn = FALSE)
  cuda <- readLines(file.path(root, "ablations", "run_systems_ablations_cuda.sh"), warn = FALSE)
  expect_true(any(grepl("^#SBATCH --account=immunology$", cpu)))
  expect_true(any(grepl("^#SBATCH --partition=ada$", cpu)))
  expect_true(any(grepl("^#SBATCH --ntasks=12$", cpu)))
  expect_true(any(grepl("^#SBATCH --account=l40sfree$", cuda)))
  expect_true(any(grepl("^#SBATCH --partition=l40s$", cuda)))
  expect_true(any(grepl("^#SBATCH --gres=gpu:l40s:1$", cuda)))
  expect_true(any(grepl("singularity exec --nv", cuda, fixed = TRUE)))
  expect_true(any(grepl("faissR CPU preflight OK", cpu, fixed = TRUE)))
  expect_true(any(grepl("faissR CUDA preflight OK", cuda, fixed = TRUE)))

  old <- Sys.getenv("FAISSR_JSS_ABLATION_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("FAISSR_JSS_ABLATION_SOURCE_ONLY") else
      Sys.setenv(FAISSR_JSS_ABLATION_SOURCE_ONLY = old)
  }, add = TRUE)
  Sys.setenv(FAISSR_JSS_ABLATION_SOURCE_ONLY = "true")
  env <- new.env(parent = globalenv())
  common_path <- file.path(root, "common", "benchmark_jss_systems_ablations.R")
  common <- readLines(common_path, warn = FALSE)
  expect_true(any(grepl("float::dbl(x)", common, fixed = TRUE)))
  expect_true(any(grepl('file.path(out_dir, "worker_logs")', common, fixed = TRUE)))
  expect_true(any(grepl('file.path(R.home("bin"), "Rscript")', common, fixed = TRUE)))
  expect_true(any(grepl('paste0("R_LIBS=", paste(.libPaths()', common, fixed = TRUE)))
  sys.source(common_path, envir = env)
  expect_true(all(c(
    "worker_input_cache", "worker_self_processing", "worker_gpu_residency",
    "worker_rscript", "worker_library_env"
  ) %in% ls(env)))
  expect_identical(env$worker_rscript(), file.path(R.home("bin"), "Rscript"))
  expect_match(env$worker_library_env(), "^R_LIBS=")
  old_r_bin <- Sys.getenv("R_BIN", unset = NA_character_)
  on.exit({
    if (is.na(old_r_bin)) Sys.unsetenv("R_BIN") else Sys.setenv(R_BIN = old_r_bin)
  }, add = TRUE)
  Sys.setenv(R_BIN = "Rscript")
  expect_identical(env$worker_rscript(), unname(Sys.which("Rscript")))

  manifest <- readLines(file.path(root, "common", "make_hpc_float32_manifest.R"), warn = FALSE)
  cpu_reference <- readLines(file.path(root, "common", "benchmark_precompute_exact_references.R"), warn = FALSE)
  cuda_reference <- readLines(file.path(root, "common", "benchmark_precompute_exact_references_cuda.R"), warn = FALSE)
  refresh <- readLines(file.path(root, "refresh_tabula_muris", "run_references_cuda.sh"), warn = FALSE)
  expect_true(any(grepl("dataset_md5", manifest, fixed = TRUE)))
  expect_true(any(grepl("dataset_md5", cpu_reference, fixed = TRUE)))
  expect_true(any(grepl("dataset_md5", cuda_reference, fixed = TRUE)))
  expect_true(any(grepl("--datasets=TabulaMuris", refresh, fixed = TRUE)))
  expect_true(any(grepl("--resume=FALSE", refresh, fixed = TRUE)))
})

test_that("publication references reject a changed dataset fingerprint", {
  root <- test_path("../../benchmark_scripts/jss_reproduction")
  if (!dir.exists(root)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }
  td <- tempfile("faissR_dataset_fingerprint_")
  dir.create(td)
  data_path <- file.path(td, "TabulaMuris_float32.RData")
  writeBin(charToRaw("tabula-v1"), data_path)
  md5_v1 <- unname(tools::md5sum(data_path)[[1L]])

  cpu_env <- new.env(parent = globalenv())
  old_cpu <- Sys.getenv("FAISSR_CPU_REFERENCE_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old_cpu)) Sys.unsetenv("FAISSR_CPU_REFERENCE_SOURCE_ONLY") else
      Sys.setenv(FAISSR_CPU_REFERENCE_SOURCE_ONLY = old_cpu)
  }, add = TRUE)
  Sys.setenv(FAISSR_CPU_REFERENCE_SOURCE_ONLY = "true")
  sys.source(file.path(root, "common", "benchmark_precompute_exact_references.R"), envir = cpu_env)

  ref_path <- file.path(td, "reference.RData")
  faissR_reference <- list(
    status = "success", dataset_md5 = md5_v1,
    indices = matrix(1L, nrow = 2L, ncol = 3L)
  )
  save(faissR_reference, file = ref_path)
  expect_true(cpu_env$reference_is_valid(ref_path, 3L, md5_v1))

  writeBin(charToRaw("tabula-v2"), data_path)
  md5_v2 <- unname(tools::md5sum(data_path)[[1L]])
  expect_false(cpu_env$reference_is_valid(ref_path, 3L, md5_v2))
})



test_that("final JSS campaign submitter preserves explicit phase gates", {
  campaign <- test_path(
    "../../benchmark_scripts/jss_reproduction/final_campaign"
  )
  submitter <- file.path(campaign, "submit_campaign.R")
  if (!file.exists(submitter)) {
    skip("Final campaign submitter is unavailable after installation.")
  }
  old <- Sys.getenv("FAISSR_JSS_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("FAISSR_JSS_SOURCE_ONLY") else
      Sys.setenv(FAISSR_JSS_SOURCE_ONLY = old)
  }, add = TRUE)
  Sys.setenv(FAISSR_JSS_SOURCE_ONLY = "true")
  env <- new.env(parent = globalenv())
  sys.source(submitter, envir = env)

  contract <- env$phase_contract()
  expect_identical(
    contract$phase,
    c(
      "qa", "references", "calibration", "calibration_audit",
      "held_out", "diagnostics", "aggregate", "freeze"
    )
  )
  expect_identical(
    contract$expected_jobs,
    c(2L, 4L, 63L, 1L, 113L, 14L, 4L, 2L)
  )
  expect_equal(sum(contract$expected_jobs), 203L)
  for (i in seq_len(nrow(contract))) {
    launchers <- env$phase_launchers(campaign, contract$phase[[i]])
    expect_length(launchers, contract$expected_jobs[[i]])
    expect_true(all(file.exists(launchers)), info = contract$phase[[i]])
  }

  env$script_path <- function() submitter
  output <- capture.output(env$submit_phase("qa", dry_run = TRUE))
  expect_length(output, 2L)
  expect_true(all(grepl("^sbatch --export=ALL", output)))
  expect_true(any(grepl("run_package_route_qa_cpu12.sh", output, fixed = TRUE)))
  expect_true(any(grepl("run_package_route_qa_cuda.sh", output, fixed = TRUE)))

  cpu_batch <- capture.output(env$submit_phase(
    "held_out", dry_run = TRUE, backend = "cpu", start = 26L, limit = 25L
  ))
  expect_length(cpu_batch, 25L)
  expect_true(all(grepl("/held_out/cpu/", cpu_batch, fixed = TRUE)))

  cuda_batch <- capture.output(env$submit_phase(
    "held_out", dry_run = TRUE, backend = "cuda", start = 26L, limit = 24L
  ))
  expect_length(cuda_batch, 24L)
  expect_true(all(grepl("/held_out/cuda/", cuda_batch, fixed = TRUE)))

  expect_error(
    env$submit_phase(
      "held_out", dry_run = TRUE, backend = "cuda", start = 50L
    ),
    "only 49 launchers"
  )
})

test_that("final JSS campaign submitter preserves a partial submission ledger", {
  campaign <- test_path(
    "../../benchmark_scripts/jss_reproduction/final_campaign"
  )
  submitter_path <- file.path(campaign, "submit_campaign.R")
  if (!file.exists(submitter_path)) {
    skip("Final campaign submitter is unavailable after installation.")
  }
  old_source_only <- Sys.getenv("FAISSR_JSS_SOURCE_ONLY", unset = NA_character_)
  tracked_env <- c(
    "BASE_DIR", "SINGULARITY_IMAGE", "EXPECTED_FAISSR_VERSION",
    "FAISSR_PACKAGE_COMMIT", "SINGULARITYENV_FAISSR_IMAGE_COMMIT",
    "APPTAINERENV_FAISSR_IMAGE_COMMIT"
  )
  old_env <- Sys.getenv(tracked_env, unset = NA_character_)
  on.exit({
    if (is.na(old_source_only)) Sys.unsetenv("FAISSR_JSS_SOURCE_ONLY") else
      Sys.setenv(FAISSR_JSS_SOURCE_ONLY = old_source_only)
    for (i in seq_along(tracked_env)) {
      if (is.na(old_env[[i]])) Sys.unsetenv(tracked_env[[i]]) else
        do.call(Sys.setenv, setNames(list(old_env[[i]]), tracked_env[[i]]))
    }
  }, add = TRUE)

  Sys.setenv(FAISSR_JSS_SOURCE_ONLY = "true")
  env <- new.env(parent = globalenv())
  sys.source(submitter_path, envir = env)
  env$script_path <- function() submitter_path

  base_dir <- tempfile("faissR-submit-ledger-")
  dir.create(base_dir, recursive = TRUE)
  Sys.setenv(
    BASE_DIR = base_dir,
    SINGULARITY_IMAGE = file.path(base_dir, "frozen.sif"),
    EXPECTED_FAISSR_VERSION = "0.99.20"
  )
  calls <- list()
  fake_submitter <- function(command, args, stdout, stderr) {
    calls[[length(calls) + 1L]] <<- list(command = command, args = args)
    if (length(calls) == 1L) return("12345")
    value <- "simulated sbatch rejection"
    attr(value, "status") <- 1L
    value
  }
  fake_preflight <- function(image, expected_version) {
    list(version = expected_version, commit = paste(rep("a", 40L), collapse = ""))
  }

  expect_error(
    env$submit_phase(
      "qa", preflight = fake_preflight, submitter = fake_submitter
    ),
    "Submission failed after 1 jobs"
  )
  expect_length(calls, 2L)
  expect_true(all(vapply(
    calls,
    function(x) normalizePath(tail(x$args, 1L), mustWork = TRUE) %in%
      normalizePath(env$phase_launchers(campaign, "qa"), mustWork = TRUE),
    logical(1L)
  )))

  ledgers <- list.files(
    file.path(base_dir, "faissR_JSS_REPRODUCTION", "final_campaign", "submissions"),
    pattern = "[.]csv$", full.names = TRUE
  )
  expect_length(ledgers, 1L)
  ledger <- read.csv(ledgers[[1L]], stringsAsFactors = FALSE)
  expect_identical(ledger$submission_status, c("submitted", "failed"))
  expect_equal(ledger$job_id[[1L]], 12345)
  expect_true(is.na(ledger$job_id[[2L]]))
  expect_match(ledger$submission_output[[2L]], "simulated sbatch rejection")
  expect_identical(
    Sys.getenv("SINGULARITYENV_FAISSR_IMAGE_COMMIT"),
    paste(rep("a", 40L), collapse = "")
  )
  expect_identical(
    Sys.getenv("APPTAINERENV_FAISSR_IMAGE_COMMIT"),
    paste(rep("a", 40L), collapse = "")
  )
})

test_that("publication-suite sync utility is portable and non-destructive", {
  sync_script <- test_path(
    "../../benchmark_scripts/jss_reproduction/sync_publication_suite.sh"
  )
  if (!file.exists(sync_script)) {
    skip("Publication-suite synchronization utility is unavailable.")
  }
  text <- paste(readLines(sync_script, warn = FALSE), collapse = "\n")
  expect_match(text, "rsync -a", fixed = TRUE)
  expect_false(grepl("--delete", text, fixed = TRUE))
  expect_false(grepl("/Users/stefano", text, fixed = TRUE))
  expect_match(text, "source_count.*277", perl = TRUE)
  expect_match(text, "target_count.*277", perl = TRUE)
  expect_match(text, "submit_campaign.R", fixed = TRUE)
})

test_that("JSS compact replication report is executed and error-free", {
  jss <- test_path("../../manuscript/jss")
  code_path <- file.path(jss, "code.R")
  html_path <- file.path(jss, "code.html")
  skip_if_not(file.exists(code_path) && file.exists(html_path))

  code <- readLines(code_path, warn = FALSE)
  html <- readLines(html_path, warn = FALSE)
  expect_true(any(grepl('candidates <- c("code.R"', code, fixed = TRUE)))
  expect_true(any(grepl("exact_cpu", html, fixed = TRUE)))
  expect_true(any(grepl("sessionInfo()", html, fixed = TRUE)))
  expect_false(any(grepl("## Error", html, fixed = TRUE)))
  expect_false(any(grepl("begin.rcode", html, fixed = TRUE)))
})

test_that("publication rnndescent routes use their current public APIs", {
  skip_if_not_installed("rnndescent")
  script <- test_path(
    "../../benchmark_scripts/jss_reproduction/common/benchmark_jmlr_tuned_methods.R"
  )
  if (!file.exists(script)) {
    skip("Publication benchmark scripts are unavailable after installation.")
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
  env <- new.env(parent = globalenv())
  sys.source(script, envir = env)

  expect_identical(env$algorithm_seed_for("rnndescent_rpf", 17L), 17L)
  expect_identical(env$algorithm_seed_for("RcppHNSW_hnsw", 17L), 17L)
  expect_true(is.na(env$algorithm_seed_for("rnndescent_bruteforce", 17L)))

  set.seed(20260730)
  x <- matrix(stats::rnorm(64L * 8L), nrow = 64L, ncol = 8L)
  for (method in c(
    "rnndescent_rpf", "rnndescent_rnnd", "rnndescent_nnd"
  )) {
    answer <- env$run_external_method(
      x, method, 5L, "euclidean", 2L, 20260730L
    )
    expect_identical(dim(answer$indices), c(64L, 5L), info = method)
    expect_identical(dim(answer$distances), c(64L, 5L), info = method)
    expect_true(all(is.finite(answer$distances)), info = method)
  }

  for (metric in c("cosine", "correlation")) {
    answer <- env$run_external_method(
      x, "rnndescent_bruteforce", 5L, metric, 2L, 20260730L
    )
    expected <- matrix(NA_real_, nrow(x), 5L)
    for (i in seq_len(nrow(x))) {
      ids <- answer$indices[i, ]
      if (identical(metric, "cosine")) {
        denom <- sqrt(rowSums(x[ids, , drop = FALSE]^2)) *
          sqrt(sum(x[i, ]^2))
        expected[i, ] <- 1 - drop(
          x[ids, , drop = FALSE] %*% x[i, ]
        ) / denom
      } else {
        expected[i, ] <- 1 - vapply(ids, function(j) {
          stats::cor(x[i, ], x[j, ])
        }, numeric(1L))
      }
    }
    expect_equal(answer$distances, expected, tolerance = 2e-5, info = metric)
  }

  set.seed(1L)
  first <- env$run_external_method(
    x, "rnndescent_rpf", 5L, "euclidean", 2L, 20260730L
  )
  set.seed(999L)
  second <- env$run_external_method(
    x, "rnndescent_rpf", 5L, "euclidean", 2L, 20260730L
  )
  expect_identical(first$indices, second$indices)
})

test_that("synthetic exact-reference paths are dataset-specific", {
  root <- test_path("../../benchmark_scripts/jss_reproduction")
  if (!dir.exists(root)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }

  old <- Sys.getenv("FAISSR_CUDA_REFERENCE_SOURCE_ONLY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("FAISSR_CUDA_REFERENCE_SOURCE_ONLY") else
      Sys.setenv(FAISSR_CUDA_REFERENCE_SOURCE_ONLY = old)
  }, add = TRUE)
  Sys.setenv(FAISSR_CUDA_REFERENCE_SOURCE_ONLY = "true")

  env <- new.env(parent = globalenv())
  sys.source(
    file.path(root, "common", "benchmark_precompute_exact_references_cuda.R"),
    envir = env
  )
  p2 <- env$reference_file(
    "/tmp/synthetic_spatial_n10000_p2_unit_float32.RData",
    "euclidean", 100L, 1024L, 4L
  )
  p3 <- env$reference_file(
    "/tmp/synthetic_spatial_n10000_p3_unit_float32.RData",
    "euclidean", 100L, 1024L, 4L
  )
  real <- env$reference_file(
    "/tmp/MNIST_float32.RData", "euclidean", 100L, 1024L, 4L
  )

  expect_false(identical(p2, p3))
  expect_match(basename(p2), "^synthetic_spatial_n10000_p2_unit_float32__")
  expect_match(basename(p3), "^synthetic_spatial_n10000_p3_unit_float32__")
  expect_identical(
    basename(real),
    "faissR_exact_reference_euclidean_k100_q1024_seed4.RData"
  )

  consumers <- c(
    "benchmark_jmlr_tuned_methods.R",
    "benchmark_method_tuning_from_reference.R",
    "benchmark_reusable_external_indexes.R"
  )
  for (name in consumers) {
    source_text <- readLines(file.path(root, "common", name), warn = FALSE)
    expect_true(any(grepl('startsWith(dataset_file, "synthetic_")', source_text,
                          fixed = TRUE)), info = name)
  }
})

test_that("publication provenance has resolved redistribution decisions", {
  root <- test_path("../../benchmark_scripts/jss_reproduction")
  if (!dir.exists(root)) {
    skip("Publication scripts are not available in this installed-package test context.")
  }

  path <- file.path(
    root, "reviewer_response", "dataset_provenance_jss_template.csv"
  )
  provenance <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)

  expect_setequal(provenance$redistribution_permitted, c("yes", "no"))
  expect_false(any(grepl(
    "verify|unknown|pending",
    provenance$redistribution_permitted,
    ignore.case = TRUE
  )))
  expect_true(all(grepl("^[[:xdigit:]]{32}$", provenance$dataset_md5)))
  expect_true(all(nzchar(provenance$source_url)))
  expect_true(all(nzchar(provenance$source_release)))
  expect_true(all(nzchar(provenance$source_accession)))
  expect_true(all(nzchar(provenance$preprocessing)))
})
