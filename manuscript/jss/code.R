#' ---
#' title: "faissR JSS replication code"
#' ---
#'
#' # Replication code for the faissR JSS article
#'
#' This compact entry point is intended for an ordinary CPU computer. It runs
#' the executable article examples and records the R session. When
#' `FAISSR_JSS_RESULTS_DIR` points to the frozen publication archive, it also
#' checks the result schema and regenerates the held-out summary tables.
#'
#' Full calibration and validation are deliberately not launched here. Their
#' separate Slurm/Singularity commands are recorded in
#' `benchmark_scripts/jmlr_mloss_publication/final_campaign/submission_commands.txt`.
#'
#' Required software for the compact path is R, FAISS, and faissR. Set an
#' output directory if desired:
#'
#' ```r
#' Sys.setenv(FAISSR_JSS_DERIVED_DIR = "/path/to/derived")
#' ```
#'
#' To rebuild tables from frozen HPC results:
#'
#' ```r
#' Sys.setenv(FAISSR_JSS_RESULTS_DIR = "/path/to/frozen/results")
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

#' Run the compact checks and, when requested, rebuild frozen-result summaries.
source(replication_script, chdir = TRUE)

#' The compact example results and the complete software session are printed in
#' the rendered report so reviewers can compare an executed `code.html` with
#' the article examples.
derived_dir <- Sys.getenv(
  "FAISSR_JSS_DERIVED_DIR",
  unset = file.path(dirname(replication_script), "derived")
)
example_summary <- utils::read.csv(
  file.path(derived_dir, "article_example_summary.csv"),
  stringsAsFactors = FALSE
)
print(example_summary, row.names = FALSE)
sessionInfo()

#' The generated directory contains the example summary, `sessionInfo.txt`,
#' and, for a frozen result root, combined results, checksums, and held-out
#' analyses. Any schema, fingerprint, or aggregation failure stops execution.
