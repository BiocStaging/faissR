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

is_present <- function(x) {
  !is.na(x) & nzchar(trimws(as.character(x)))
}

main <- function() {
  args <- parse_args()
  provenance_path <- normalizePath(
    args$provenance %||% "Data/dataset_provenance_jss.csv",
    mustWork = TRUE
  )
  data_root <- normalizePath(args$`data-root` %||% args$data_root %||% ".", mustWork = TRUE)
  out <- args$out %||% ""

  provenance <- read.csv(
    provenance_path,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  required <- c(
    "dataset", "source_url", "source_release", "source_accession",
    "citation", "license_or_terms", "redistribution_permitted",
    "acquisition_date", "preprocessing", "source_file", "dataset_md5",
    "dataset_sha256"
  )
  missing_columns <- setdiff(required, names(provenance))
  if (length(missing_columns)) {
    stop("Missing provenance columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }
  if (anyDuplicated(provenance$dataset)) {
    stop("Dataset names must be unique in the provenance manifest.", call. = FALSE)
  }

  policy <- tolower(trimws(provenance$redistribution_permitted))
  resolved <- policy %in% c("yes", "no")
  metadata_fields <- setdiff(required, c("dataset", "dataset_md5", "dataset_sha256"))
  metadata_complete <- apply(
    provenance[, metadata_fields, drop = FALSE],
    1L,
    function(x) all(is_present(x))
  )
  md5_valid <- grepl("^[[:xdigit:]]{32}$", provenance$dataset_md5)
  sha256_valid <- grepl("^[[:xdigit:]]{64}$", provenance$dataset_sha256)
  fingerprint_present <- md5_valid | sha256_valid

  paths <- ifelse(
    grepl("^/", provenance$source_file),
    provenance$source_file,
    file.path(data_root, provenance$source_file)
  )
  file_exists <- file.exists(paths)
  observed_md5 <- rep(NA_character_, nrow(provenance))
  observed_md5[file_exists] <- unname(tools::md5sum(paths[file_exists]))
  md5_match <- !md5_valid | (file_exists & tolower(observed_md5) == tolower(provenance$dataset_md5))

  audit <- data.frame(
    dataset = provenance$dataset,
    redistribution_permitted = policy,
    converted_matrix_in_replication_archive = policy == "yes",
    source_file = provenance$source_file,
    file_exists = file_exists,
    expected_md5 = provenance$dataset_md5,
    observed_md5 = observed_md5,
    redistribution_resolved = resolved,
    metadata_complete = metadata_complete,
    fingerprint_present = fingerprint_present,
    fingerprint_match = md5_match,
    pass = resolved & metadata_complete & fingerprint_present & file_exists & md5_match,
    stringsAsFactors = FALSE
  )

  print(audit, row.names = FALSE)
  if (nzchar(out)) {
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    write.csv(audit, out, row.names = FALSE)
    cat("Wrote dataset provenance audit: ", out, "\n", sep = "")
  }
  if (any(!audit$pass)) {
    stop(sum(!audit$pass), " dataset provenance or fingerprint checks failed.", call. = FALSE)
  }
  cat("All ", nrow(audit), " dataset provenance and fingerprint checks passed.\n", sep = "")
}

main()
