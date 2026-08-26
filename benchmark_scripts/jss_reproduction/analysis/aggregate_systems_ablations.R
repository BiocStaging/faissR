#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]]) || !nzchar(x[[1L]])) y else x
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

read_union <- function(files) {
  tables <- lapply(files, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    if (!nrow(x)) return(NULL)
    x$source_file <- normalizePath(path, mustWork = TRUE)
    x$source_mtime <- as.numeric(file.info(path)$mtime)
    x
  })
  tables <- Filter(Negate(is.null), tables)
  if (!length(tables)) {
    stop("All matching systems-ablation CSV files are empty.", call. = FALSE)
  }
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, tables)
}

latest_dataset_runs <- function(x) {
  key <- interaction(x$backend, x$dataset, drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(seq_len(nrow(x)), key), function(ii) {
    files <- unique(x$source_file[ii])
    times <- vapply(
      files,
      function(path) max(x$source_mtime[ii][x$source_file[ii] == path]),
      numeric(1)
    )
    ii[x$source_file[ii] == files[[which.max(times)]]]
  })
  x[sort(unlist(rows, use.names = FALSE)), , drop = FALSE]
}

median_summary <- function(x) {
  columns <- c(
    "dataset", "dataset_md5", "n", "p", "backend", "method", "metric", "k",
    "faissR_version", "faissR_package_commit", "faissR_image_commit",
    "input_type", "experiment",
    "phase"
  )
  for (name in setdiff(columns, names(x))) x[[name]] <- NA
  key <- interaction(
    lapply(x[columns], function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "<NA>"
      value
    }),
    drop = TRUE,
    lex.order = TRUE
  )
  rows <- lapply(split(x, key), function(part) {
    elapsed <- as.numeric(part$elapsed_sec)
    memory_valid <- if ("memory_valid_for_comparison" %in% names(part)) {
      value <- suppressWarnings(as.logical(part$memory_valid_for_comparison))
      !is.na(value) & value
    } else {
      rep(FALSE, nrow(part))
    }
    rss <- suppressWarnings(as.numeric(part$peak_rss_gb[memory_valid]))
    gpu <- as.numeric(part$gpu_memory_peak_mib)
    copy <- as.numeric(part$host_copy_sec)
    data.frame(
      part[1L, columns, drop = FALSE],
      repeats = nrow(part),
      median_elapsed_sec = median(elapsed, na.rm = TRUE),
      iqr_elapsed_sec = if (sum(is.finite(elapsed)) > 1L) {
        IQR(elapsed, na.rm = TRUE)
      } else {
        NA_real_
      },
      n_valid_host_memory_measurements = sum(is.finite(rss)),
      median_peak_rss_gb = if (any(is.finite(rss))) median(rss, na.rm = TRUE) else NA_real_,
      median_gpu_memory_peak_mib = if (any(is.finite(gpu))) median(gpu, na.rm = TRUE) else NA_real_,
      median_host_copy_sec = if (any(is.finite(copy))) median(copy, na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

paired_ratio <- function(summary, arm_column, numerator, denominator, contrast) {
  keep <- summary[[arm_column]] %in% c(numerator, denominator)
  x <- summary[keep, , drop = FALSE]
  id_columns <- setdiff(
    c(
      "dataset", "dataset_md5", "n", "p", "backend", "method", "metric", "k",
      "input_type", "experiment", "phase"
    ),
    arm_column
  )
  id_columns <- id_columns[
    !vapply(x[id_columns], function(value) length(unique(value)) == 1L, logical(1))
  ]
  fixed_columns <- c(
    "dataset", "dataset_md5", "n", "p", "backend", "method", "metric", "k",
    "faissR_version", "faissR_package_commit", "faissR_image_commit",
    "input_type", "experiment", "phase"
  )
  fixed_columns <- setdiff(fixed_columns, arm_column)
  id_columns <- unique(c(fixed_columns, id_columns))
  key <- interaction(
    lapply(x[id_columns], function(value) {
      value <- as.character(value)
      value[is.na(value)] <- "<NA>"
      value
    }),
    drop = TRUE,
    lex.order = TRUE
  )
  rows <- lapply(split(x, key), function(part) {
    a <- part[part[[arm_column]] == numerator, , drop = FALSE]
    b <- part[part[[arm_column]] == denominator, , drop = FALSE]
    if (nrow(a) != 1L || nrow(b) != 1L) return(NULL)
    data.frame(
      part[1L, fixed_columns, drop = FALSE],
      contrast = contrast,
      numerator_arm = numerator,
      denominator_arm = denominator,
      numerator_time_sec = a$median_elapsed_sec,
      denominator_time_sec = b$median_elapsed_sec,
      time_ratio = a$median_elapsed_sec / b$median_elapsed_sec,
      time_difference_sec = a$median_elapsed_sec - b$median_elapsed_sec,
      numerator_peak_rss_gb = a$median_peak_rss_gb,
      denominator_peak_rss_gb = b$median_peak_rss_gb,
      peak_rss_ratio = if (
        a$n_valid_host_memory_measurements > 0L &&
          b$n_valid_host_memory_measurements > 0L
      ) a$median_peak_rss_gb / b$median_peak_rss_gb else NA_real_,
      numerator_gpu_memory_mib = a$median_gpu_memory_peak_mib,
      denominator_gpu_memory_mib = b$median_gpu_memory_peak_mib,
      gpu_memory_ratio = a$median_gpu_memory_peak_mib /
        b$median_gpu_memory_peak_mib,
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

route_over_flat <- function(summary) {
  x <- summary[
    summary$experiment == "input_cache" &
      summary$phase == "cache_disabled" &
      summary$input_type == "float32",
    ,
    drop = FALSE
  ]
  flat <- x[x$method == "flat", c(
    "dataset", "dataset_md5", "n", "p", "backend", "metric", "k",
    "faissR_version", "faissR_package_commit", "faissR_image_commit",
    "median_elapsed_sec"
  ), drop = FALSE]
  names(flat)[ncol(flat)] <- "flat_time_sec"
  candidates <- x[x$method != "flat", , drop = FALSE]
  keys <- setdiff(names(flat), "flat_time_sec")
  out <- merge(candidates, flat, by = keys, all = FALSE, sort = FALSE)
  if (!nrow(out)) return(data.frame())
  data.frame(
    out[, c(
      "dataset", "dataset_md5", "n", "p", "backend", "method", "metric", "k",
      "faissR_version", "faissR_package_commit", "faissR_image_commit"
    ), drop = FALSE],
    estimand = "search_index_route_conditional_on_float32_cache_disabled",
    contrast = "route_over_flat",
    conditioning_input_type = "float32",
    conditioning_phase = "cache_disabled",
    numerator_arm = out$method,
    denominator_arm = "flat",
    numerator_time_sec = out$median_elapsed_sec,
    denominator_time_sec = out$flat_time_sec,
    time_ratio = out$median_elapsed_sec / out$flat_time_sec,
    time_difference_sec = out$median_elapsed_sec - out$flat_time_sec,
    stringsAsFactors = FALSE
  )
}

contrast_summary <- function(x, group_columns) {
  if (!nrow(x)) return(data.frame())
  x <- x[is.finite(x$time_ratio) & x$time_ratio > 0, , drop = FALSE]
  if (!nrow(x)) return(data.frame())
  dataset_groups <- unique(c(group_columns, "dataset"))
  dataset_key <- interaction(x[dataset_groups], drop = TRUE, lex.order = TRUE)
  dataset_rows <- lapply(split(x, dataset_key), function(part) {
    data.frame(
      part[1L, dataset_groups, drop = FALSE],
      dataset_median_time_ratio = median(part$time_ratio),
      cells = nrow(part),
      stringsAsFactors = FALSE
    )
  })
  dataset_rows <- do.call(rbind, dataset_rows)
  summary_key <- interaction(dataset_rows[group_columns], drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(dataset_rows, summary_key), function(part) {
    ratio <- part$dataset_median_time_ratio
    data.frame(
      part[1L, group_columns, drop = FALSE],
      datasets = nrow(part),
      cells = sum(part$cells),
      median_time_ratio = median(ratio),
      iqr_time_ratio = if (length(ratio) > 1L) IQR(ratio) else NA_real_,
      min_time_ratio = min(ratio),
      max_time_ratio = max(ratio),
      median_speedup = median(1 / ratio),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

main <- function() {
  args <- parse_args()
  root <- normalizePath(args$ablations_root %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(
    args$out_dir %||% file.path(root, "analysis"),
    mustWork = FALSE
  )
  datasets <- split_values(
    args$datasets,
    "COIL20,MNIST,flow18,mass41"
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  files <- list.files(
    root,
    pattern = "^jss_systems_ablation_results[.]csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(files)) stop("No systems-ablation result files found.", call. = FALSE)
  results <- read_union(files)
  results <- results[
    results$dataset %in% datasets & results$status == "success",
    ,
    drop = FALSE
  ]
  if (!nrow(results)) stop("No successful rows match `--datasets`.", call. = FALSE)
  results <- latest_dataset_runs(results)
  summary <- median_summary(results)

  input_rows <- summary[summary$experiment == "input_cache", , drop = FALSE]
  input_contrasts <- paired_ratio(
    input_rows,
    "input_type",
    "float32",
    "double",
    "float32_over_double"
  )
  input_contrasts$estimand <-
    "end_to_end_representation_effect_same_route_and_phase"
  cache_contrasts <- rbind(
    paired_ratio(
      input_rows,
      "phase",
      "cache_enabled_cold",
      "cache_disabled",
      "cold_cache_over_disabled"
    ),
    paired_ratio(
      input_rows,
      "phase",
      "cache_enabled_warm",
      "cache_disabled",
      "warm_cache_over_disabled"
    ),
    paired_ratio(
      input_rows,
      "phase",
      "cache_enabled_warm",
      "cache_enabled_cold",
      "warm_over_cold"
    )
  )
  cache_contrasts$estimand <-
    "fitted_index_reuse_effect_same_route_and_representation"
  self_rows <- summary[summary$experiment == "self_processing", , drop = FALSE]
  self_contrasts <- paired_ratio(
    self_rows,
    "phase",
    "compiled_self_removal",
    "r_self_removal",
    "compiled_over_r_self_removal"
  )
  residency <- summary[summary$experiment == "gpu_residency", , drop = FALSE]
  if (nrow(residency)) {
    residency$host_copy_fraction <- residency$median_host_copy_sec /
      residency$median_elapsed_sec
  }
  route_contrasts <- route_over_flat(summary)
  representation_primary <- input_contrasts[
    input_contrasts$phase == "cache_disabled", , drop = FALSE
  ]
  reuse_primary <- cache_contrasts[
    cache_contrasts$contrast == "warm_over_cold" &
      cache_contrasts$input_type == "float32",
    ,
    drop = FALSE
  ]
  component_parts <- list(
    contrast_summary(
      representation_primary,
      c("backend", "estimand", "contrast")
    ),
    contrast_summary(
      reuse_primary,
      c("backend", "estimand", "contrast")
    ),
    contrast_summary(
      route_contrasts,
      c("backend", "method", "estimand", "contrast")
    )
  )
  component_columns <- unique(unlist(lapply(component_parts, names), use.names = FALSE))
  component_parts <- lapply(component_parts, function(part) {
    for (name in setdiff(component_columns, names(part))) part[[name]] <- NA
    part[, component_columns, drop = FALSE]
  })
  component_summary <- do.call(rbind, component_parts)

  write.csv(
    results,
    file.path(out_dir, "jss_ablation_eligible_rows.csv"),
    row.names = FALSE
  )
  write.csv(
    summary,
    file.path(out_dir, "jss_ablation_median_summary.csv"),
    row.names = FALSE
  )
  write.csv(
    input_contrasts,
    file.path(out_dir, "jss_ablation_float32_contrasts.csv"),
    row.names = FALSE
  )
  write.csv(
    cache_contrasts,
    file.path(out_dir, "jss_ablation_cache_contrasts.csv"),
    row.names = FALSE
  )
  write.csv(
    self_contrasts,
    file.path(out_dir, "jss_ablation_self_processing_contrasts.csv"),
    row.names = FALSE
  )
  write.csv(
    residency,
    file.path(out_dir, "jss_ablation_gpu_residency.csv"),
    row.names = FALSE
  )
  write.csv(
    route_contrasts,
    file.path(out_dir, "jss_ablation_route_over_flat_contrasts.csv"),
    row.names = FALSE
  )
  write.csv(
    component_summary,
    file.path(out_dir, "jss_ablation_component_summary.csv"),
    row.names = FALSE
  )
  report <- c(
    "# JSS systems-ablation audit",
    "",
    paste0("Source files: ", length(files), "."),
    paste0("Eligible successful rows: ", nrow(results), "."),
    paste0("Datasets: ", paste(sort(unique(results$dataset)), collapse = ", "), "."),
    paste0("Float32 contrasts: ", nrow(input_contrasts), "."),
    paste0("Cache contrasts: ", nrow(cache_contrasts), "."),
    paste0("Self-processing contrasts: ", nrow(self_contrasts), "."),
    paste0("GPU-residency summaries: ", nrow(residency), "."),
    paste0("Compatible-representation route contrasts: ", nrow(route_contrasts), "."),
    paste0(
      "Valid isolated host-memory observations: ",
      sum(summary$n_valid_host_memory_measurements), "."
    ),
    "",
    "Ratios below one favor the numerator arm. Timing repetitions are technical replicates.",
    "Host-memory ratios are emitted only when both arms contain explicitly valid fresh-process measurements; shared-process VmHWM values are excluded."
  )
  writeLines(report, file.path(out_dir, "JSS_ABLATION_AUDIT.md"))
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  cat("Wrote systems-ablation evidence to ", out_dir, "\n", sep = "")
}

main()
