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

read_union <- function(files) {
  tables <- lapply(files, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    x$archive_file <- normalizePath(path, mustWork = TRUE)
    x
  })
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, tables)
}

finite_median <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) median(x) else NA_real_
}

finite_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) max(x) else NA_real_
}

main <- function() {
  args <- parse_args()
  results_root <- normalizePath(
    args$results_root %||% stop("`--results_root` is required.", call. = FALSE),
    mustWork = TRUE
  )
  out_dir <- args$out_dir %||% file.path(results_root, "analysis")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(
    results_root,
    pattern = "^jss_reusable_external_index_results[.]csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(files)) stop("No reusable-index result files found.", call. = FALSE)
  all <- read_union(files)
  write.csv(
    all, file.path(out_dir, "jss_reusable_external_index_all_rows.csv"),
    row.names = FALSE
  )

  keys <- c("dataset", "package", "package_version", "route", "metric", "k")
  group_key <- do.call(
    paste,
    c(
      lapply(all[keys], function(x) ifelse(is.na(x), "<NA>", as.character(x))),
      sep = "\r"
    )
  )
  groups <- split(all, group_key)
  summary <- lapply(groups, function(x) {
    cold <- x[x$phase == "cold_build_plus_query" & x$status == "success", , drop = FALSE]
    warm <- x[x$phase == "warm_query" & x$status == "success", , drop = FALSE]
    out <- x[1L, keys, drop = FALSE]
    n_seeds <- length(unique(x$seed[is.finite(x$seed)]))
    warm_repeats <- finite_max(x$repeat_id[x$phase == "warm_query"])
    out$n <- x$n[[1L]]
    out$p <- x$p[[1L]]
    out$query_n <- finite_max(x$query_n)
    out$expected_cold_rows <- n_seeds
    out$successful_cold_rows <- nrow(cold)
    out$expected_warm_rows <- if (is.finite(warm_repeats)) {
      n_seeds * warm_repeats
    } else {
      0L
    }
    out$successful_warm_rows <- nrow(warm)
    out$median_conversion_sec <- finite_median(cold$conversion_sec)
    out$median_build_sec <- finite_median(cold$build_sec)
    out$median_cold_total_sec <- finite_median(cold$elapsed_sec)
    out$median_warm_query_sec <- finite_median(warm$elapsed_sec)
    out$warm_to_cold_ratio <- out$median_warm_query_sec /
      out$median_cold_total_sec
    out$min_recall_at_k <- if (any(is.finite(x$recall_at_k))) {
      min(x$recall_at_k[is.finite(x$recall_at_k)])
    } else {
      NA_real_
    }
    out$all_finite_distances <- all(
      x$finite_distance[x$status == "success"]
    )
    out$all_sorted_distances <- all(
      x$sorted_distance[x$status == "success"]
    )
    out$failures <- sum(x$status != "success")
    out
  })
  summary <- do.call(rbind, summary)
  summary$complete <- with(
    summary,
    successful_cold_rows == expected_cold_rows &
      successful_warm_rows == expected_warm_rows & failures == 0L
  )
  write.csv(
    summary, file.path(out_dir, "jss_reusable_external_index_summary.csv"),
    row.names = FALSE
  )
  writeLines(
    c(
      "# Reusable external-index audit",
      "",
      paste("Rows:", nrow(all)),
      paste("Summary cells:", nrow(summary)),
      paste("Complete cells:", sum(summary$complete), "/", nrow(summary)),
      paste("Failed executions:", sum(all$status != "success")),
      "",
      "Cold total is conversion plus index construction plus the first sampled-query call.",
      "Warm time is a repeated sampled-query call against the same fitted index.",
      "These timings are not mixed with the primary full all-row cold comparison."
    ),
    file.path(out_dir, "JSS_REUSABLE_EXTERNAL_INDEX_REPORT.md")
  )
}

main()
