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
  metrics <- c("euclidean", "cosine", "correlation")
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

draw_paired_ratios <- function(dataset_pairs, output, backend, comparison_type,
                               title, reference_label) {
  usable <- dataset_pairs[
    dataset_pairs$comparison_type == comparison_type &
      is.finite(dataset_pairs$dataset_median_paired_ratio) &
      dataset_pairs$dataset_median_paired_ratio > 0,
    , drop = FALSE
  ]
  pdf(output, width = 11, height = 7, onefile = TRUE)
  on.exit(dev.off(), add = TRUE)
  if (!nrow(usable)) {
    plot.new(); text(0.5, 0.5, "No complete paired comparisons")
    return(invisible(NULL))
  }
  metrics <- intersect(
    c("euclidean", "cosine", "correlation"),
    unique(usable$metric)
  )
  for (metric in metrics) {
    part <- usable[usable$metric == metric, , drop = FALSE]
    labels <- if (comparison_type == "faissR_auto_vs_oracle") {
      factor(rep("empirical oracle", nrow(part)))
    } else {
      factor(part$comparator_id, levels = sort(unique(part$comparator_id)))
    }
    values <- log2(part$dataset_median_paired_ratio)
    par(mar = c(8, 4.5, 3.5, 1))
    boxplot(values ~ labels, col = "grey88", las = 2,
            ylab = "log2 paired runtime ratio", xlab = "",
            main = paste(title, "-", toupper(backend), metric))
    abline(h = 0, lty = 2, col = "grey35")
    stripchart(values ~ labels, method = "jitter", vertical = TRUE,
               pch = 19, cex = 0.65,
               col = grDevices::adjustcolor("#006d77", 0.6), add = TRUE)
    mtext(reference_label, side = 1, line = 6.8, cex = 0.75)
  }
}

main <- function() {
  args <- parse_args()
  analysis_dir <- normalizePath(args$analysis_dir %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(analysis_dir, "figures"), mustWork = FALSE)
  backend <- tolower(args$backend %||% "cpu")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  summary <- read.csv(file.path(analysis_dir, "jss_robust_method_summary.csv"), stringsAsFactors = FALSE)
  auto <- read.csv(file.path(analysis_dir, "jss_auto_vs_oracle.csv"), stringsAsFactors = FALSE)
  paired_datasets <- read.csv(
    file.path(analysis_dir, "jss_paired_performance_by_dataset.csv"),
    stringsAsFactors = FALSE
  )
  summary <- summary[summary$backend == backend, , drop = FALSE]
  auto <- auto[auto$backend == backend, , drop = FALSE]
  paired_datasets <- paired_datasets[
    paired_datasets$backend == backend, , drop = FALSE
  ]
  draw_frontiers(summary, file.path(out_dir, paste0("jss_speed_recall_", backend, ".pdf")), backend)
  draw_paired_ratios(
    paired_datasets,
    file.path(out_dir, paste0("jss_paired_auto_oracle_", backend, ".pdf")),
    backend,
    "faissR_auto_vs_oracle",
    "Automatic-selection regret",
    "auto/oracle; values above 1 favor the oracle"
  )
  draw_paired_ratios(
    paired_datasets,
    file.path(out_dir, paste0("jss_paired_external_", backend, ".pdf")),
    backend,
    "faissR_auto_vs_external",
    "faissR auto versus external comparators",
    "comparator/faissR auto; values above 1 favor faissR"
  )

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
