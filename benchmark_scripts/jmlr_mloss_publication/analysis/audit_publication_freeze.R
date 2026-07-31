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

canonical_commit <- function(x) {
  !is.na(x) & grepl("^[[:xdigit:]]{40}$", x)
}

audit_reference_identity <- function(paths, expected_commit, expected_version) {
  paths <- unique(as.character(paths))
  paths <- paths[!is.na(paths) & nzchar(paths)]
  if (!length(paths)) {
    return(data.frame(
      reference_path = character(), file_exists = logical(),
      faissR_version = character(),
      faissR_package_commit = character(), faissR_image_commit = character(),
      identity_pass = logical(), error = character(),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(paths, function(path) {
    exists <- file.exists(path)
    version_ref <- package_ref <- image_ref <- NA_character_
    error <- ""
    if (exists) {
      tryCatch({
        env <- new.env(parent = emptyenv())
        loaded <- load(path, envir = env)
        candidates <- mget(loaded, envir = env, inherits = FALSE)
        candidates <- Filter(is.list, candidates)
        if (!length(candidates)) {
          stop("reference file contains no list object")
        }
        reference <- candidates[[1L]]
        version_ref <- as.character(reference$faissR_version %||% NA_character_)
        package_ref <- as.character(reference$faissR_package_commit %||% NA_character_)
        image_ref <- as.character(reference$faissR_image_commit %||% NA_character_)
      }, error = function(e) {
        error <<- conditionMessage(e)
      })
    } else {
      error <- "reference file does not exist"
    }
    pass <- exists && !nzchar(error) && identical(version_ref, expected_version) &&
      canonical_commit(package_ref) &&
      canonical_commit(image_ref) && identical(package_ref, expected_commit) &&
      identical(image_ref, expected_commit)
    data.frame(
      reference_path = path, file_exists = exists,
      faissR_version = version_ref,
      faissR_package_commit = package_ref, faissR_image_commit = image_ref,
      identity_pass = pass, error = error,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
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

  package_version <- tryCatch(
    as.character(utils::packageVersion("faissR")),
    error = function(e) NA_character_
  )
  result_version <- if ("faissR_version" %in% names(results)) {
    as.character(results$faissR_version)
  } else {
    rep(NA_character_, nrow(results))
  }
  version_mismatch <- (
    is.na(result_version) | !nzchar(result_version) |
      is.na(package_version) | result_version != package_version
  )
  stale_versions <- unique(results[
    version_mismatch,
    intersect(
      c(
        "dataset", "backend", "method_id", "metric", "k",
        "faissR_version", "implementation_version", "archive_file"
      ),
      names(results)
    ),
    drop = FALSE
  ])
  write.csv(
    stale_versions,
    file.path(out_dir, "mismatched_faissR_result_versions.csv"),
    row.names = FALSE
  )

  package_commit <- Sys.getenv("FAISSR_PACKAGE_COMMIT", unset = "UNSET")
  image_commit <- Sys.getenv("FAISSR_IMAGE_COMMIT", unset = "UNSET")
  result_package_commit <- if ("faissR_package_commit" %in% names(results)) {
    as.character(results$faissR_package_commit)
  } else {
    rep(NA_character_, nrow(results))
  }
  result_image_commit <- if ("faissR_image_commit" %in% names(results)) {
    as.character(results$faissR_image_commit)
  } else {
    rep(NA_character_, nrow(results))
  }
  commit_mismatch <- !canonical_commit(result_package_commit) |
    !canonical_commit(result_image_commit) |
    result_package_commit != package_commit |
    result_image_commit != package_commit |
    result_package_commit != result_image_commit
  commit_mismatch[is.na(commit_mismatch)] <- TRUE
  stale_commits <- unique(results[
    commit_mismatch,
    intersect(
      c(
        "dataset", "backend", "method_id", "metric", "k",
        "faissR_package_commit", "faissR_image_commit", "archive_file"
      ),
      names(results)
    ),
    drop = FALSE
  ])
  write.csv(
    stale_commits,
    file.path(out_dir, "mismatched_faissR_result_commits.csv"),
    row.names = FALSE
  )

  reference_audit <- audit_reference_identity(
    if ("reference_path" %in% names(results)) results$reference_path else character(),
    package_commit, package_version
  )
  write.csv(
    reference_audit,
    file.path(out_dir, "exact_reference_identity_audit.csv"),
    row.names = FALSE
  )
  bad_references <- reference_audit[!reference_audit$identity_pass, , drop = FALSE]

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

  backend <- tryCatch(paste(capture.output(print(faissR::backend_info())), collapse = "\n"),
                      error = function(e) paste("unavailable:", conditionMessage(e)))
  container_sha256 <- Sys.getenv("FAISSR_CONTAINER_SHA256", unset = "UNSET")
  freeze <- data.frame(
    field = c("audit_timestamp_utc", "faissR_version", "package_git_commit",
              "image_git_commit", "container_path",
              "container_sha256", "slurm_job_id", "hostname", "R", "OS"),
    value = c(format(Sys.time(), tz = "UTC", usetz = TRUE), package_version,
              package_commit, image_commit,
              Sys.getenv("FAISSR_CONTAINER_PATH", unset = "UNSET"),
              container_sha256,
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
    if (nrow(stale_versions)) paste(nrow(stale_versions), "faissR result rows from another or unknown package version") else NULL,
    if (nrow(stale_commits)) paste(nrow(stale_commits), "result groups with missing or mismatched package/image commits") else NULL,
    if (nrow(bad_references)) paste(nrow(bad_references), "exact-reference files with missing or mismatched package/image commits") else NULL,
    if (any(!provenance$provenance_complete)) paste(sum(!provenance$provenance_complete), "incomplete provenance rows") else NULL,
    if (!grepl("^[[:xdigit:]]{40}$", package_commit)) "package commit is not a 40-character hexadecimal hash" else NULL,
    if (!grepl("^[[:xdigit:]]{40}$", image_commit)) "image commit is not a 40-character hexadecimal hash" else NULL,
    if (!identical(package_commit, image_commit)) "package and image commits differ" else NULL,
    if (!grepl("^[[:xdigit:]]{64}$", container_sha256)) "container SHA-256 is not a 64-character hexadecimal digest" else NULL
  )
  writeLines(c("# Publication freeze audit", "", if (length(problems)) paste0("- ", problems) else "All checks passed."),
             file.path(out_dir, "JSS_FREEZE_AUDIT_REPORT.md"))
  if (strict && length(problems)) stop("Freeze audit found: ", paste(problems, collapse = "; "), call. = FALSE)
}

main()
