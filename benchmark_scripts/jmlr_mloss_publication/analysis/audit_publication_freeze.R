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

logical_value <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  tolower(x) %in% c("true", "t", "1", "yes")
}

split_values <- function(x, default = "") {
  values <- trimws(strsplit(x %||% default, ",", fixed = TRUE)[[1L]])
  values[nzchar(values)]
}

read_union <- function(files) {
  rows <- lapply(files, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    x$archive_file <- normalizePath(path, mustWork = TRUE)
    x
  })
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, rows)
}

command_output <- function(command, args = character()) {
  tryCatch(paste(system2(command, args, stdout = TRUE, stderr = TRUE), collapse = "\n"),
           error = function(e) paste("unavailable:", conditionMessage(e)))
}

main <- function() {
  args <- parse_args()
  manifest_path <- normalizePath(args$manifest, mustWork = TRUE)
  results_root <- normalizePath(args$results_root, mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(results_root, "freeze_audit"), mustWork = FALSE)
  provenance_path <- args$provenance %||% ""
  strict <- logical_value(args$strict, TRUE)
  datasets <- split_values(args$datasets)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (length(datasets)) manifest <- manifest[manifest$dataset %in% datasets, , drop = FALSE]
  if (!nrow(manifest)) stop("No manifest rows match `--datasets`.", call. = FALSE)
  if (!"path" %in% names(manifest) && "output" %in% names(manifest)) manifest$path <- manifest$output
  manifest$file_exists <- file.exists(manifest$path)
  manifest$current_md5 <- NA_character_
  manifest$current_md5[manifest$file_exists] <- unname(tools::md5sum(manifest$path[manifest$file_exists]))
  if ("dataset_md5" %in% names(manifest)) {
    manifest$manifest_md5_matches <- is.na(manifest$dataset_md5) | !nzchar(manifest$dataset_md5) |
      manifest$dataset_md5 == manifest$current_md5
  } else {
    manifest$manifest_md5_matches <- NA
  }
  write.csv(manifest, file.path(out_dir, "frozen_dataset_manifest.csv"), row.names = FALSE)

  result_files <- list.files(results_root, pattern = "^jmlr_tuned_benchmark_results[.]csv$", recursive = TRUE, full.names = TRUE)
  result_files <- result_files[!grepl("/calibration/|/analysis/", result_files)]
  if (!length(result_files)) stop("No held-out result files found.", call. = FALSE)
  results <- read_union(result_files)
  if (length(datasets)) results <- results[results$dataset %in% datasets, , drop = FALSE]
  if (!nrow(results)) stop("No held-out result rows match `--datasets`.", call. = FALSE)
  current <- setNames(manifest$current_md5, manifest$dataset)
  results$current_dataset_md5 <- unname(current[as.character(results$dataset)])
  results$fingerprint_current <- !is.na(results$dataset_md5) & !is.na(results$current_dataset_md5) &
    results$dataset_md5 == results$current_dataset_md5
  stale <- results[!results$fingerprint_current | is.na(results$fingerprint_current),
                   c("dataset", "dataset_md5", "current_dataset_md5", "backend", "method_id", "archive_file"), drop = FALSE]
  stale <- unique(stale)
  write.csv(stale, file.path(out_dir, "stale_or_unverifiable_result_rows.csv"), row.names = FALSE)

  provenance <- if (nzchar(provenance_path) && file.exists(provenance_path)) {
    read.csv(provenance_path, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    data.frame(dataset = unique(manifest$dataset), source_url = "", license_or_terms = "",
               citation = "", acquisition_date = "", notes = "", stringsAsFactors = FALSE)
  }
  required <- c("dataset", "source_url", "license_or_terms", "citation", "acquisition_date")
  for (name in setdiff(required, names(provenance))) provenance[[name]] <- ""
  if (length(datasets)) provenance <- provenance[provenance$dataset %in% datasets, , drop = FALSE]
  provenance$provenance_complete <- apply(provenance[, required[-1L], drop = FALSE], 1L, function(x) {
    all(!is.na(x) & nzchar(trimws(as.character(x))))
  })
  write.csv(provenance, file.path(out_dir, "dataset_provenance_audit.csv"), row.names = FALSE)

  package_version <- tryCatch(as.character(utils::packageVersion("faissR")), error = function(e) NA_character_)
  backend <- tryCatch(paste(capture.output(print(faissR::backend_info())), collapse = "\n"),
                      error = function(e) paste("unavailable:", conditionMessage(e)))
  freeze <- data.frame(
    field = c("audit_timestamp_utc", "faissR_version", "package_git_commit", "container_path",
              "container_sha256", "slurm_job_id", "hostname", "R", "OS"),
    value = c(format(Sys.time(), tz = "UTC", usetz = TRUE), package_version,
              Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET"),
              Sys.getenv("FAISSR_CONTAINER_PATH", unset = "UNSET"),
              Sys.getenv("FAISSR_CONTAINER_SHA256", unset = "UNSET"),
              Sys.getenv("SLURM_JOB_ID", unset = "manual"), Sys.info()[["nodename"]],
              R.version.string, paste(Sys.info()[c("sysname", "release", "machine")], collapse = " ")),
    stringsAsFactors = FALSE
  )
  write.csv(freeze, file.path(out_dir, "software_container_freeze.csv"), row.names = FALSE)
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  writeLines(backend, file.path(out_dir, "faissR_backend_info.txt"))
  writeLines(command_output("nvidia-smi"), file.path(out_dir, "nvidia-smi.txt"))
  writeLines(command_output("lscpu"), file.path(out_dir, "lscpu.txt"))

  all_files <- list.files(out_dir, full.names = TRUE)
  write.csv(data.frame(file = basename(all_files), md5 = unname(tools::md5sum(all_files))),
            file.path(out_dir, "audit_checksums.csv"), row.names = FALSE)
  problems <- c(
    if (any(!manifest$file_exists)) paste(sum(!manifest$file_exists), "dataset files missing") else NULL,
    if (nrow(stale)) paste(nrow(stale), "stale/unverifiable result groups") else NULL,
    if (any(!provenance$provenance_complete)) paste(sum(!provenance$provenance_complete), "incomplete provenance rows") else NULL,
    if (Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET") == "UNSET") "package commit unset" else NULL,
    if (Sys.getenv("FAISSR_CONTAINER_SHA256", unset = "UNSET") == "UNSET") "container SHA-256 unset" else NULL
  )
  writeLines(c("# Publication freeze audit", "", if (length(problems)) paste0("- ", problems) else "All checks passed."),
             file.path(out_dir, "JSS_FREEZE_AUDIT_REPORT.md"))
  if (strict && length(problems)) stop("Freeze audit found: ", paste(problems, collapse = "; "), call. = FALSE)
}

main()
