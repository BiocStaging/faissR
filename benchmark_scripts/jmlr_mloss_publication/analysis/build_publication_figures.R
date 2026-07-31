#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
  }
  out
}

method_family <- function(x) sub("^faissR_(cpu|cuda)_", "", as.character(x))

draw_frontiers <- function(summary, output, backend) {
  metrics <- c("euclidean", "cosine", "correlation", "inner_product")
  pdf(output, width = 11, height = 8.5, onefile = TRUE)
  on.exit(dev.off(), add = TRUE)
  for (target in c(0.9, 0.95, 0.99)) {
    par(mfrow = c(2, 2), mar = c(4.2, 4.4, 3.2, 1.2))
    for (metric in metrics) {
      x <- summary[summary$metric == metric & abs(summary$target_recall - target) < 1e-12 &
                     summary$complete_validation & is.finite(summary$median_time_sec) &
                     is.finite(summary$min_recall_at_k), , drop = FALSE]
      if (!nrow(x)) {
        plot.new(); title(main = metric); text(0.5, 0.5, "No complete cells")
        next
      }
      family <- method_family(x$method_id)
      levels <- sort(unique(family))
      colors <- grDevices::hcl.colors(length(levels), "Dark 3")
      col <- colors[match(family, levels)]
      plot(x$median_time_sec, x$min_recall_at_k, log = "x", pch = 19, col = col,
           xlab = "Median end-to-end time (seconds, log scale)", ylab = "Minimum recall@k",
           main = paste(metric, "target", target), ylim = range(c(target, x$min_recall_at_k), finite = TRUE))
      abline(h = target, lty = 2, col = "grey40")
      legend("bottomright", legend = levels, col = colors, pch = 19, cex = 0.55, bty = "n", ncol = 2)
    }
    mtext(paste("faissR", toupper(backend), "held-out speed-recall evidence"), outer = TRUE, line = -1.2, cex = 1.1)
  }
}

draw_auto_oracle <- function(auto, output, backend) {
  usable <- auto[is.finite(auto$auto_over_oracle) & auto$auto_over_oracle > 0, , drop = FALSE]
  pdf(output, width = 10, height = 6)
  on.exit(dev.off(), add = TRUE)
  if (!nrow(usable)) {
    plot.new(); text(0.5, 0.5, "No complete auto-oracle comparisons")
    return(invisible(NULL))
  }
  usable$metric <- factor(usable$metric, levels = c("euclidean", "cosine", "correlation", "inner_product"))
  boxplot(log10(auto_over_oracle) ~ metric, data = usable, col = "grey85",
          ylab = "log10(auto runtime / explicit-faissR-oracle runtime)", xlab = "Metric",
          main = paste("Automatic-selection regret on", toupper(backend)))
  abline(h = 0, lty = 2, col = "grey35")
  stripchart(log10(auto_over_oracle) ~ metric, data = usable, method = "jitter", vertical = TRUE,
             pch = 19, cex = 0.55, col = grDevices::adjustcolor("#006d77", 0.55), add = TRUE)
}

main <- function() {
  args <- parse_args()
  analysis_dir <- normalizePath(args$analysis_dir %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(analysis_dir, "figures"), mustWork = FALSE)
  backend <- tolower(args$backend %||% "cpu")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  summary <- read.csv(file.path(analysis_dir, "jss_robust_method_summary.csv"), stringsAsFactors = FALSE)
  auto <- read.csv(file.path(analysis_dir, "jss_auto_vs_oracle.csv"), stringsAsFactors = FALSE)
  draw_frontiers(summary, file.path(out_dir, paste0("jss_speed_recall_", backend, ".pdf")), backend)
  draw_auto_oracle(auto, file.path(out_dir, paste0("jss_auto_oracle_", backend, ".pdf")), backend)

  focus <- summary[summary$k == 30L & abs(summary$target_recall - 0.99) < 1e-12, , drop = FALSE]
  write.csv(focus, file.path(out_dir, paste0("jss_figure_data_k30_recall099_", backend, ".csv")), row.names = FALSE)
  auto_focus <- auto[auto$k == 30L & abs(auto$target_recall - 0.99) < 1e-12, , drop = FALSE]
  write.csv(auto_focus, file.path(out_dir, paste0("jss_auto_oracle_k30_recall099_", backend, ".csv")), row.names = FALSE)
  files <- list.files(out_dir, full.names = TRUE)
  write.csv(data.frame(file = basename(files), md5 = unname(tools::md5sum(files))),
            file.path(out_dir, "figure_checksums.csv"), row.names = FALSE)
  cat("Wrote publication figures to ", out_dir, "\n", sep = "")
}

main()
