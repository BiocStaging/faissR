#!/usr/bin/env Rscript

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  required <- c("loodo", "method_summary", "out_dir")
  missing <- setdiff(required, names(out))
  if (length(missing)) stop("Missing arguments: ", paste(missing, collapse = ", "))
  out
}

finite_quantile <- function(x, probability) {
  x <- x[is.finite(x)]
  if (length(x)) unname(stats::quantile(x, probability)) else NA_real_
}

summarize_policy <- function(x) {
  ratio <- x$feasible_route_regret[is.finite(x$feasible_route_regret)]
  approximate <- x$selected_approximate %in% TRUE
  data.frame(
    policy = x$policy[[1L]],
    workload = x$workload[[1L]],
    cells = nrow(x),
    evaluable_cells = length(ratio),
    median_regret = stats::median(ratio),
    q75_regret = finite_quantile(ratio, 0.75),
    q90_regret = finite_quantile(ratio, 0.90),
    q95_regret = finite_quantile(ratio, 0.95),
    maximum_regret = max(ratio),
    fraction_within_5_percent = mean(ratio <= 1.05),
    fraction_within_10_percent = mean(ratio <= 1.10),
    fraction_within_25_percent = mean(ratio <= 1.25),
    fraction_within_2_fold = mean(ratio <= 2.00),
    fraction_selecting_exact = mean(x$selected_exact_audited %in% TRUE),
    approximate_cells = sum(approximate),
    approximate_faster_than_exact_cells = sum(
      approximate & x$selected_faster_than_explicit_exact %in% TRUE
    ),
    fraction_approximate_faster_than_exact_all_cells = mean(
      approximate & x$selected_faster_than_explicit_exact %in% TRUE
    ),
    fraction_approximate_faster_than_exact_conditional = if (any(approximate)) {
      mean(x$selected_faster_than_explicit_exact[approximate] %in% TRUE)
    } else {
      NA_real_
    },
    median_seconds_saved_vs_exact = stats::median(x$seconds_saved_vs_exact),
    positive_seconds_saved_vs_exact = sum(pmax(x$seconds_saved_vs_exact, 0)),
    seconds_lost_vs_exact = sum(pmax(-x$seconds_saved_vs_exact, 0)),
    net_seconds_saved_vs_exact = sum(x$seconds_saved_vs_exact),
    successful_runs = sum(x$n_success),
    failed_runs = sum(x$n_failed),
    timeout_runs = sum(x$n_timeout),
    out_of_memory_runs = sum(x$n_out_of_memory),
    expected_runs = sum(x$expected_runs),
    stringsAsFactors = FALSE
  )
}

summarize_stratum <- function(x, variable) {
  groups <- split(x, as.character(x[[variable]]), drop = TRUE)
  do.call(rbind, lapply(groups, function(z) {
    ratio <- z$feasible_route_regret[is.finite(z$feasible_route_regret)]
    data.frame(
      policy = z$policy[[1L]], workload = z$workload[[1L]],
      stratum = variable, level = as.character(z[[variable]][[1L]]),
      cells = nrow(z), evaluable_cells = length(ratio),
      median_regret = stats::median(ratio),
      q90_regret = finite_quantile(ratio, 0.90),
      maximum_regret = max(ratio),
      fraction_within_10_percent = mean(ratio <= 1.10),
      fraction_selecting_exact = mean(z$selected_exact_audited %in% TRUE),
      approximate_cells = sum(z$selected_approximate %in% TRUE),
      approximate_faster_than_exact_cells = sum(
        z$selected_approximate %in% TRUE &
          z$selected_faster_than_explicit_exact %in% TRUE
      ),
      net_seconds_saved_vs_exact = sum(z$seconds_saved_vs_exact),
      stringsAsFactors = FALSE
    )
  }))
}

args <- parse_args()
loodo <- utils::read.csv(args$loodo, stringsAsFactors = FALSE, check.names = FALSE)
methods <- utils::read.csv(args$method_summary, stringsAsFactors = FALSE,
                           check.names = FALSE)
loodo <- loodo[loodo$backend == "cuda", , drop = FALSE]
keys <- c("dataset", "dataset_md5", "backend", "metric", "k", "target_recall")

exact <- methods[
  methods$backend == "cuda" & methods$method_id == "faissR_cuda_exact",
  c(keys, "median_time_sec"), drop = FALSE
]
names(exact)[names(exact) == "median_time_sec"] <- "explicit_exact_time_sec"

make_policy <- function(policy) {
  if (identical(policy, "installed")) {
    selected <- data.frame(
      loodo[keys], policy = "installed",
      selected_method = loodo$package_auto_method,
      selected_route_family = loodo$package_auto_resolved_route_family,
      selected_time_sec = loodo$package_auto_time_sec,
      selected_exact_audited = loodo$package_auto_exact_selected,
      selected_operating_point_met = loodo$package_auto_operating_point_met,
      selected_abstained = loodo$package_auto_abstained,
      selected_over_fastest_explicit_route = loodo$package_auto_over_oracle,
      oracle_method = loodo$oracle_method,
      oracle_route_family = loodo$oracle_resolved_route_family,
      oracle_time_sec = loodo$oracle_time_sec,
      stringsAsFactors = FALSE
    )
  } else {
    selected <- data.frame(
      loodo[keys], policy = "cross_fitted",
      selected_method = loodo$crossfit_test_method,
      selected_route_family = loodo$crossfit_resolved_route_family,
      selected_time_sec = loodo$crossfit_time_sec,
      selected_exact_audited = loodo$crossfit_exact_selected,
      selected_operating_point_met = loodo$crossfit_operating_point_met,
      selected_abstained = loodo$crossfit_abstained,
      selected_over_fastest_explicit_route = loodo$crossfit_over_oracle,
      oracle_method = loodo$oracle_method,
      oracle_route_family = loodo$oracle_resolved_route_family,
      oracle_time_sec = loodo$oracle_time_sec,
      stringsAsFactors = FALSE
    )
  }
  selected <- merge(selected, exact, by = keys, all.x = TRUE, sort = FALSE)
  selected$workload <- "cold_full_self_search"
  selected$query_rows <- loodo$n[match(
    do.call(paste, c(selected[keys], sep = "\r")),
    do.call(paste, c(loodo[keys], sep = "\r"))
  )]
  selected$selected_approximate <- !selected$selected_exact_audited
  selected$selected_faster_than_explicit_exact <-
    selected$selected_time_sec < selected$explicit_exact_time_sec
  selected$seconds_saved_vs_exact <-
    selected$explicit_exact_time_sec - selected$selected_time_sec
  selected$fastest_feasible_route_time_sec <- pmin(
    selected$selected_time_sec, selected$oracle_time_sec, na.rm = TRUE
  )
  selected$feasible_route_regret <-
    selected$selected_time_sec / selected$fastest_feasible_route_time_sec

  execution <- methods[c(
    keys, "method_id", "n_success", "n_failed", "n_timeout",
    "n_out_of_memory", "expected_runs", "complete_validation"
  )]
  names(execution)[names(execution) == "method_id"] <- "selected_method"
  selected <- merge(
    selected, execution, by = c(keys, "selected_method"),
    all.x = TRUE, sort = FALSE
  )
  selected
}

cells <- rbind(make_policy("installed"), make_policy("cross_fitted"))
if (any(!is.finite(cells$feasible_route_regret))) {
  stop("Every selector cell must have a finite feasible-route regret.")
}
if (any(!is.finite(cells$n_success))) {
  stop("Selected-route execution accounting is incomplete.")
}

policy_summary <- do.call(rbind, lapply(split(cells, cells$policy), summarize_policy))
strata <- do.call(rbind, lapply(split(cells, cells$policy), function(x) {
  do.call(rbind, lapply(
    c("dataset", "metric", "k", "target_recall", "workload"),
    function(variable) summarize_stratum(x, variable)
  ))
}))
route_choices <- aggregate(
  rep(1L, nrow(cells)),
  cells[c("policy", "workload", "dataset", "metric", "k", "target_recall",
          "selected_route_family", "selected_exact_audited")],
  sum
)
names(route_choices)[ncol(route_choices)] <- "cells"

dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(cells, file.path(args$out_dir, "jss_selector_regret_cells.csv"),
                 row.names = FALSE)
utils::write.csv(policy_summary,
                 file.path(args$out_dir, "jss_selector_regret_summary.csv"),
                 row.names = FALSE)
utils::write.csv(strata,
                 file.path(args$out_dir, "jss_selector_regret_by_stratum.csv"),
                 row.names = FALSE)
utils::write.csv(route_choices,
                 file.path(args$out_dir, "jss_selector_route_choices.csv"),
                 row.names = FALSE)

report <- c(
  "# Feasible-route regret analysis", "",
  "Regret is selected-route elapsed time divided by the fastest target-attaining",
  "empirical-route elapsed time, including the selected route itself, in the same dataset, metric,",
  "k, target, and cold full-self-search cell. Exact-audited routes are eligible",
  "by exhaustive audit; approximate routes must attain the requested mean",
  "query recall in every validation replicate.", "",
  capture.output(print(policy_summary, row.names = FALSE))
)
writeLines(report, file.path(args$out_dir, "JSS_SELECTOR_REGRET_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
