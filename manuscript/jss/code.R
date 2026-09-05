#' ---
#' title: "faissR JSS replication code"
#' ---
#'
#' # Replication code for the faissR JSS article
#'
#' This is the standalone entry point for both the reduced ordinary-computer
#' replication and the checksummed publication analysis. It never analyzes an
#' archive until its SHA-256 digest has been verified.
#'
#' Full calibration and validation are deliberately not launched here. Their
#' separate Slurm/Singularity commands are recorded in
#' `benchmark_scripts/jss_reproduction/final_campaign/submission_commands.txt`.
#'
#' Required software for the compact path is R, FAISS, and faissR. Set an
#' output directory if desired:
#'
#' ```r
#' Sys.setenv(FAISSR_JSS_DERIVED_DIR = "/path/to/derived")
#' ```
#'
#' To rebuild every manuscript table from the bundled checksummed snapshot:
#'
#' ```r
#' Sys.setenv(FAISSR_JSS_MODE = "archive")
#' ```
#'
#' To use separately distributed files, also set:
#'
#' ```r
#' Sys.setenv(
#'   FAISSR_JSS_ARCHIVE = "/path/to/faissR_jss_evidence_snapshot.tar.gz",
#'   FAISSR_JSS_ARCHIVE_SHA256 = "/path/to/faissR_jss_evidence_snapshot.tar.gz.sha256"
#' )
#' ```

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
this_file <- if (length(file_arg)) {
  normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
} else {
  candidates <- c("code.R", file.path("manuscript", "jss", "code.R"))
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) {
    stop("Cannot locate code.R from the current working directory.")
  }
  normalizePath(candidates[[1L]], mustWork = TRUE)
}

replication_script <- file.path(dirname(this_file), "replication_article.R")
if (!file.exists(replication_script)) {
  stop("Cannot find the authoritative article replication script: ",
       replication_script)
}
Sys.setenv(FAISSR_JSS_REPLICATION_SCRIPT = normalizePath(replication_script))

#' Run the selected replication mode. `compact` is the default; `archive`
#' requires no GPU and performs analysis only; `all` runs both paths.
source(replication_script, chdir = TRUE)

#' The compact example results and the complete software session are printed in
#' the rendered report so reviewers can compare an executed `code.html` with
#' the article examples.
derived_dir <- Sys.getenv(
  "FAISSR_JSS_DERIVED_DIR",
  unset = file.path(dirname(replication_script), "derived")
)
example_file <- file.path(derived_dir, "article_example_summary.csv")
if (file.exists(example_file)) {
  example_summary <- utils::read.csv(example_file, stringsAsFactors = FALSE)
  print(example_summary, row.names = FALSE)
}
verification_file <- file.path(derived_dir, "archive_verification.csv")
if (file.exists(verification_file)) {
  archive_verification <- utils::read.csv(
    verification_file, stringsAsFactors = FALSE
  )
  print(archive_verification, row.names = FALSE)
}
cpu_loodo_file <- file.path(derived_dir, "cpu_loodo_verification.csv")
if (file.exists(cpu_loodo_file)) {
  cpu_loodo_verification <- utils::read.csv(
    cpu_loodo_file, stringsAsFactors = FALSE
  )
  print(cpu_loodo_verification, row.names = FALSE)
}
manifest_file <- file.path(
  derived_dir, "manuscript_tables", "manuscript_table_manifest.csv"
)
if (file.exists(manifest_file)) {
  table_manifest <- utils::read.csv(manifest_file, stringsAsFactors = FALSE)
  print(table_manifest[, c("table_number", "file", "rows", "sha256")],
        row.names = FALSE)
}
sessionInfo()

#' The generated directory contains the example summary, `sessionInfo.txt`,
#' and, in archive mode, checksum verification, analysis outputs, all 18
#' manuscript tables, the paired CPU and comprehensive-R comparison figures,
#' and their audit summaries. Any checksum, schema, fingerprint, aggregation,
#' table-audit, or figure-audit failure stops execution.
