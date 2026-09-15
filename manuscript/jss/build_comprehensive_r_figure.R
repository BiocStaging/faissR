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
  reference_routes <- unique(as.character(x$reference_route))
  if (length(reference_routes) != 1L) {
    stop("A comparison group contains more than one faissR reference route.")
  }
  eligible <- x$recall_equivalent %in% TRUE
  eligible_ratios <- x$time_ratio_comparator_over_faissR[eligible]
  eligible_datasets <- as.character(x$dataset[eligible])
  dataset_medians <- vapply(
    split(eligible_ratios, eligible_datasets),
    median_or_na,
    numeric(1L)
  )
  dataset_medians <- dataset_medians[is.finite(dataset_medians)]
  data.frame(
    package = x$package[[1L]],
    comparison_class = x$comparison_class[[1L]],
    reference_route = reference_routes[[1L]],
    datasets_planned = length(unique(x$dataset)),
    datasets_matched = length(dataset_medians),
    planned_pairs = nrow(x),
    both_successful = sum(x$both_successful),
    point_recall_matched = sum(eligible),
    comparator_timeouts = sum(x$status_comparator == "timeout"),
    comparator_failures = sum(x$status_comparator == "failed"),
    faissR_timeouts = sum(x$status_faissR == "timeout"),
    faissR_failures = sum(x$status_faissR == "failed"),
    median_ratio = median_or_na(dataset_medians),
    q25_ratio = quantile_or_na(dataset_medians, 0.25),
    q75_ratio = quantile_or_na(dataset_medians, 0.75),
    stringsAsFactors = FALSE
  )
}

summarize_dataset_group <- function(x) {
  reference_routes <- unique(as.character(x$reference_route))
  datasets <- unique(as.character(x$dataset))
  if (length(reference_routes) != 1L || length(datasets) != 1L) {
    stop("A dataset comparison group is not uniquely identified.")
  }
  eligible <- x$recall_equivalent %in% TRUE
  data.frame(
    dataset = datasets[[1L]],
    package = x$package[[1L]],
    comparison_class = x$comparison_class[[1L]],
    reference_route = reference_routes[[1L]],
    planned_pairs = nrow(x),
    point_recall_matched = sum(eligible),
    timeouts = sum(x$status_comparator == "timeout") +
      sum(x$status_faissR == "timeout"),
    median_ratio = median_or_na(
      x$time_ratio_comparator_over_faissR[eligible]
    ),
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
dataset_output <- args$dataset_summary %||% file.path(
  dirname(output), "jss_comprehensive_r_dataset_medians.csv"
)

input <- normalizePath(input, mustWork = TRUE)
checksum <- normalizePath(checksum, mustWork = TRUE)
if (!identical(tolower(sha256_file(input)), expected_sha256(checksum))) {
  stop("Comprehensive-comparison evidence failed SHA-256 verification.")
}

pairs <- utils::read.csv(gzfile(input), stringsAsFactors = FALSE, check.names = FALSE)
required <- c(
  "dataset", "package", "comparison_class", "both_successful", "recall_equivalent",
  "time_ratio_comparator_over_faissR", "status_comparator", "status_faissR",
  "same_node", "reference_route"
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
dataset_groups <- split(
  pairs,
  interaction(
    pairs$dataset, pairs$package, pairs$comparison_class,
    drop = TRUE
  )
)
dataset_summary <- do.call(
  rbind,
  lapply(dataset_groups, summarize_dataset_group)
)
external_method <- c(
  exact = "exact", hnsw = "HNSW", annoy = "Annoy",
  nndescent = "NN-descent"
)
faissr_method <- c(
  faissR_exact = "exact", faissR_hnsw = "HNSW",
  faissR_auto = "auto", faissR_nndescent = "nndescent_style"
)
comparison_scope <- c(
  exact = "same_family",
  hnsw = "same_family",
  annoy = "task_level_alternative",
  nndescent = "experimental_derived"
)
if (anyNA(external_method[summary$comparison_class]) ||
    anyNA(faissr_method[summary$reference_route]) ||
    anyNA(comparison_scope[summary$comparison_class])) {
  stop("Cannot construct an explicit comparator-to-faissR route label.")
}
summary$comparison_scope <- unname(
  comparison_scope[summary$comparison_class]
)
dataset_summary$comparison_scope <- unname(
  comparison_scope[dataset_summary$comparison_class]
)
summary$label <- paste(
  summary$package,
  unname(external_method[summary$comparison_class]),
  "/",
  unname(faissr_method[summary$reference_route])
)
scope_suffix <- c(
  same_family = "",
  task_level_alternative = " [task-level]",
  experimental_derived = " [experimental]"
)
summary$label <- paste0(
  summary$label,
  unname(scope_suffix[summary$comparison_scope])
)
scope_rank <- c(
  same_family = 1L,
  task_level_alternative = 2L,
  experimental_derived = 3L
)
summary <- summary[
  order(scope_rank[summary$comparison_scope], summary$median_ratio,
        na.last = TRUE),
  , drop = FALSE
]
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(summary, summary_output, row.names = FALSE, na = "")
dataset_summary <- dataset_summary[
  order(dataset_summary$package, dataset_summary$comparison_class,
        dataset_summary$dataset),
  , drop = FALSE
]
utils::write.csv(dataset_summary, dataset_output, row.names = FALSE, na = "")

plot_labels <- summary$label
long_label <- nchar(plot_labels) > 34L
plot_labels[long_label] <- sub(" / ", "\n/ ", plot_labels[long_label],
                               fixed = TRUE)

grDevices::pdf(output, width = 7.2, height = 4.8, useDingbats = FALSE)
graphics::par(mar = c(4.2, 12.8, 0.7, 1.0), las = 1, xpd = FALSE)
y <- rev(seq_len(nrow(summary)))
graphics::plot(
  NA, NA, log = "x", xlim = c(0.18, 300), ylim = c(0.45, nrow(summary) + 0.55),
  axes = FALSE, xlab = "", ylab = ""
)
graphics::abline(v = 1, lty = 2, col = "#666666")
graphics::abline(h = seq(1.5, nrow(summary) - 0.5, by = 1), col = "#E5E5E5", lwd = 0.7)
scope_boundaries <- which(
  summary$comparison_scope[-1L] !=
    summary$comparison_scope[-nrow(summary)]
)
if (length(scope_boundaries)) {
  graphics::abline(
    h = nrow(summary) - scope_boundaries + 0.5,
    col = "#777777",
    lwd = 1.1
  )
}
ticks <- c(0.2, 0.5, 1, 2, 5, 10, 20, 50)
graphics::axis(1, at = ticks, labels = ticks)
graphics::axis(2, at = y, labels = plot_labels, tick = FALSE, cex.axis = 0.78)
graphics::box()
for (i in seq_len(nrow(summary))) {
  if (!is.finite(summary$median_ratio[[i]])) next
  dataset_rows <- dataset_summary[
    dataset_summary$package == summary$package[[i]] &
      dataset_summary$comparison_class == summary$comparison_class[[i]] &
      is.finite(dataset_summary$median_ratio),
    , drop = FALSE
  ]
  graphics::points(
    dataset_rows$median_ratio, rep(y[[i]], nrow(dataset_rows)),
    pch = 1, cex = 0.62, col = "#777777"
  )
  graphics::segments(summary$q25_ratio[[i]], y[[i]], summary$q75_ratio[[i]], y[[i]],
                     col = "#333333", lwd = 1.6)
  graphics::points(summary$median_ratio[[i]], y[[i]], pch = 16, cex = 0.75)
  graphics::text(
    270, y[[i]],
    labels = paste0("n=", summary$point_recall_matched[[i]],
                    "; d=", summary$datasets_matched[[i]],
                    "; t=", summary$comparator_timeouts[[i]] + summary$faissR_timeouts[[i]]),
    adj = 1, cex = 0.62
  )
}
graphics::mtext("Comparator faster", side = 1, at = 0.32, line = 2.0,
                cex = 0.72, col = "#555555")
graphics::mtext("faissR faster", side = 1, at = 18, line = 2.0,
                cex = 0.72, col = "#555555")
graphics::mtext(expression(T[comparator] / T[faissR]), side = 1, line = 3.1)
grDevices::dev.off()
cat(
  "Wrote ", output, ", ", summary_output, " and ", dataset_output, "\n",
  sep = ""
)
