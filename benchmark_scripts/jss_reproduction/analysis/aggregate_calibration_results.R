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
    stop("All matching calibration CSV files are empty.", call. = FALSE)
  }
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, tables)
}

latest_rows <- function(x, key_columns) {
  key_values <- lapply(x[key_columns], function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  key <- interaction(key_values, drop = TRUE, lex.order = TRUE)
  selected <- vapply(
    split(seq_len(nrow(x)), key),
    function(ii) ii[[which.max(x$source_mtime[ii])]],
    integer(1)
  )
  x[sort(selected), , drop = FALSE]
}

group_summary <- function(x, columns, fun) {
  key_values <- lapply(x[columns], function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  key <- interaction(key_values, drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(x, key), fun)
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

main <- function() {
  args <- parse_args()
  root <- normalizePath(args$calibration_root %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(
    args$out_dir %||% file.path(root, "analysis"),
    mustWork = FALSE
  )
  datasets <- split_values(args$datasets)
  metrics <- split_values(
    args$metrics,
    "euclidean,cosine,correlation"
  )
  k_values <- as.integer(split_values(args$k_values, "15,30,50,100"))
  targets <- as.numeric(split_values(args$target_recalls, "0.9,0.95,0.99"))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  recommendation_files <- list.files(
    root,
    pattern = "_tuning_recommendations[.]csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  result_files <- list.files(
    root,
    pattern = "_tuning_results[.]csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(recommendation_files) || !length(result_files)) {
    stop("Calibration recommendations and result files are required.", call. = FALSE)
  }

  recommendations <- read_union(recommendation_files)
  candidates <- read_union(result_files)
  if (length(datasets)) {
    recommendations <- recommendations[
      recommendations$dataset %in% datasets,
      ,
      drop = FALSE
    ]
    candidates <- candidates[candidates$dataset %in% datasets, , drop = FALSE]
  }
  recommendations <- recommendations[
    recommendations$metric %in% metrics &
      recommendations$k %in% k_values,
    ,
    drop = FALSE
  ]
  candidates <- candidates[
    candidates$metric %in% metrics & candidates$k %in% k_values,
    ,
    drop = FALSE
  ]
  if (!nrow(recommendations)) {
    stop("No calibration recommendations match the requested campaign.", call. = FALSE)
  }

  if (!"target_recall_threshold" %in% names(recommendations)) {
    recommendations$target_recall_threshold <- recommendations$target_recall
  }
  recommendations <- latest_rows(
    recommendations,
    c("backend", "method", "dataset", "metric", "k", "target_recall_threshold")
  )
  recommendations$target_met <- recommendations$status == "success" &
    is.finite(recommendations$recall_at_k) &
    recommendations$recall_at_k + 1e-12 >=
      recommendations$target_recall_threshold
  recommendations$below_target <- recommendations$status == "success" &
    !recommendations$target_met

  candidate_key <- intersect(
    c("backend", "method", "dataset", "metric", "k", "candidate_id"),
    names(candidates)
  )
  candidates <- latest_rows(candidates, candidate_key)

  policy_summary <- group_summary(
    recommendations,
    c("backend", "method", "metric"),
    function(part) {
      data.frame(
        part[1L, c("backend", "method", "metric"), drop = FALSE],
        datasets_observed = length(unique(part$dataset)),
        policy_cells = nrow(part),
        success_cells = sum(part$status == "success"),
        target_met_cells = sum(part$target_met),
        below_target_cells = sum(part$below_target),
        failed_cells = sum(part$status != "success"),
        target_met_fraction = mean(part$target_met),
        stringsAsFactors = FALSE
      )
    }
  )

  candidate_summary <- group_summary(
    candidates,
    c("backend", "method", "metric"),
    function(part) {
      status <- as.character(part$status)
      data.frame(
        part[1L, c("backend", "method", "metric"), drop = FALSE],
        candidate_rows = nrow(part),
        successful_rows = sum(status == "success"),
        failed_rows = sum(status == "failed"),
        timeout_rows = sum(status == "timeout"),
        unsupported_rows = sum(status == "unsupported"),
        other_rows = sum(!status %in% c(
          "success", "failed", "timeout", "unsupported"
        )),
        stringsAsFactors = FALSE
      )
    }
  )

  observed_datasets <- if (length(datasets)) {
    datasets
  } else {
    sort(unique(recommendations$dataset))
  }
  methods <- unique(recommendations[, c("backend", "method"), drop = FALSE])
  expected <- do.call(rbind, lapply(seq_len(nrow(methods)), function(i) {
    expand.grid(
      backend = methods$backend[[i]],
      method = methods$method[[i]],
      dataset = observed_datasets,
      metric = metrics,
      k = k_values,
      target_recall_threshold = targets,
      stringsAsFactors = FALSE
    )
  }))
  key <- function(x) {
    paste(
      x$backend, x$method, x$dataset, x$metric, x$k,
      format(x$target_recall_threshold, digits = 12),
      sep = "\r"
    )
  }
  missing <- expected[!key(expected) %in% key(recommendations), , drop = FALSE]

  write.csv(
    recommendations,
    file.path(out_dir, "jss_calibration_recommendations.csv"),
    row.names = FALSE
  )
  write.csv(
    policy_summary,
    file.path(out_dir, "jss_calibration_policy_summary.csv"),
    row.names = FALSE
  )
  write.csv(
    candidate_summary,
    file.path(out_dir, "jss_calibration_candidate_summary.csv"),
    row.names = FALSE
  )
  write.csv(
    missing,
    file.path(out_dir, "jss_calibration_missing_cells.csv"),
    row.names = FALSE
  )
  write.csv(
    recommendations[
      recommendations$status != "success" | !recommendations$target_met,
      ,
      drop = FALSE
    ],
    file.path(out_dir, "jss_calibration_negative_evidence.csv"),
    row.names = FALSE
  )

  report <- c(
    "# JSS calibration audit",
    "",
    paste0("Recommendation files: ", length(recommendation_files), "."),
    paste0("Candidate-result files: ", length(result_files), "."),
    paste0("Latest policy cells: ", nrow(recommendations), "."),
    paste0("Target-meeting cells: ", sum(recommendations$target_met), "."),
    paste0("Below-target successful cells: ", sum(recommendations$below_target), "."),
    paste0("Failed policy cells: ", sum(recommendations$status != "success"), "."),
    paste0("Missing expected cells: ", nrow(missing), "."),
    "",
    "No below-target or incomplete cell is eligible for automatic approximate-method promotion."
  )
  writeLines(report, file.path(out_dir, "JSS_CALIBRATION_AUDIT.md"))
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  cat("Wrote calibration audit to ", out_dir, "\n", sep = "")
}

main()
