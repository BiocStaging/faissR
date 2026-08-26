options(prompt = "R> ", continue = "+  ", width = 70,
        useFancyQuotes = FALSE)

if (!requireNamespace("faissR", quietly = TRUE)) {
  stop("Install faissR before running the article replication script.")
}

out_dir <- Sys.getenv(
  "FAISSR_JSS_DERIVED_DIR",
  unset = file.path(getwd(), "derived")
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sha256_files <- function(paths) {
  paths <- normalizePath(paths, mustWork = TRUE)
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(vapply(paths, function(path) {
      con <- file(path, open = "rb")
      value <- as.character(openssl::sha256(con))
      close(con)
      value
    }, character(1L)))
  }
  sha256sum <- Sys.which("sha256sum")
  shasum <- Sys.which("shasum")
  if (nzchar(sha256sum)) {
    return(vapply(paths, function(path) {
      sub("[[:space:]].*$", "", system2(sha256sum, shQuote(path), stdout = TRUE)[[1L]])
    }, character(1L)))
  }
  if (nzchar(shasum)) {
    return(vapply(paths, function(path) {
      sub("[[:space:]].*$", "", system2(
        shasum, c("-a", "256", shQuote(path)), stdout = TRUE
      )[[1L]])
    }, character(1L)))
  }
  warning("No SHA-256 implementation is available; checksum values are NA.")
  rep(NA_character_, length(paths))
}

latest_method_runs <- function(x) {
  suite <- if ("dataset_suite" %in% names(x)) {
    value <- as.character(x$dataset_suite)
    value[is.na(value) | !nzchar(value)] <- "real"
    value
  } else {
    rep("real", nrow(x))
  }
  key <- paste(
    x$backend, x$method_id, suite, x$dataset, x$metric,
    sep = "\r"
  )
  selected <- unlist(lapply(split(seq_len(nrow(x)), key), function(ii) {
    roots <- unique(x$run_root[ii])
    root_time <- vapply(roots, function(root) {
      max(x$source_mtime[ii][x$run_root[ii] == root])
    }, numeric(1L))
    ii[x$run_root[ii] == roots[[which.max(root_time)]]]
  }), use.names = FALSE)
  x[sort(selected), , drop = FALSE]
}

x <- scale(as.matrix(iris[, 1:4]))

exact <- faissR::nn(
  x,
  k = 5,
  exclude_self = TRUE,
  backend = "cpu",
  method = "exact",
  metric = "euclidean",
  n_threads = 2
)
stopifnot(identical(dim(exact$indices), c(150L, 5L)))
stopifnot(all(exact$indices >= 1L), all(is.finite(exact$distances)))
exact_route <- attr(exact, "faiss")
stopifnot(
  identical(attr(exact, "requested_method"), "exact"),
  identical(exact_route$method, "exact"),
  identical(attr(exact, "metric"), "euclidean"),
  identical(attr(exact, "backend_used"), exact$backend_used)
)

hnsw <- faissR::nn(
  x,
  k = 15,
  exclude_self = TRUE,
  backend = "cpu",
  method = "hnsw",
  metric = "cosine",
  tuning = "auto",
  target_recall = 0.99,
  n_threads = 2
)
hnsw_tuning <- attr(hnsw, "approximation")
stopifnot(
  identical(dim(hnsw$indices), c(150L, 15L)),
  identical(hnsw_tuning$target_recall, 0.99),
  is.logical(hnsw_tuning$tuning_benchmark_target_met),
  length(hnsw_tuning$tuning_benchmark_target_met) == 1L,
  is.character(hnsw_tuning$tuning_benchmark_source),
  nzchar(hnsw_tuning$tuning_benchmark_source)
)

float_example_ran <- FALSE
if (requireNamespace("float", quietly = TRUE)) {
  xf <- float::fl(x)
  float_result <- faissR::nn(
    xf,
    k = 5,
    exclude_self = TRUE,
    backend = "cpu",
    method = "flat",
    output = "float",
    n_threads = 2
  )
  stopifnot(
    identical(dim(float_result$indices), c(150L, 5L)),
    identical(float_result$input_type, "float32"),
    identical(float_result$distance_type, "float32")
  )
  float_example_ran <- TRUE
}

model <- faissR::knn(
  x,
  iris$Species,
  k = 5,
  backend = "cpu",
  method = "flat",
  metric = "euclidean",
  n_threads = 2
)
classes <- predict(model, x[1:6, , drop = FALSE])
probabilities <- predict(
  model,
  x[1:6, , drop = FALSE],
  type = "prob"
)
stopifnot(length(classes) == 6L)
stopifnot(identical(dim(probabilities), c(6L, 3L)))
stopifnot(all(abs(rowSums(probabilities) - 1) < 1e-12))

example_summary <- data.frame(
  example = c(
    "exact_cpu",
    "hnsw_cpu",
    "float32_cpu_optional",
    "knn_classification"
  ),
  executed = c(TRUE, TRUE, float_example_ran, TRUE),
  rows = c(
    nrow(exact$indices),
    nrow(hnsw$indices),
    if (float_example_ran) nrow(float_result$indices) else NA_integer_,
    length(classes)
  ),
  columns = c(
    ncol(exact$indices),
    ncol(hnsw$indices),
    if (float_example_ran) ncol(float_result$indices) else NA_integer_,
    ncol(probabilities)
  ),
  stringsAsFactors = FALSE
)
write.csv(
  example_summary,
  file.path(out_dir, "article_example_summary.csv"),
  row.names = FALSE
)

results_root <- Sys.getenv("FAISSR_JSS_RESULTS_DIR", unset = "")
if (nzchar(results_root)) {
  result_files <- list.files(
    results_root,
    pattern = "^jmlr_tuned_benchmark_results[.]csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(result_files)) {
    stop("No publication benchmark result CSV files were found.")
  }

  tables <- lapply(result_files, read.csv, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("dataset", "backend", "method_id", "metric", "k", "status",
                "time_sec", "recall_at_k", "validation_seed", "repeat_id",
                "dataset_md5")
  missing_by_file <- Map(
    function(value, path) {
      missing <- setdiff(required, names(value))
      if (!length(missing)) return(NULL)
      paste0(normalizePath(path, mustWork = TRUE), ": ", paste(missing, collapse = ", "))
    },
    tables,
    result_files
  )
  missing_by_file <- unlist(missing_by_file, use.names = FALSE)
  if (length(missing_by_file)) {
    stop(
      "Publication result files are missing required columns:\n",
      paste(missing_by_file, collapse = "\n")
    )
  }

  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- Map(function(value, path) {
    for (name in setdiff(columns, names(value))) value[[name]] <- NA
    value$source_file <- normalizePath(path, mustWork = TRUE)
    value$source_mtime <- as.numeric(file.info(path)$mtime)
    value$run_root <- dirname(value$source_file)
    value
  }, tables, result_files)
  all_columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(value) {
    for (name in setdiff(all_columns, names(value))) value[[name]] <- NA
    value[, all_columns, drop = FALSE]
  })
  all_runs <- do.call(rbind, tables)
  combined <- latest_method_runs(all_runs)
  if (any(is.na(combined$dataset_md5) | !nzchar(combined$dataset_md5))) {
    stop("Every publication result row must include a non-empty dataset_md5 fingerprint.")
  }
  key_columns <- c(
    "dataset", "dataset_md5", "backend", "method_id", "metric", "k",
    "target_recall", "validation_seed", "repeat_id"
  )
  key_columns <- intersect(key_columns, names(combined))
  key <- do.call(
    paste,
    c(lapply(combined[key_columns], function(x) {
      x <- as.character(x)
      x[is.na(x)] <- "<NA>"
      x
    }), sep = "\r")
  )
  if (anyDuplicated(key)) {
    duplicate_rows <- combined[duplicated(key) | duplicated(key, fromLast = TRUE),
                               key_columns, drop = FALSE]
    write.csv(
      duplicate_rows,
      file.path(out_dir, "duplicate_publication_result_keys.csv"),
      row.names = FALSE
    )
    stop("The selected newest publication runs contain duplicate benchmark keys.")
  }

  dataset_manifest <- Sys.getenv("FAISSR_JSS_DATASET_MANIFEST", unset = "")
  if (nzchar(dataset_manifest)) {
    manifest <- read.csv(
      normalizePath(dataset_manifest, mustWork = TRUE),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (!"dataset" %in% names(manifest)) {
      stop("The frozen dataset manifest must contain a `dataset` column.")
    }
    if (!"dataset_md5" %in% names(manifest)) {
      if (!"path" %in% names(manifest)) {
        stop("The frozen dataset manifest must contain `dataset_md5` or `path`.")
      }
      manifest$dataset_md5 <- unname(tools::md5sum(manifest$path))
    }
    expected_md5 <- setNames(as.character(manifest$dataset_md5), manifest$dataset)
    observed_md5 <- expected_md5[as.character(combined$dataset)]
    if (any(is.na(observed_md5)) ||
        any(as.character(combined$dataset_md5) != observed_md5)) {
      stop("Benchmark dataset fingerprints do not match the frozen dataset manifest.")
    }
  }
  write.csv(
    all_runs,
    file.path(out_dir, "publication_results_all_runs.csv"),
    row.names = FALSE
  )
  write.csv(
    combined,
    file.path(out_dir, "publication_results_combined.csv"),
    row.names = FALSE
  )

  source_checksums <- data.frame(
    source_file = normalizePath(result_files, mustWork = TRUE),
    md5 = unname(tools::md5sum(result_files)),
    sha256 = unname(sha256_files(result_files)),
    bytes = unname(file.info(result_files)$size),
    stringsAsFactors = FALSE
  )
  write.csv(
    source_checksums,
    file.path(out_dir, "publication_result_source_checksums.csv"),
    row.names = FALSE
  )

  checksum_ledger <- Sys.getenv("FAISSR_JSS_RESULT_CHECKSUMS", unset = "")
  if (nzchar(checksum_ledger)) {
    ledger <- read.csv(
      normalizePath(checksum_ledger, mustWork = TRUE),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (!all(c("source_file", "sha256") %in% names(ledger))) {
      stop("The result checksum ledger must contain `source_file` and `sha256`.")
    }
    expected <- setNames(as.character(ledger$sha256), basename(ledger$source_file))
    observed <- setNames(source_checksums$sha256, basename(source_checksums$source_file))
    if (!setequal(names(expected), names(observed)) ||
        any(expected[names(observed)] != observed)) {
      stop("Publication result files do not match the frozen SHA-256 ledger.")
    }
  }

  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script_path <- if (length(file_arg)) normalizePath(sub("^--file=", "", file_arg[[1L]])) else ""
  package_root <- if (nzchar(script_path)) dirname(dirname(dirname(script_path))) else getwd()
  aggregator <- Sys.getenv(
    "FAISSR_JSS_AGGREGATOR",
    unset = file.path(
      package_root, "benchmark_scripts", "jss_reproduction",
      "analysis", "aggregate_publication_results.R"
    )
  )
  if (!file.exists(aggregator)) stop("Cannot find publication evidence aggregator: ", aggregator)
  analysis_dir <- file.path(out_dir, "held_out_analysis")
  status <- system2(
    "Rscript",
    vapply(c(
      aggregator,
      paste0("--results_root=", normalizePath(results_root, mustWork = TRUE)),
      paste0("--out_dir=", analysis_dir),
      "--backend=all", "--target_recalls=0.9,0.95,0.99",
      "--expected_seeds=2", "--expected_repeats=3"
    ), shQuote, character(1L))
  )
  if (!identical(status, 0L)) stop("Independent validation aggregation failed with status ", status)
}

writeLines(
  capture.output(sessionInfo()),
  file.path(out_dir, "sessionInfo.txt")
)
