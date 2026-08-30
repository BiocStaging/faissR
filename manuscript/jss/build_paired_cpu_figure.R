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
  if (requireNamespace("openssl", quietly = TRUE)) {
    con <- file(path, open = "rb")
    on.exit(close(con))
    return(paste0(as.character(openssl::sha256(con))))
  }
  command <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
  if (!nzchar(Sys.which(command))) stop("No SHA-256 implementation is available.")
  command_args <- if (command == "shasum") c("-a", "256", path) else path
  sub("[[:space:]].*$", "", system2(command, command_args, stdout = TRUE)[[1L]])
}

read_expected_sha256 <- function(path) {
  line <- readLines(path, warn = FALSE)[[1L]]
  value <- tolower(strsplit(trimws(line), "[[:space:]]+")[[1L]][[1L]])
  if (!grepl("^[0-9a-f]{64}$", value)) stop("Invalid SHA-256 ledger: ", path)
  value
}

summarize_group <- function(z) {
  eligible <- z$cold_recall_equivalent %in% TRUE
  ratios <- z$cold_speed_ratio[eligible & is.finite(z$cold_speed_ratio)]
  data.frame(
    dataset = z$dataset[[1L]], comparator = z$comparator[[1L]],
    planned_pairs = nrow(z), completed_pairs = sum(z$pair_complete, na.rm = TRUE),
    target_equivalent_pairs = length(ratios),
    comparator_timeouts = sum(z$status_comparator == "timeout", na.rm = TRUE),
    median_ratio = if (length(ratios)) stats::median(ratios) else NA_real_,
    q1_ratio = if (length(ratios)) unname(stats::quantile(ratios, 0.25)) else NA_real_,
    q3_ratio = if (length(ratios)) unname(stats::quantile(ratios, 0.75)) else NA_real_,
    stringsAsFactors = FALSE
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
explicit_script <- Sys.getenv("FAISSR_JSS_FIGURE_SCRIPT", unset = "")
script <- if (nzchar(explicit_script)) {
  explicit_script
} else if (length(script_arg)) {
  sub("^--file=", "", script_arg[[1L]])
} else {
  "."
}
# Some macOS R launchers encode spaces in --file paths this way.
script <- gsub("~+~", " ", script, fixed = TRUE)
script_dir <- dirname(normalizePath(script, mustWork = TRUE))
input <- args$input %||% file.path(
  script_dir, "paired_cpu_comparison", "jss_paired_hnsw_pairs.csv.gz"
)
checksum <- args$checksum %||% paste0(input, ".sha256")
output <- args$output %||% file.path(script_dir, "fig_paired_cpu_log_ratio.pdf")
summary_output <- args$summary %||% file.path(
  dirname(output), "jss_paired_cpu_figure_data.csv"
)

input <- normalizePath(input, mustWork = TRUE)
checksum <- normalizePath(checksum, mustWork = TRUE)
if (!identical(tolower(sha256_file(input)), read_expected_sha256(checksum))) {
  stop("Paired CPU evidence failed SHA-256 verification.")
}

pairs <- utils::read.csv(gzfile(input), stringsAsFactors = FALSE, check.names = FALSE)
required <- c(
  "dataset", "comparator", "pair_complete", "cold_speed_ratio",
  "cold_recall_equivalent", "status_comparator", "same_node",
  "same_allocation", "opposite_order_positions"
)
missing <- setdiff(required, names(pairs))
if (length(missing)) stop("Missing paired-result columns: ", paste(missing, collapse = ", "))
if (nrow(pairs) != 720L || !all(pairs$same_node) ||
    !all(pairs$same_allocation) || !all(pairs$opposite_order_positions)) {
  stop("The controlled-pair design audit did not pass.")
}
if (sum(pairs$status_comparator == "timeout", na.rm = TRUE) != 29L) {
  stop("Unexpected comparator timeout count.")
}

groups <- split(pairs, interaction(pairs$dataset, pairs$comparator, drop = TRUE))
figure_data <- do.call(rbind, lapply(groups, summarize_group))
figure_data$dataset[figure_data$dataset == "FlowRepository_FR-FCM-ZYRM_files"] <-
  "FR-FCM-ZYRM"
figure_data$dataset[figure_data$dataset == "imagenet"] <- "ImageNet features"
figure_data$comparator <- sub("_hnsw$", "", figure_data$comparator)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(figure_data, summary_output, row.names = FALSE, na = "")

dataset_order <- c(
  "COIL20", "FashionMNIST", "FR-FCM-ZYRM", "flow18",
  "ImageNet features", "mass41", "MetRef", "MNIST", "USPS"
)
comparators <- c("BiocNeighbors", "RcppHNSW")
colors <- c(BiocNeighbors = "#111111", RcppHNSW = "#666666")
symbols <- c(BiocNeighbors = 16L, RcppHNSW = 17L)
offsets <- c(BiocNeighbors = 0.14, RcppHNSW = -0.14)

grDevices::pdf(output, width = 7.2, height = 5.2, useDingbats = FALSE)
graphics::par(mar = c(4.2, 9.2, 0.8, 4.5), las = 1, xpd = NA)
y <- rev(seq_along(dataset_order))
graphics::plot(
  NA, NA, log = "x", xlim = c(0.45, 48), ylim = c(0.45, 9.55),
  axes = FALSE, xlab = expression(T[comparator] / T[faissR]), ylab = ""
)
graphics::abline(v = 1, lty = 2, col = "#777777")
graphics::abline(h = seq(1.5, 8.5, by = 1), col = "#EEEEEE", lwd = 0.7)
ticks <- c(0.5, 1, 2, 5, 10, 20, 40)
graphics::axis(1, at = ticks, labels = ticks)
graphics::axis(2, at = y, labels = dataset_order, tick = FALSE)
graphics::box()

for (comparator in comparators) {
  for (i in seq_along(dataset_order)) {
    z <- figure_data[
      figure_data$dataset == dataset_order[[i]] &
        figure_data$comparator == comparator,
      , drop = FALSE
    ]
    if (!nrow(z)) next
    yi <- y[[i]] + offsets[[comparator]]
    if (is.finite(z$median_ratio)) {
      graphics::segments(z$q1_ratio, yi, z$q3_ratio, yi,
                         col = colors[[comparator]], lwd = 1.8)
      graphics::points(z$median_ratio, yi, pch = symbols[[comparator]],
                       col = colors[[comparator]], cex = 0.8)
      graphics::text(
        48, yi,
        labels = paste0("n=", z$target_equivalent_pairs),
        col = colors[[comparator]], cex = 0.62, adj = 0
      )
    } else {
      graphics::points(0.52, yi, pch = 4, col = "#888888", cex = 0.9, lwd = 1.4)
      graphics::text(48, yi, labels = "n=0", col = "#777777", cex = 0.62, adj = 0)
    }
    if (z$comparator_timeouts > 0L) {
      graphics::points(39, yi, pch = 4, col = "#111111", cex = 0.9, lwd = 1.4)
      graphics::text(43, yi, labels = paste0("t=", z$comparator_timeouts),
                     col = "#111111", cex = 0.62)
    }
  }
}

graphics::legend(
  "topleft",
  legend = c("BiocNeighbors", "RcppHNSW", "No eligible pair", "Timeout (t)"),
  col = c(colors, "#888888", "#111111"), pch = c(symbols, 4, 4),
  bty = "n", cex = 0.78, inset = 0.01
)
graphics::mtext("Comparator faster", side = 1, at = 0.6, line = 2.7,
                cex = 0.72, col = "#555555")
graphics::mtext("faissR faster", side = 1, at = 17, line = 2.7,
                cex = 0.72, col = "#555555")
grDevices::dev.off()
cat("Wrote ", output, " and ", summary_output, "\n", sep = "")
