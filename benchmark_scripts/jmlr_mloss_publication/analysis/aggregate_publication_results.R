#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
  }
  out
}

split_values <- function(x, default) {
  trimws(strsplit(x %||% default, ",", fixed = TRUE)[[1L]])
}

read_union <- function(files) {
  tables <- lapply(files, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    x$source_file <- normalizePath(path, mustWork = TRUE)
    x$source_mtime <- as.numeric(file.info(path)$mtime)
    x$run_root <- dirname(path)
    x
  })
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, tables)
}

latest_method_runs <- function(x) {
  if (!"dataset_md5" %in% names(x)) x$dataset_md5 <- NA_character_
  suite <- ifelse(is.na(x$dataset_suite) | !nzchar(x$dataset_suite), "real", x$dataset_suite)
  key <- paste(x$backend, x$method_id, suite, x$dataset, x$metric, sep = "\r")
  selected <- unlist(lapply(split(seq_len(nrow(x)), key), function(ii) {
    roots <- unique(x$run_root[ii])
    root_time <- vapply(roots, function(root) max(x$source_mtime[ii][x$run_root[ii] == root]), numeric(1))
    ii[x$run_root[ii] == roots[[which.max(root_time)]]]
  }), use.names = FALSE)
  x[sort(selected), , drop = FALSE]
}

expand_external_targets <- function(x, targets) {
  external <- x$implementation != "faissR" | is.na(x$target_recall)
  fixed <- x[!external, , drop = FALSE]
  ext <- x[external, , drop = FALSE]
  if (!nrow(ext)) return(fixed)
  expanded <- do.call(rbind, lapply(targets, function(target) {
    out <- ext
    out$target_recall <- target
    out
  }))
  rbind(fixed, expanded)
}

group_apply <- function(x, columns, fun) {
  key_data <- lapply(x[columns], function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  key <- interaction(key_data, drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(x, key), fun)
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

robust_summary <- function(x, expected_seeds, expected_repeats) {
  if (!"dataset_md5" %in% names(x)) x$dataset_md5 <- NA_character_
  if (!"result_backend" %in% names(x)) x$result_backend <- NA_character_
  columns <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k", "target_recall",
    "implementation", "method_id", "public_method", "kind", "n_threads",
    "result_backend"
  )
  group_apply(x, columns, function(part) {
    success <- part$status == "success"
    times <- suppressWarnings(as.numeric(part$time_sec[success]))
    recalls <- suppressWarnings(as.numeric(part$recall_at_k[success]))
    memory <- suppressWarnings(as.numeric(part$peak_rss_gb[success]))
    gpu_memory <- if ("gpu_memory_peak_mib" %in% names(part)) {
      suppressWarnings(as.numeric(part$gpu_memory_peak_mib[success]))
    } else {
      numeric()
    }
    copies <- suppressWarnings(as.numeric(part$host_copy_sec[success]))
    target <- suppressWarnings(as.numeric(part$target_recall[[1L]]))
    seeds <- unique(part$validation_seed)
    seeds <- seeds[!is.na(seeds)]
    expected_runs <- expected_seeds * expected_repeats
    expected_repeat_ids <- seq_len(expected_repeats)
    observed_pairs <- paste(part$validation_seed, part$repeat_id, sep = "\r")
    complete <- length(seeds) == expected_seeds &&
      nrow(part) == expected_runs &&
      !anyDuplicated(observed_pairs) &&
      all(success) &&
      all(vapply(seeds, function(seed) {
        identical(
          sort(as.integer(part$repeat_id[part$validation_seed == seed])),
          expected_repeat_ids
        )
      }, logical(1L)))
    data.frame(
      part[1L, columns, drop = FALSE],
      n_rows = nrow(part),
      n_success = sum(success),
      n_failed = sum(!success),
      n_validation_seeds = length(seeds),
      expected_runs = expected_runs,
      complete_validation = complete,
      median_time_sec = if (any(is.finite(times))) median(times[is.finite(times)]) else NA_real_,
      iqr_time_sec = if (sum(is.finite(times)) > 1L) IQR(times[is.finite(times)]) else NA_real_,
      median_peak_rss_gb = if (any(is.finite(memory))) median(memory[is.finite(memory)]) else NA_real_,
      median_gpu_memory_peak_mib = if (any(is.finite(gpu_memory))) median(gpu_memory[is.finite(gpu_memory)]) else NA_real_,
      median_host_copy_sec = if (any(is.finite(copies))) median(copies[is.finite(copies)]) else NA_real_,
      mean_recall_at_k = if (any(is.finite(recalls))) mean(recalls[is.finite(recalls)]) else NA_real_,
      min_recall_at_k = if (any(is.finite(recalls))) min(recalls[is.finite(recalls)]) else NA_real_,
      target_met_all_runs = complete && length(recalls) == expected_runs &&
        all(is.finite(recalls) & recalls >= target),
      stringsAsFactors = FALSE
    )
  })
}

rank_qualifying <- function(summary) {
  keys <- c("dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k", "target_recall")
  group_apply(summary, keys, function(part) {
    qualifying <- part[part$complete_validation & part$target_met_all_runs & is.finite(part$median_time_sec), , drop = FALSE]
    qualifying <- qualifying[order(qualifying$median_time_sec, qualifying$method_id), , drop = FALSE]
    is_faissr_auto <- qualifying$implementation == "faissR" &
      qualifying$public_method == "auto"
    is_faissr_auto[is.na(is_faissr_auto)] <- FALSE
    auto <- qualifying[is_faissr_auto, , drop = FALSE]
    overall <- qualifying[!is_faissr_auto, , drop = FALSE]
    exact_family <- overall$public_method %in% c("exact", "flat", "bruteforce") |
      grepl("_(exact|flat|bruteforce)$", overall$method_id)
    provider <- as.character(overall$result_backend)
    provider[is.na(provider) | !nzchar(provider)] <- overall$method_id[
      is.na(provider) | !nzchar(provider)
    ]
    route_identity <- ifelse(
      exact_family,
      paste(
        "exact_family", overall$implementation, overall$backend,
        overall$metric, provider, sep = "::"
      ),
      paste("method", overall$method_id, sep = "::")
    )
    overall <- overall[!duplicated(route_identity), , drop = FALSE]
    faissr_oracle <- overall[
      overall$implementation == "faissR",
      ,
      drop = FALSE
    ]
    exact <- overall[
      overall$public_method %in% c("exact", "flat", "bruteforce") |
        grepl("_(exact|flat|bruteforce)$", overall$method_id), , drop = FALSE
    ]
    pick <- function(tbl, i, column, default = NA) {
      if (nrow(tbl) < i) default else tbl[[column]][[i]]
    }
    data.frame(
      part[1L, keys, drop = FALSE],
      n_complete_methods = sum(part$complete_validation),
      n_qualifying_methods = nrow(qualifying),
      fastest_method = pick(overall, 1L, "method_id", NA_character_),
      fastest_time_sec = pick(overall, 1L, "median_time_sec", NA_real_),
      fastest_recall = pick(overall, 1L, "min_recall_at_k", NA_real_),
      second_method = pick(overall, 2L, "method_id", NA_character_),
      second_time_sec = pick(overall, 2L, "median_time_sec", NA_real_),
      exact_baseline_method = pick(exact, 1L, "method_id", NA_character_),
      exact_baseline_time_sec = pick(exact, 1L, "median_time_sec", NA_real_),
      faissr_oracle_method = pick(
        faissr_oracle, 1L, "method_id", NA_character_
      ),
      faissr_oracle_time_sec = pick(
        faissr_oracle, 1L, "median_time_sec", NA_real_
      ),
      faissr_oracle_recall = pick(
        faissr_oracle, 1L, "min_recall_at_k", NA_real_
      ),
      faissr_oracle_provider = pick(
        faissr_oracle, 1L, "result_backend", NA_character_
      ),
      auto_method = pick(auto, 1L, "method_id", NA_character_),
      auto_time_sec = pick(auto, 1L, "median_time_sec", NA_real_),
      auto_recall = pick(auto, 1L, "min_recall_at_k", NA_real_),
      auto_provider = pick(auto, 1L, "result_backend", NA_character_),
      auto_recall_difference = if (nrow(auto) && nrow(faissr_oracle)) {
        auto$min_recall_at_k[[1L]] - faissr_oracle$min_recall_at_k[[1L]]
      } else {
        NA_real_
      },
      auto_provider_agreement = if (nrow(auto) && nrow(faissr_oracle)) {
        identical(
          as.character(auto$result_backend[[1L]]),
          as.character(faissr_oracle$result_backend[[1L]])
        )
      } else {
        NA
      },
      auto_over_oracle = if (nrow(auto) && nrow(faissr_oracle)) {
        auto$median_time_sec[[1L]] / faissr_oracle$median_time_sec[[1L]]
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  })
}

route_audit <- function(x) {
  success <- x$status == "success"
  auditable <- success & x$implementation == "faissR" &
    !is.na(x$result_backend) & nzchar(x$result_backend)
  requested_backend_bad <- success & !is.na(x$requested_backend) &
    nzchar(x$requested_backend) & x$requested_backend != x$backend
  resolved <- tolower(as.character(x$result_backend))
  cpu_bad <- auditable & x$backend == "cpu" & grepl("cuda|gpu|cuvs", resolved)
  cuda_bad <- auditable & x$backend == "cuda" & !grepl("cuda|gpu|cuvs", resolved)
  requested_method_bad <- success & x$implementation == "faissR" &
    !is.na(x$public_method) & !is.na(x$requested_method) &
    nzchar(x$requested_method) & x$requested_method != x$public_method
  bad <- requested_backend_bad | cpu_bad | cuda_bad | requested_method_bad
  out <- x[bad, , drop = FALSE]
  if (nrow(out)) {
    out$route_audit_reason <- paste(
      ifelse(requested_backend_bad[bad], "requested_backend_mismatch", ""),
      ifelse(cpu_bad[bad] | cuda_bad[bad], "resolved_device_mismatch", ""),
      ifelse(requested_method_bad[bad], "requested_method_mismatch", ""),
      sep = ";"
    )
  }
  out
}

compliance_table <- function(summary) {
  columns <- c("backend", "metric", "target_recall")
  group_apply(summary, columns, function(part) data.frame(
    part[1L, columns, drop = FALSE],
    evaluated_cells = nrow(part),
    complete_cells = sum(part$complete_validation),
    target_met_cells = sum(part$complete_validation & part$target_met_all_runs),
    completion_fraction = mean(part$complete_validation),
    target_attainment_fraction = if (any(part$complete_validation))
      mean(part$target_met_all_runs[part$complete_validation]) else NA_real_,
    stringsAsFactors = FALSE
  ))
}

write_report <- function(out_dir, files, combined, summary, best, route_errors) {
  lines <- c(
    "# Held-out publication evidence",
    "",
    paste0("- Source result files: ", length(files), "."),
    paste0("- Selected result rows: ", nrow(combined), "."),
    paste0("- Robust method cells: ", nrow(summary), "."),
    paste0("- Complete validation cells: ", sum(summary$complete_validation), "."),
    paste0("- Cells meeting recall in every run: ", sum(summary$complete_validation & summary$target_met_all_runs), "."),
    paste0("- Successful route mismatches: ", nrow(route_errors), "."),
    "",
    "A result is publication-eligible only when its newest run contains exactly one successful row for every expected validation-seed/repeat pair and every row reaches the recall target. Failed, timed-out, unsupported, duplicated, incomplete, and route-mismatched rows remain in the archive.",
    "",
    "`jss_auto_vs_oracle.csv` compares method = auto with the fastest independently requested qualifying faissR method, the attainable oracle for the package selector. Values above one in `auto_over_oracle` quantify remaining automatic-selection regret. Cross-package winners remain separate in the fastest/second-fastest columns.",
    "",
    paste0("Complete fastest/second-fastest blocks: ", sum(!is.na(best$fastest_method)), " of ", nrow(best), ".")
  )
  writeLines(lines, file.path(out_dir, "JSS_EVIDENCE_REPORT.md"))
}

main <- function() {
  args <- parse_args()
  root <- normalizePath(args$results_root %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(root, "analysis"), mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  backend <- tolower(args$backend %||% "all")
  if (!backend %in% c("all", "cpu", "cuda")) stop("`backend` must be all, cpu, or cuda.", call. = FALSE)
  targets <- as.numeric(split_values(args$target_recalls, "0.9,0.95,0.99"))
  expected_seeds <- as.integer(args$expected_seeds %||% 2L)
  expected_repeats <- as.integer(args$expected_repeats %||% 3L)
  datasets <- split_values(args$datasets, "")
  datasets <- datasets[nzchar(datasets)]

  files <- list.files(root, pattern = "^jmlr_tuned_benchmark_results[.]csv$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/calibration/|/analysis/", files)]
  if (!length(files)) stop("No held-out publication result files were found under `results_root`.", call. = FALSE)
  combined <- read_union(files)
  if (backend != "all") combined <- combined[combined$backend == backend, , drop = FALSE]
  if (length(datasets)) combined <- combined[combined$dataset %in% datasets, , drop = FALSE]
  if (!nrow(combined)) stop("No result rows match the requested backend.", call. = FALSE)
  combined <- latest_method_runs(combined)
  combined <- expand_external_targets(combined, targets)
  combined <- combined[order(combined$dataset, combined$backend, combined$metric, combined$k,
                             combined$target_recall, combined$method_id,
                             combined$validation_seed, combined$repeat_id), , drop = FALSE]
  summary <- robust_summary(combined, expected_seeds, expected_repeats)
  best <- rank_qualifying(summary)
  routes <- route_audit(combined)
  compliance <- compliance_table(summary)

  write.csv(combined, file.path(out_dir, "jss_publication_results_combined.csv"), row.names = FALSE)
  write.csv(combined[combined$status != "success", , drop = FALSE], file.path(out_dir, "jss_failures_and_unsupported.csv"), row.names = FALSE)
  write.csv(summary, file.path(out_dir, "jss_robust_method_summary.csv"), row.names = FALSE)
  write.csv(best, file.path(out_dir, "jss_fastest_second_exact_and_auto.csv"), row.names = FALSE)
  write.csv(best[, c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall", "faissr_oracle_method", "faissr_oracle_time_sec",
    "faissr_oracle_recall", "faissr_oracle_provider", "auto_method",
    "auto_time_sec", "auto_recall", "auto_provider",
    "auto_recall_difference", "auto_provider_agreement", "auto_over_oracle"
  ), drop = FALSE],
            file.path(out_dir, "jss_auto_vs_oracle.csv"), row.names = FALSE)
  write.csv(compliance, file.path(out_dir, "jss_recall_compliance_table.csv"), row.names = FALSE)
  write.csv(routes, file.path(out_dir, "jss_successful_route_mismatches.csv"), row.names = FALSE)
  focus <- best[best$k == 30L & abs(best$target_recall - 0.99) < 1e-12, , drop = FALSE]
  write.csv(focus, file.path(out_dir, "jss_main_table_k30_recall099.csv"), row.names = FALSE)
  write_report(out_dir, files, combined, summary, best, routes)
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  outputs <- list.files(out_dir, full.names = TRUE)
  checksums <- data.frame(file = basename(outputs), md5 = unname(tools::md5sum(outputs)), stringsAsFactors = FALSE)
  write.csv(checksums, file.path(out_dir, "checksums.csv"), row.names = FALSE)
  cat("Wrote held-out evidence to ", out_dir, "\n", sep = "")
}

if (!identical(Sys.getenv("FAISSR_JSS_AGGREGATE_SOURCE_ONLY", unset = ""), "true")) main()
