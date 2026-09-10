#!/usr/bin/env Rscript
# Shared, isolated source-package check. No default R library is modified.
args <- commandArgs(TRUE)
if (length(args) < 3L) {
    stop("Usage: run.R SOURCE.tar.gz OUTPUT functional|diagnostic [SMOKE.R]")
}
source_archive <- normalizePath(args[[1]], mustWork = TRUE)
out <- args[[2]]
profile <- match.arg(args[[3]], c("functional", "diagnostic"))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, mustWork = TRUE)
if (file.exists(file.path(out, "status.csv"))) {
    stop("Output already contains a run; choose a new output directory.")
}
lib <- file.path(out, "library")
dir.create(lib, showWarnings = FALSE)
scratch <- tempfile("package-check-")
dir.create(scratch, showWarnings = FALSE)
if (grepl(" ", scratch, fixed = TRUE)) {
    stop("R CMD INSTALL requires a temporary directory without spaces.")
}
Sys.setenv(TMPDIR = scratch, TMP = scratch, TEMP = scratch)
r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
smoke <- if (length(args) >= 4L) normalizePath(args[[4]], mustWork = TRUE) else ""
Sys.setenv(R_LIBS_USER = lib, OMP_NUM_THREADS = "2",
    OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
# Incoming repository checks are network-dependent submission checks, not
# portability tests. Keep the rest of --as-cran, with all Suggests required.
Sys.setenv(`_R_CHECK_CRAN_INCOMING_REMOTE_` = "false",
    `_R_CHECK_FORCE_SUGGESTS_` = "true")
# Keep dependency libraries, but always install the package under test separately.
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
writeLines(c(capture.output(sessionInfo()), capture.output(Sys.info()),
    paste("source:", source_archive), paste("profile:", profile),
    paste("commit:", Sys.getenv("PACKAGE_TEST_COMMIT", "UNRECORDED")),
    paste("image:", Sys.getenv("PACKAGE_TEST_IMAGE", "native"))),
    file.path(out, "environment.txt"))
status <- data.frame(stage = character(), exit_code = integer())
record <- function(stage, code) {
    status[nrow(status) + 1L, ] <<- list(stage, as.integer(code))
    write.csv(status, file.path(out, "status.csv"), row.names = FALSE)
}
run <- function(stage, argv) {
    log <- file.path(out, paste0(stage, ".log"))
    code <- system2(r, argv, stdout = log, stderr = log)
    record(stage, code)
    code
}
setwd(out)
code <- run("install", c("CMD", "INSTALL", "--install-tests",
    paste0("--library=", shQuote(lib)), shQuote(source_archive)))
if (code != 0L) quit(status = 1L)
if (nzchar(smoke)) {
    Sys.setenv(PACKAGE_TEST_LIBRARY = lib, PACKAGE_TEST_PROFILE = profile)
    code <- run("smoke", c("--vanilla", "--slave", "-f", shQuote(smoke)))
    if (code != 0L) quit(status = 1L)
}
# --no-manual avoids requiring TeX on every host; vignettes/examples/tests run.
code <- run("check", c("CMD", "check", "--as-cran", "--no-manual",
    paste0("--library=", shQuote(lib)), shQuote(source_archive)))
checks <- list.files(out, "00check.log$", recursive = TRUE, full.names = TRUE)
if (length(checks) != 1L) {
    record("check_log", 1L)
    quit(status = 1L)
}
lines <- readLines(checks, warn = FALSE)
writeLines(tail(lines, 20L), file.path(out, "check-summary.txt"))
has_problem <- any(grepl("^Status:.*(ERROR|WARNING)", lines))
complete <- any(grepl("^\\* DONE", lines))
record("check_complete", as.integer(!complete))
record("check_errors_warnings", as.integer(has_problem))
quit(status = as.integer(code != 0L || has_problem || !complete))
