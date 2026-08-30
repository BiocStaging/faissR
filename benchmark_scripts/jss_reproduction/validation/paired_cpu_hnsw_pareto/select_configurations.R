#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list()
  for (a in x) if (startsWith(a, "--")) {
    p <- strsplit(sub("^--", "", a), "=", fixed = TRUE)[[1L]]
    out[[p[[1L]]]] <- paste(p[-1L], collapse = "=")
  }
  out
}
args <- parse_args(commandArgs(trailingOnly = TRUE))
root <- normalizePath(args$root, mustWork = TRUE)
files <- list.files(file.path(root, "calibration"), "jss_paired_hnsw_raw[.]csv$", recursive = TRUE, full.names = TRUE)
if (!length(files)) stop("No calibration result files found.")
x <- do.call(rbind, lapply(files, read.csv, stringsAsFactors = FALSE))
x$success <- x$status == "success" & is.finite(x$cold_call_sec) & is.finite(x$cold_recall_at_k)

keys <- c("dataset", "k", "comparator", "route", "hnsw_m", "ef_construction", "ef_search")
groups <- interaction(x[keys], drop = TRUE, lex.order = TRUE)
curve <- do.call(rbind, lapply(split(x, groups), function(z) data.frame(
  z[1L, keys, drop = FALSE], n_runs = nrow(z), n_success = sum(z$success),
  minimum_recall = if (any(z$success)) min(z$cold_recall_at_k[z$success]) else NA_real_,
  median_time_sec = if (any(z$success)) median(z$cold_call_sec[z$success]) else NA_real_,
  target_met = nrow(z) == 3L && all(z$success) && all(z$cold_recall_at_k >= 0.99),
  stringsAsFactors = FALSE
)))
curve$pareto_efficient <- FALSE
front_groups <- interaction(curve[c("dataset", "k", "comparator", "route")], drop = TRUE)
for (indices in split(seq_len(nrow(curve)), front_groups)) {
  z <- curve[indices, ]
  valid <- is.finite(z$median_time_sec) & is.finite(z$minimum_recall)
  for (j in which(valid)) {
    dominated <- valid & z$median_time_sec <= z$median_time_sec[[j]] &
      z$minimum_recall >= z$minimum_recall[[j]] &
      (z$median_time_sec < z$median_time_sec[[j]] |
         z$minimum_recall > z$minimum_recall[[j]])
    curve$pareto_efficient[indices[[j]]] <- !any(dominated)
  }
}
curve <- curve[order(curve$dataset, curve$k, curve$comparator, curve$route,
                     curve$median_time_sec, curve$ef_search, curve$ef_construction), ]
write.csv(curve, file.path(root, "calibration_pareto_points.csv"), row.names = FALSE)

select_one <- function(z) {
  eligible <- z[z$target_met & is.finite(z$median_time_sec), ]
  basis <- "fastest_calibration_target_attaining"
  if (!nrow(eligible)) {
    eligible <- z[z$n_success > 0L & is.finite(z$minimum_recall), ]
    eligible <- eligible[order(-eligible$minimum_recall, eligible$median_time_sec,
                               eligible$ef_search, eligible$ef_construction), ]
    basis <- "fallback_highest_observed_recall"
  } else {
    eligible <- eligible[order(eligible$median_time_sec, eligible$ef_search,
                               eligible$ef_construction), ]
  }
  if (!nrow(eligible)) stop("No successful calibration candidate for ", z$dataset[[1L]])
  out <- eligible[1L, ]
  out$selection_basis <- basis
  out
}
selection_groups <- interaction(curve[c("dataset", "k", "comparator", "route")], drop = TRUE)
selected <- do.call(rbind, lapply(split(curve, selection_groups), select_one))

pairs <- unique(selected[c("dataset", "k", "comparator")])
rows <- lapply(seq_len(nrow(pairs)), function(i) {
  key <- pairs[i, ]
  z <- selected[selected$dataset == key$dataset & selected$k == key$k &
                  selected$comparator == key$comparator, ]
  f <- z[z$route == "faissR_hnsw", ]; c <- z[z$route == key$comparator, ]
  stopifnot(nrow(f) == 1L, nrow(c) == 1L)
  data.frame(
    key, faiss_hnsw_m = f$hnsw_m, faiss_ef_construction = f$ef_construction,
    faiss_ef_search = f$ef_search, faiss_calibration_target_met = f$target_met,
    faiss_selection_basis = f$selection_basis,
    comparator_hnsw_m = c$hnsw_m,
    comparator_ef_construction = c$ef_construction,
    comparator_ef_search = c$ef_search,
    comparator_calibration_target_met = c$target_met,
    comparator_selection_basis = c$selection_basis,
    stringsAsFactors = FALSE
  )
})
manifest <- do.call(rbind, rows)
manifest$task_id <- seq_len(nrow(manifest))
manifest <- manifest[, c("task_id", setdiff(names(manifest), "task_id"))]
stopifnot(nrow(manifest) == 72L)
write.csv(manifest, file.path(root, "selected_configuration_manifest.csv"), row.names = FALSE)
cat("Selected 72 independently tuned provider pairs.\n")
