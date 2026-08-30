#!/usr/bin/env Rscript

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list(cap_sec = "2000", tau_max = "100", tau_points = "160")
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  required <- c("summary", "out_dir")
  missing <- setdiff(required, names(out))
  if (length(missing)) stop("Missing arguments: ", paste(missing, collapse = ", "))
  out
}

finite_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) min(x) else NA_real_
}

args <- parse_args()
input <- utils::read.csv(args$summary, stringsAsFactors = FALSE, check.names = FALSE)
required <- c(
  "dataset", "backend", "metric", "k", "target_recall", "method_id",
  "median_time_sec", "complete_validation", "selection_eligible", "n_timeout",
  "n_out_of_memory", "n_failed", "expected_runs"
)
missing <- setdiff(required, names(input))
if (length(missing)) stop("Summary lacks: ", paste(missing, collapse = ", "))

keys <- c("dataset", "backend", "metric", "k", "target_recall")
input$observed_success <- input$complete_validation %in% TRUE &
  input$selection_eligible %in% TRUE & is.finite(input$median_time_sec)
cell <- interaction(input[keys], drop = TRUE, lex.order = TRUE)
best <- vapply(split(input$median_time_sec[input$observed_success], cell[input$observed_success]), finite_min, numeric(1L))
input$cell_key <- as.character(cell)
input$best_eligible_sec <- unname(best[input$cell_key])
input$performance_ratio <- ifelse(
  input$observed_success,
  input$median_time_sec / input$best_eligible_sec,
  Inf
)
cap_sec <- as.numeric(args$cap_sec)
input$capped_elapsed_sec <- ifelse(input$observed_success, input$median_time_sec, cap_sec)
input$capped_ratio <- input$capped_elapsed_sec / input$best_eligible_sec

tau <- exp(seq(log(1), log(as.numeric(args$tau_max)), length.out = as.integer(args$tau_points)))
method_groups <- split(input, interaction(input[c("backend", "method_id")], drop = TRUE))
profile <- do.call(rbind, lapply(method_groups, function(x) {
  data.frame(
    backend = x$backend[[1L]], method_id = x$method_id[[1L]], tau = tau,
    fraction_solved = vapply(tau, function(z) mean(x$performance_ratio <= z), numeric(1L)),
    fraction_within_capped_ratio = vapply(tau, function(z) mean(x$capped_ratio <= z), numeric(1L)),
    cells = nrow(x), successful_eligible_cells = sum(x$observed_success),
    timeout_runs = sum(x$n_timeout), out_of_memory_runs = sum(x$n_out_of_memory),
    failed_runs = sum(x$n_failed), expected_runs = sum(x$expected_runs),
    stringsAsFactors = FALSE
  )
}))

summary <- do.call(rbind, lapply(method_groups, function(x) {
  ratios <- x$performance_ratio[is.finite(x$performance_ratio)]
  data.frame(
    backend = x$backend[[1L]], method_id = x$method_id[[1L]], cells = nrow(x),
    successful_eligible_cells = sum(x$observed_success),
    completion_fraction = mean(x$observed_success),
    fraction_within_1_05 = mean(x$performance_ratio <= 1.05),
    fraction_within_1_25 = mean(x$performance_ratio <= 1.25),
    fraction_within_2 = mean(x$performance_ratio <= 2),
    median_ratio_successful = if (length(ratios)) median(ratios) else NA_real_,
    q90_ratio_successful = if (length(ratios)) unname(quantile(ratios, 0.90)) else NA_real_,
    timeout_runs = sum(x$n_timeout), out_of_memory_runs = sum(x$n_out_of_memory),
    failed_runs = sum(x$n_failed), expected_runs = sum(x$expected_runs),
    cap_sec = cap_sec, stringsAsFactors = FALSE
  )
}))

dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(input, file.path(args$out_dir, "jss_failure_aware_cells.csv"), row.names = FALSE)
utils::write.csv(profile, file.path(args$out_dir, "jss_failure_aware_profile.csv"), row.names = FALSE)
utils::write.csv(summary, file.path(args$out_dir, "jss_failure_aware_summary.csv"), row.names = FALSE)

pdf(file.path(args$out_dir, "jss_failure_aware_performance_profile.pdf"), width = 8, height = 5.5)
for (backend in unique(profile$backend)) {
  part <- profile[profile$backend == backend, , drop = FALSE]
  methods <- unique(part$method_id)
  palette <- grDevices::hcl.colors(length(methods), "Dark 3")
  plot(NA, xlim = range(log10(tau)), ylim = c(0, 1), xlab = "log10 performance ratio",
       ylab = "Fraction of all operating cells solved", main = paste(backend, "failure-aware profile"))
  grid()
  for (i in seq_along(methods)) {
    z <- part[part$method_id == methods[[i]], ]
    lines(log10(z$tau), z$fraction_solved, col = palette[[i]], lwd = 2)
  }
  legend("bottomright", legend = methods, col = palette, lwd = 2, cex = 0.7, bty = "n")
}
dev.off()

report <- c(
  "# Failure-aware performance profiles", "",
  "The denominator is every planned dataset x metric x k x requested-tier cell",
  "for each method. A cell is solved only when validation is complete, the route",
  "is quality-eligible, and its median elapsed time is finite. Timeouts, OOMs,",
  "unsupported outcomes, and other failures therefore remain unsolved (infinite",
  "performance ratio) rather than disappearing from conditional medians.", "",
  sprintf("The separate capped-runtime sensitivity assigns %.1f seconds to an unsolved cell.", cap_sec),
  "That cap is a prespecified sensitivity analysis and is not interpreted as an",
  "observed completion time.", "", capture.output(print(summary, row.names = FALSE))
)
writeLines(report, file.path(args$out_dir, "JSS_FAILURE_AWARE_PROFILE_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
