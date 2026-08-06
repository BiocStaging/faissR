#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list(phase = "list", dry_run = FALSE)
  i <- 1L
  while (i <= length(x)) {
    if (identical(x[[i]], "--dry-run")) {
      out$dry_run <- TRUE
      i <- i + 1L
    } else if (identical(x[[i]], "--phase") && i < length(x)) {
      out$phase <- x[[i + 1L]]
      i <- i + 2L
    } else if (startsWith(x[[i]], "--phase=")) {
      out$phase <- sub("^--phase=", "", x[[i]])
      i <- i + 1L
    } else {
      stop("Unknown argument: ", x[[i]], call. = FALSE)
    }
  }
  out
}

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) return(normalizePath(getwd(), mustWork = TRUE))
  normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
}

shell_capture <- function(command) {
  value <- system(command, intern = TRUE, ignore.stderr = FALSE)
  status <- attr(value, "status")
  if (!is.null(status) && status != 0L) {
    stop("Command failed: ", command, call. = FALSE)
  }
  paste(value, collapse = "\n")
}

phase_launchers <- function(campaign_dir, phase) {
  directory_scripts <- function(name) {
    sort(list.files(
      file.path(campaign_dir, name), pattern = "[.]sh$",
      recursive = TRUE, full.names = TRUE
    ))
  }
  analysis_script <- function(name) {
    file.path(campaign_dir, "analysis", name)
  }

  switch(
    phase,
    qa = directory_scripts("qa"),
    references = directory_scripts("references"),
    calibration = directory_scripts("calibration"),
    calibration_audit = analysis_script("run_calibration_audit_cpu12.sh"),
    held_out = directory_scripts("held_out"),
    diagnostics = c(
      directory_scripts("reusable_external"),
      directory_scripts("ablations"),
      analysis_script("run_metric_conformance_cpu12.sh"),
      analysis_script("run_metric_conformance_cuda.sh")
    ),
    aggregate = c(
      analysis_script("run_held_out_analysis_cpu12.sh"),
      analysis_script("run_held_out_analysis_cuda.sh"),
      analysis_script("run_ablation_audit_cpu12.sh"),
      analysis_script("run_reusable_external_audit_cpu12.sh")
    ),
    freeze = c(
      analysis_script("run_freeze_audit_cpu12.sh"),
      analysis_script("run_freeze_audit_cuda.sh")
    ),
    stop("Unknown phase: ", phase, call. = FALSE)
  )
}

phase_contract <- function() {
  data.frame(
    order = seq_len(8L),
    phase = c(
      "qa", "references", "calibration", "calibration_audit",
      "held_out", "diagnostics", "aggregate", "freeze"
    ),
    expected_jobs = c(2L, 5L, 105L, 1L, 142L, 16L, 4L, 2L),
    proceed_when = c(
      "both route-QA reports pass",
      "QA is complete",
      "all exact references pass identity and CPU audit",
      "calibration jobs are complete",
      "calibration audit passes and compiled policies remain frozen",
      "held-out jobs are complete",
      "held-out and diagnostic evidence is complete",
      "all aggregate reports pass"
    ),
    stringsAsFactors = FALSE
  )
}

preflight_image <- function(image, expected_version) {
  if (!file.exists(image)) {
    stop("Singularity image does not exist: ", image, call. = FALSE)
  }
  if (!nzchar(Sys.which("singularity"))) {
    stop("`singularity` is not available on PATH.", call. = FALSE)
  }
  version_command <- paste(
    "singularity exec --cleanenv", shQuote(image),
    "Rscript -e",
    shQuote("cat(as.character(utils::packageVersion('faissR')))"),
    sep = " "
  )
  commit_command <- paste(
    "singularity exec --cleanenv", shQuote(image),
    "/bin/sh -c",
    shQuote("printf '%s' \"${FAISSR_IMAGE_COMMIT:-}\""),
    sep = " "
  )
  version <- trimws(shell_capture(version_command))
  commit <- trimws(shell_capture(commit_command))
  if (!identical(version, expected_version)) {
    stop(
      "Expected faissR ", expected_version,
      " but the image contains ", version, ".",
      call. = FALSE
    )
  }
  if (!grepl("^[[:xdigit:]]{40}$", commit)) {
    stop("The image lacks a canonical FAISSR_IMAGE_COMMIT.", call. = FALSE)
  }
  list(version = version, commit = tolower(commit))
}

submit_phase <- function(
    phase, dry_run = FALSE, preflight = preflight_image, submitter = NULL) {
  campaign_dir <- dirname(script_path())
  contract <- phase_contract()
  if (identical(phase, "list")) {
    print(contract, row.names = FALSE)
    return(invisible(contract))
  }
  if (!phase %in% contract$phase) {
    stop(
      "`--phase` must be one of: list, ",
      paste(contract$phase, collapse = ", "), ".",
      call. = FALSE
    )
  }

  launchers <- phase_launchers(campaign_dir, phase)
  expected_jobs <- contract$expected_jobs[match(phase, contract$phase)]
  if (length(launchers) != expected_jobs || any(!file.exists(launchers))) {
    stop(
      "Phase `", phase, "` expected ", expected_jobs,
      " launchers but found ", sum(file.exists(launchers)), ".",
      call. = FALSE
    )
  }

  base_dir <- Sys.getenv("BASE_DIR", unset = "/scratch/firenze/NN")
  image <- Sys.getenv(
    "SINGULARITY_IMAGE",
    unset = file.path(
      base_dir, "singularity", "fastembedr_cuda_faissR_0.99.20.sif"
    )
  )
  expected_version <- Sys.getenv(
    "EXPECTED_FAISSR_VERSION", unset = "0.99.20"
  )

  if (dry_run) {
    commit <- Sys.getenv(
      "FAISSR_PACKAGE_COMMIT",
      unset = "<commit-read-from-image-during-live-submission>"
    )
  } else {
    identity <- preflight(image, expected_version)
    commit <- identity$commit
    Sys.setenv(
      SINGULARITY_IMAGE = image,
      EXPECTED_FAISSR_VERSION = expected_version,
      FAISSR_PACKAGE_COMMIT = commit
    )
  }

  suite_root <- dirname(dirname(dirname(campaign_dir)))
  relative <- substring(launchers, nchar(suite_root) + 2L)
  commands <- sprintf(
    "sbatch --export=ALL,FAISSR_PACKAGE_COMMIT=%s %s",
    commit, shQuote(launchers)
  )
  if (dry_run) {
    cat(paste(commands, collapse = "\n"), "\n", sep = "")
    return(invisible(commands))
  }
  if (is.null(submitter)) {
    if (!nzchar(Sys.which("sbatch"))) {
      stop("`sbatch` is not available on PATH.", call. = FALSE)
    }
    submitter <- system2
  }

  log_dir <- file.path(
    base_dir, "faissR_JMLR_MLOSS", "final_campaign", "submissions"
  )
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_path <- file.path(
    log_dir,
    sprintf(
      "%s_%s_pid%s.csv", phase,
      format(Sys.time(), tz = "UTC", format = "%Y%m%d_%H%M%S"),
      Sys.getpid()
    )
  )
  write_ledger <- function(rows) {
    write.csv(do.call(rbind, rows), log_path, row.names = FALSE)
  }

  records <- vector("list", length(launchers))
  for (i in seq_along(launchers)) {
    output <- submitter(
      "sbatch",
      c(
        "--parsable",
        paste0("--export=ALL,FAISSR_PACKAGE_COMMIT=", commit),
        launchers[[i]]
      ),
      stdout = TRUE,
      stderr = TRUE
    )
    status <- attr(output, "status")
    parsed_job_id <- if (length(output)) {
      sub(";.*$", "", trimws(output[[1L]]))
    } else {
      ""
    }
    submission_failed <- (!is.null(status) && status != 0L) ||
      !grepl("^[0-9]+$", parsed_job_id)
    if (submission_failed) {
      failure_output <- if (length(output)) {
        paste(output, collapse = "\n")
      } else {
        "sbatch returned no parsable job identifier"
      }
      records[[i]] <- data.frame(
        phase = phase,
        launcher = relative[[i]],
        job_id = NA_character_,
        submission_status = "failed",
        submission_output = failure_output,
        image = image,
        faissR_version = expected_version,
        faissR_commit = commit,
        submitted_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
        stringsAsFactors = FALSE
      )
      write_ledger(records[seq_len(i)])
      stop(
        "Submission failed after ", i - 1L, " jobs: ",
        failure_output, "\nSubmission ledger: ", log_path,
        call. = FALSE
      )
    }
    records[[i]] <- data.frame(
      phase = phase,
      launcher = relative[[i]],
      job_id = parsed_job_id,
      submission_status = "submitted",
      submission_output = paste(output, collapse = "\n"),
      image = image,
      faissR_version = expected_version,
      faissR_commit = commit,
      submitted_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      stringsAsFactors = FALSE
    )
    write_ledger(records[seq_len(i)])
    cat(sprintf("[%d/%d] %s\n", i, length(launchers), output[[1L]]))
  }

  records <- do.call(rbind, records)
  cat("Submission ledger: ", log_path, "\n", sep = "")
  invisible(records)
}

if (!identical(Sys.getenv("FAISSR_JSS_SOURCE_ONLY"), "true")) {
  args <- parse_args(commandArgs(trailingOnly = TRUE))
  submit_phase(args$phase, args$dry_run)
}
