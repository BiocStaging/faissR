#!/usr/bin/env Rscript

`%||%` <- function(x, y) if (is.null(x) || !nzchar(x)) y else x

parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    value <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[value[[1L]]]] <- paste(value[-1L], collapse = "=")
  }
  out
}

sha256_file <- function(path) {
  command <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
  if (!nzchar(Sys.which(command))) stop("No SHA-256 implementation is available.")
  arguments <- if (command == "shasum") c("-a", "256", path) else path
  sub("[[:space:]].*$", "", system2(command, shQuote(arguments), stdout = TRUE)[[1L]])
}

expected_sha256 <- function(path) {
  value <- strsplit(trimws(readLines(path, warn = FALSE)[[1L]]), "[[:space:]]+")[[1L]][[1L]]
  if (!grepl("^[0-9a-fA-F]{64}$", value)) stop("Invalid SHA-256 ledger: ", path)
  tolower(value)
}

median_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}

quantile_or_na <- function(x, probability) {
  x <- x[is.finite(x)]
  if (length(x)) unname(stats::quantile(x, probability)) else NA_real_
}

summarize_group <- function(x) {
  eligible <- x$recall_equivalent %in% TRUE
  ratios <- x$time_ratio_comparator_over_faissR[eligible]
  data.frame(
    package = x$package[[1L]],
    comparison_class = x$comparison_class[[1L]],
    planned_pairs = nrow(x),
    both_successful = sum(x$both_successful),
    point_recall_matched = sum(eligible),
    comparator_timeouts = sum(x$status_comparator == "timeout"),
    comparator_failures = sum(x$status_comparator == "failed"),
    faissR_timeouts = sum(x$status_faissR == "timeout"),
    faissR_failures = sum(x$status_faissR == "failed"),
    median_ratio = median_or_na(ratios),
    q25_ratio = quantile_or_na(ratios, 0.25),
    q75_ratio = quantile_or_na(ratios, 0.75),
    stringsAsFactors = FALSE
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
script_path <- gsub("~+~", " ", script_path, fixed = TRUE)
script_dir <- dirname(normalizePath(script_path, mustWork = TRUE))
input <- args$input %||% file.path(
  script_dir, "comprehensive_r_comparison", "jss_comprehensive_r_pairs.csv.gz"
)
checksum <- args$checksum %||% paste0(input, ".sha256")
output <- args$output %||% file.path(script_dir, "fig_comprehensive_r_log_ratio.pdf")
summary_output <- args$summary %||% file.path(
  dirname(output), "jss_comprehensive_r_figure_data.csv"
)

input <- normalizePath(input, mustWork = TRUE)
checksum <- normalizePath(checksum, mustWork = TRUE)
if (!identical(tolower(sha256_file(input)), expected_sha256(checksum))) {
  stop("Comprehensive-comparison evidence failed SHA-256 verification.")
}

pairs <- utils::read.csv(gzfile(input), stringsAsFactors = FALSE, check.names = FALSE)
required <- c(
  "package", "comparison_class", "both_successful", "recall_equivalent",
  "time_ratio_comparator_over_faissR", "status_comparator", "status_faissR",
  "same_node"
)
missing <- setdiff(required, names(pairs))
if (length(missing)) stop("Missing paired-result columns: ", paste(missing, collapse = ", "))
if (nrow(pairs) != 4104L || !all(pairs$same_node)) {
  stop("The complete matched-node comparison audit did not pass.")
}
if (!setequal(unique(pairs$package), c(
  "BiocNeighbors", "FNN", "RANN", "RcppAnnoy", "RcppHNSW", "Rnanoflann", "rnndescent"
))) stop("Unexpected comparator package coverage.")

groups <- split(pairs, interaction(pairs$package, pairs$comparison_class, drop = TRUE))
summary <- do.call(rbind, lapply(groups, summarize_group))
summary$label <- paste(summary$package, summary$comparison_class, sep = ": ")
summary <- summary[order(summary$median_ratio, na.last = TRUE), , drop = FALSE]
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(summary, summary_output, row.names = FALSE, na = "")

grDevices::pdf(output, width = 7.2, height = 4.8, useDingbats = FALSE)
graphics::par(mar = c(4.2, 11.4, 0.7, 4.6), las = 1, xpd = NA)
y <- rev(seq_len(nrow(summary)))
graphics::plot(
  NA, NA, log = "x", xlim = c(0.18, 70), ylim = c(0.45, nrow(summary) + 0.55),
  axes = FALSE, xlab = expression(T[comparator] / T[faissR]), ylab = ""
)
graphics::abline(v = 1, lty = 2, col = "#666666")
graphics::abline(h = seq(1.5, nrow(summary) - 0.5, by = 1), col = "#E5E5E5", lwd = 0.7)
ticks <- c(0.2, 0.5, 1, 2, 5, 10, 20, 50)
graphics::axis(1, at = ticks, labels = ticks)
graphics::axis(2, at = y, labels = summary$label, tick = FALSE, cex.axis = 0.78)
graphics::box()
for (i in seq_len(nrow(summary))) {
  if (!is.finite(summary$median_ratio[[i]])) next
  graphics::segments(summary$q25_ratio[[i]], y[[i]], summary$q75_ratio[[i]], y[[i]],
                     col = "#333333", lwd = 1.6)
  graphics::points(summary$median_ratio[[i]], y[[i]], pch = 16, cex = 0.75)
  graphics::text(
    70, y[[i]],
    labels = paste0("n=", summary$point_recall_matched[[i]],
                    "; t=", summary$comparator_timeouts[[i]] + summary$faissR_timeouts[[i]]),
    adj = 0, cex = 0.62
  )
}
graphics::mtext("Comparator faster", side = 1, at = 0.32, line = 2.7, cex = 0.72, col = "#555555")
graphics::mtext("faissR faster", side = 1, at = 18, line = 2.7, cex = 0.72, col = "#555555")
grDevices::dev.off()
cat("Wrote ", output, " and ", summary_output, "\n", sep = "")
