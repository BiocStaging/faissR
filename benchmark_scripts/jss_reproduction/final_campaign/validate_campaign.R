#!/usr/bin/env Rscript

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) return(normalizePath(getwd(), mustWork = TRUE))
  normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
}

root <- dirname(script_path())
files <- list.files(root, pattern = "[.]sh$", recursive = TRUE, full.names = TRUE)
relative <- substring(files, nchar(root) + 2L)
publication <- !startsWith(relative, "resume/")
files <- files[publication]
relative <- relative[publication]
expected <- c(
  "calibration/real/cpu" = 30L,
  "calibration/real/cuda" = 33L,
  "held_out/cpu" = 64L,
  "held_out/cuda" = 49L,
  "references" = 4L,
  "reusable_external" = 10L,
  "ablations" = 2L,
  "qa" = 2L,
  "analysis" = 9L
)

count_prefix <- function(prefix) sum(startsWith(relative, paste0(prefix, "/")))
observed <- vapply(names(expected), count_prefix, integer(1L))
if (!identical(unname(observed), unname(expected))) {
  stop(
    "Unexpected launcher matrix:\n",
    paste(names(expected), "expected", expected, "observed", observed, collapse = "\n"),
    call. = FALSE
  )
}

validate_file <- function(path) {
  lines <- readLines(path, warn = FALSE)
  cuda <- any(grepl("^#SBATCH --account=l40sfree$", lines))
  cpu <- any(grepl("^#SBATCH --account=immunology$", lines))
  if (cuda == cpu) stop("Launcher must have exactly one backend header: ", path)
  required <- c(
    "^#!/usr/bin/env bash$",
    "^#SBATCH --nodes=1$",
    "^#SBATCH --time=48:00:00$",
    "^#SBATCH --job-name=",
    "^#SBATCH --output=",
    "^#SBATCH --error=",
    "^set -euo pipefail$",
    "singularity|run_one_|reviewer_response/"
  )
  absent <- required[
    !vapply(required, function(pattern) any(grepl(pattern, lines)), logical(1L))
  ]
  if (length(absent)) {
    stop("Missing required launcher content in ", path, ": ", paste(absent, collapse = ", "))
  }
  if (cuda) {
    cuda_required <- c(
      "^#SBATCH --partition=l40s$",
      "^#SBATCH --ntasks=2$",
      "^#SBATCH --gres=gpu:l40s:1$"
    )
    if (any(!vapply(
      cuda_required,
      function(pattern) any(grepl(pattern, lines)),
      logical(1L)
    ))) stop("Invalid CUDA Slurm header: ", path)
  } else {
    cpu_required <- c(
      "^#SBATCH --partition=ada$",
      "^#SBATCH --ntasks=12$"
    )
    if (any(!vapply(
      cpu_required,
      function(pattern) any(grepl(pattern, lines)),
      logical(1L)
    ))) stop("Invalid CPU Slurm header: ", path)
  }
  if (any(grepl("TabulaMuris", lines, fixed = TRUE))) {
    stop("TabulaMuris must not appear in the fixed JSS campaign: ", path)
  }
  status <- system2("bash", c("-n", shQuote(path)))
  if (!identical(status, 0L)) stop("Bash syntax validation failed: ", path)
  TRUE
}

invisible(vapply(files, validate_file, logical(1L)))
cat("Validated ", length(files), " independent Slurm launchers.\n", sep = "")
print(data.frame(section = names(expected), launchers = observed, row.names = NULL))
