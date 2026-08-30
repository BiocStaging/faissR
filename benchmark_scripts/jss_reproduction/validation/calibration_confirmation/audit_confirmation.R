#!/usr/bin/env Rscript

median_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}

cv_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) > 1L && mean(x) > 0) stats::sd(x) / mean(x) else NA_real_
}

quantile_or_na <- function(x, probability) {
  x <- x[is.finite(x)]
  if (length(x)) unname(stats::quantile(x, probability)) else NA_real_
}

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else stop("Provide the confirmation root.")
manifest_dir <- if (length(args) >= 2L) args[[2L]] else stop("Provide the manifest directory.")
expected_repeats <- if (length(args) >= 3L) as.integer(args[[3L]]) else 5L
manifest_files <- file.path(manifest_dir, paste0("confirmation_", c("cpu", "cuda"), ".csv"))
if (!all(file.exists(manifest_files))) stop("CPU and CUDA confirmation manifests are required.")
manifests <- lapply(manifest_files, utils::read.csv, stringsAsFactors = FALSE,
                    check.names = FALSE)
manifest_columns <- unique(unlist(lapply(manifests, names), use.names = FALSE))
manifests <- lapply(manifests, function(x) {
  for (name in setdiff(manifest_columns, names(x))) x[[name]] <- NA
  x[, manifest_columns, drop = FALSE]
})
manifest <- do.call(rbind, manifests)
files <- list.files(
  root, pattern = "^jss_calibration_confirmation_raw[.]csv$",
  recursive = TRUE, full.names = TRUE
)
if (!length(files)) stop("No confirmation result files under ", root)
values <- lapply(files, utils::read.csv, stringsAsFactors = FALSE,
                 check.names = FALSE)
columns <- unique(unlist(lapply(values, names), use.names = FALSE))
values <- lapply(values, function(x) {
  for (name in setdiff(columns, names(x))) x[[name]] <- NA
  x[, columns, drop = FALSE]
})
raw <- do.call(rbind, values)
success <- raw[raw$status == "success" & is.finite(raw$elapsed_sec), , drop = FALSE]
failed_rows <- sum(raw$status != "success" | !is.finite(raw$elapsed_sec))
if (!nrow(success)) stop("No successful confirmation timing rows were produced.")
candidate_keys <- c("confirmation_cell_id", "dataset", "backend", "metric", "k",
                    "target_recall", "method", "candidate_id")
key_string <- function(x, columns) {
  do.call(paste, c(lapply(x[columns], as.character), sep = "\r"))
}
expected_candidate_keys <- unique(key_string(manifest, candidate_keys))
observed_candidate_keys <- unique(key_string(raw, candidate_keys))
missing_candidates <- setdiff(expected_candidate_keys, observed_candidate_keys)
unexpected_candidates <- setdiff(observed_candidate_keys, expected_candidate_keys)
timing_keys <- c(candidate_keys, "timing_repeat")
duplicate_timings <- sum(duplicated(key_string(raw, timing_keys)))
candidate_groups <- split(
  success,
  interaction(success[candidate_keys], drop = TRUE, lex.order = TRUE)
)
candidate_summary <- do.call(rbind, lapply(candidate_groups, function(x) {
  first <- x[1L, candidate_keys, drop = FALSE]
  cbind(
    first,
    screen_rank = x$screen_rank[[1L]],
    screen_elapsed_sec = x$screen_elapsed_sec[[1L]],
    completed_repeats = nrow(x),
    median_elapsed_sec = median_or_na(x$elapsed_sec),
    q1_elapsed_sec = unname(stats::quantile(x$elapsed_sec, 0.25)),
    q3_elapsed_sec = unname(stats::quantile(x$elapsed_sec, 0.75)),
    mad_elapsed_sec = stats::mad(x$elapsed_sec),
    timing_cv = cv_or_na(x$elapsed_sec),
    min_confirmed_recall = min(x$recall_at_k, na.rm = TRUE),
    exact_audited = all(x$exact %in% TRUE),
    target_eligible = all(x$exact %in% TRUE) ||
      all(is.finite(x$recall_at_k) & x$recall_at_k >= x$target_recall),
    stringsAsFactors = FALSE
  )
}))

incomplete_candidates <- sum(candidate_summary$completed_repeats != expected_repeats)

cell_groups <- split(
  candidate_summary,
  interaction(
    candidate_summary[c("backend", "confirmation_cell_id")],
    drop = TRUE, lex.order = TRUE
  ),
  drop = TRUE
)
cell_summary <- do.call(rbind, lapply(cell_groups, function(candidates) {
  eligible <- candidates[candidates$target_eligible, , drop = FALSE]
  if (!nrow(eligible)) {
    first <- candidates[1L, , drop = FALSE]
    return(data.frame(
      confirmation_cell_id = first$confirmation_cell_id,
      dataset = first$dataset, backend = first$backend, metric = first$metric,
      k = first$k, target_recall = first$target_recall,
      candidates_confirmed = nrow(candidates), candidates_eligible = 0L,
      robust_method = NA_character_, robust_candidate_id = NA_character_,
      screen_method = candidates$method[candidates$screen_rank == 1L][1L],
      screen_candidate_id = candidates$candidate_id[candidates$screen_rank == 1L][1L],
      screen_candidate_eligible = FALSE,
      configuration_agreement = FALSE, method_family_agreement = FALSE,
      robust_winner_frequency = NA_real_, robust_method_frequency = NA_real_,
      one_run_selection_regret = NA_real_, changed_but_within_5_percent = FALSE,
      robust_median_sec = NA_real_, screen_candidate_median_sec = NA_real_,
      robust_timing_cv = NA_real_, stringsAsFactors = FALSE
    ))
  }
  eligible <- eligible[order(
    eligible$median_elapsed_sec, -eligible$min_confirmed_recall,
    eligible$method, eligible$candidate_id
  ), , drop = FALSE]
  robust <- eligible[1L, , drop = FALSE]
  screen <- candidates[candidates$screen_rank == 1L, , drop = FALSE]
  if (!nrow(screen)) screen <- robust
  eligible_keys <- paste(eligible$method, eligible$candidate_id, sep = "\r")
  cell_raw <- success[
    success$backend == robust$backend &
      success$confirmation_cell_id == robust$confirmation_cell_id &
      paste(success$method, success$candidate_id, sep = "\r") %in% eligible_keys,
    , drop = FALSE
  ]
  replicate_groups <- split(cell_raw, cell_raw$timing_repeat)
  replicate_winners <- lapply(replicate_groups, function(x) {
    x[order(x$elapsed_sec, -x$recall_at_k, x$method, x$candidate_id), , drop = FALSE][1L, ]
  })
  winner_ids <- vapply(replicate_winners, function(x) as.character(x$candidate_id[[1L]]), character(1L))
  winner_methods <- vapply(replicate_winners, function(x) as.character(x$method[[1L]]), character(1L))
  screen_eligible <- isTRUE(screen$target_eligible[[1L]])
  regret <- if (screen_eligible) {
    screen$median_elapsed_sec[[1L]] / robust$median_elapsed_sec[[1L]]
  } else {
    NA_real_
  }
  data.frame(
    confirmation_cell_id = robust$confirmation_cell_id,
    dataset = robust$dataset, backend = robust$backend, metric = robust$metric,
    k = robust$k, target_recall = robust$target_recall,
    candidates_confirmed = nrow(candidates),
    candidates_eligible = nrow(eligible),
    robust_method = robust$method,
    robust_candidate_id = robust$candidate_id,
    screen_method = screen$method[[1L]],
    screen_candidate_id = screen$candidate_id[[1L]],
    screen_candidate_eligible = screen_eligible,
    configuration_agreement = identical(screen$candidate_id[[1L]], robust$candidate_id[[1L]]) &&
      identical(screen$method[[1L]], robust$method[[1L]]),
    method_family_agreement = identical(screen$method[[1L]], robust$method[[1L]]),
    robust_winner_frequency = mean(
      winner_ids == robust$candidate_id & winner_methods == robust$method
    ),
    robust_method_frequency = mean(winner_methods == robust$method),
    one_run_selection_regret = regret,
    changed_but_within_5_percent = !identical(screen$candidate_id[[1L]], robust$candidate_id[[1L]]) &&
      is.finite(regret) && regret <= 1.05,
    robust_median_sec = robust$median_elapsed_sec,
    screen_candidate_median_sec = screen$median_elapsed_sec[[1L]],
    robust_timing_cv = robust$timing_cv,
    stringsAsFactors = FALSE
  )
}))

summary <- do.call(rbind, lapply(split(cell_summary, cell_summary$backend), function(x) {
  data.frame(
    backend = x$backend[[1L]], cells = nrow(x),
    configuration_agreement = mean(x$configuration_agreement),
    method_family_agreement = mean(x$method_family_agreement),
    median_robust_winner_frequency = median_or_na(x$robust_winner_frequency),
    median_robust_method_frequency = median_or_na(x$robust_method_frequency),
    median_one_run_regret = median_or_na(x$one_run_selection_regret),
    q95_one_run_regret = quantile_or_na(x$one_run_selection_regret, 0.95),
    changed_but_within_5_percent = sum(x$changed_but_within_5_percent),
    median_robust_timing_cv = median_or_na(x$robust_timing_cv),
    stringsAsFactors = FALSE
  )
}))
dir.create(root, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(raw, file.path(root, "jss_calibration_confirmation_raw_combined.csv"), row.names = FALSE)
utils::write.csv(candidate_summary, file.path(root, "jss_calibration_confirmation_candidates.csv"), row.names = FALSE)
utils::write.csv(cell_summary, file.path(root, "jss_calibration_confirmation_cells.csv"), row.names = FALSE)
utils::write.csv(summary, file.path(root, "jss_calibration_confirmation_summary.csv"), row.names = FALSE)
report <- c(
  "# Replicated calibration confirmation", "",
  sprintf("Expected timing rows: %d.", nrow(manifest) * expected_repeats),
  sprintf("Observed timing rows: %d.", nrow(raw)),
  sprintf("Successful timing rows: %d.", nrow(success)),
  sprintf("Failed or incomplete timing rows: %d.", failed_rows),
  sprintf("Missing candidate configurations: %d.", length(missing_candidates)),
  sprintf("Unexpected candidate configurations: %d.", length(unexpected_candidates)),
  sprintf("Duplicate candidate-repeat rows: %d.", duplicate_timings),
  sprintf("Candidates without exactly %d successful repetitions: %d.",
          expected_repeats, incomplete_candidates),
  sprintf("Cells without a confirmed target-eligible candidate: %d.",
          sum(cell_summary$candidates_eligible == 0L)),
  sprintf("Candidate summaries: %d.", nrow(candidate_summary)),
  sprintf("Policy cells: %d.", nrow(cell_summary)), "",
  "The original wide grid is a screening stage. Plausible candidates were",
  sprintf("re-timed %d times in isolated workers and randomized execution order.",
          expected_repeats),
  "Selection uses median elapsed time with deterministic recall and identifier",
  "tie-breaking. The CSV files report configuration and method-family stability,",
  "timing dispersion, one-run selection regret, and immaterial near-tie switches."
)
writeLines(report, file.path(root, "JSS_CALIBRATION_CONFIRMATION_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
audit_failures <- c(
  failed_rows, length(missing_candidates), length(unexpected_candidates),
  duplicate_timings, incomplete_candidates,
  sum(cell_summary$candidates_eligible == 0L)
)
if (any(audit_failures > 0L)) quit(status = 1L)
