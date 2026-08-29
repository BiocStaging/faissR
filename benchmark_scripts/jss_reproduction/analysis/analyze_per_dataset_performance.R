#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list(
    held_out_root = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/final_campaign/held_out",
    out_dir = "/scratch/firenze/NN/faissR_JSS_REPRODUCTION/final_campaign/analysis/per_dataset"
  )
  for (arg in x) {
    if (startsWith(arg, "--held_out_root=")) {
      out$held_out_root <- sub("^--held_out_root=", "", arg)
    } else if (startsWith(arg, "--out_dir=")) {
      out$out_dir <- sub("^--out_dir=", "", arg)
    } else {
      stop("Unknown argument: ", arg, call. = FALSE)
    }
  }
  out
}

num <- function(x) suppressWarnings(as.numeric(x))

read_route <- function(root, backend, route) {
  path <- file.path(root, backend, route)
  files <- list.files(
    path, pattern = "^jmlr_tuned_benchmark_results[.]csv$",
    recursive = TRUE, full.names = TRUE
  )
  if (!length(files)) stop("No result files under ", path, call. = FALSE)
  x <- do.call(rbind, lapply(files, utils::read.csv, stringsAsFactors = FALSE))
  x <- x[x$metric %in% c("euclidean", "cosine", "correlation"), , drop = FALSE]
  if ("dataset_suite" %in% names(x)) {
    x <- x[is.na(x$dataset_suite) | x$dataset_suite == "real", , drop = FALSE]
  }
  keys <- c("dataset", "metric", "k", "target_recall", "validation_seed", "repeat_id")
  key <- interaction(lapply(x[keys], function(z) {
    z <- as.character(z)
    z[is.na(z)] <- "<NA>"
    z
  }), drop = TRUE, lex.order = TRUE)
  x[!duplicated(key, fromLast = TRUE), , drop = FALSE]
}

group_indices <- function(x, columns) {
  split(seq_len(nrow(x)), interaction(x[columns], drop = TRUE, lex.order = TRUE))
}

median_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}

pretty_dataset <- function(x) {
  x[x == "FlowRepository_FR-FCM-ZYRM_files"] <- "FR-FCM-ZYRM"
  x[x == "imagenet"] <- "ImageNet features"
  x
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)

cpu_faiss <- read_route(args$held_out_root, "cpu", "faissR_hnsw")
cpu_bioc <- read_route(args$held_out_root, "cpu", "BiocNeighbors_hnsw")
expected_replicates <- length(unique(cpu_faiss$validation_seed)) *
  length(unique(cpu_faiss$repeat_id))

cpu_cells <- lapply(group_indices(
  cpu_faiss, c("dataset", "metric", "k", "target_recall")
), function(i) {
  z <- cpu_faiss[i, , drop = FALSE]
  complete <- nrow(z) == expected_replicates && all(z$status == "success")
  data.frame(
    dataset = z$dataset[[1L]],
    complete = complete,
    target_met = complete && all(num(z$recall_at_k) >= num(z$target_recall) - 1e-12),
    stringsAsFactors = FALSE
  )
})
cpu_cells <- do.call(rbind, cpu_cells)

faiss_099 <- cpu_faiss[
  cpu_faiss$metric %in% c("euclidean", "cosine") &
    abs(num(cpu_faiss$target_recall) - 0.99) < 1e-12,
  , drop = FALSE
]
pair_keys <- c("dataset", "metric", "k", "validation_seed", "repeat_id")
lhs <- faiss_099[, c(pair_keys, "status", "time_sec", "recall_at_k"), drop = FALSE]
rhs <- cpu_bioc[cpu_bioc$metric %in% c("euclidean", "cosine"),
                c(pair_keys, "status", "time_sec", "recall_at_k"), drop = FALSE]
names(lhs)[-(seq_along(pair_keys))] <- paste0("faissR_", names(lhs)[-(seq_along(pair_keys))])
names(rhs)[-(seq_along(pair_keys))] <- paste0("bioc_", names(rhs)[-(seq_along(pair_keys))])
cpu_pairs <- merge(lhs, rhs, by = pair_keys, all = FALSE)
cpu_pairs <- cpu_pairs[
  cpu_pairs$faissR_status == "success" & cpu_pairs$bioc_status == "success",
  , drop = FALSE
]
cpu_pairs$speed_ratio_bioc_over_faissR <-
  num(cpu_pairs$bioc_time_sec) / num(cpu_pairs$faissR_time_sec)
cpu_pairs$recall_equivalent <- FALSE
for (i in group_indices(cpu_pairs, c("dataset", "metric", "k"))) {
  z <- cpu_pairs[i, , drop = FALSE]
  cpu_pairs$recall_equivalent[i] <-
    nrow(z) == expected_replicates &&
    all(num(z$faissR_recall_at_k) >= 0.99) &&
    all(num(z$bioc_recall_at_k) >= 0.99)
}

datasets <- sort(unique(c(cpu_faiss$dataset, cpu_bioc$dataset)))
cpu_table <- do.call(rbind, lapply(datasets, function(dataset) {
  cells <- cpu_cells[cpu_cells$dataset == dataset, , drop = FALSE]
  pairs <- cpu_pairs[cpu_pairs$dataset == dataset, , drop = FALSE]
  equivalent <- pairs[pairs$recall_equivalent, , drop = FALSE]
  data.frame(
    dataset = pretty_dataset(dataset),
    target_cells_completed = sum(cells$complete),
    target_cells_met = sum(cells$target_met),
    faissR_timeouts = sum(cpu_faiss$dataset == dataset & cpu_faiss$status == "timeout"),
    matched_hnsw_cells = length(unique(interaction(pairs$metric, pairs$k, drop = TRUE))),
    recall_equivalent_hnsw_cells = length(unique(interaction(
      equivalent$metric, equivalent$k, drop = TRUE
    ))),
    BiocNeighbors_timeouts = sum(cpu_bioc$dataset == dataset & cpu_bioc$status == "timeout"),
    median_ratio_BiocNeighbors_over_faissR = median_or_na(
      num(pairs$speed_ratio_bioc_over_faissR)
    ),
    median_recall_equivalent_ratio = median_or_na(
      num(equivalent$speed_ratio_bioc_over_faissR)
    ),
    stringsAsFactors = FALSE
  )
}))

cuda <- lapply(
  c("faissR_auto", "faissR_exact", "faissR_bruteforce", "faissR_cagra"),
  function(route) read_route(args$held_out_root, "cuda", route)
)
names(cuda) <- c("auto", "exact", "bruteforce", "cagra")

cuda_key <- function(x) {
  do.call(
    paste,
    c(
      lapply(
        x[c("dataset", "metric", "k", "target_recall", "validation_seed", "repeat_id")],
        as.character
      ),
      sep = "\r"
    )
  )
}
cuda_maps <- lapply(cuda, function(x) {
  out <- seq_len(nrow(x))
  names(out) <- as.character(cuda_key(x))
  out
})

auto_cells <- lapply(group_indices(
  cuda$auto, c("dataset", "metric", "k", "target_recall")
), function(i) {
  z <- cuda$auto[i, , drop = FALSE]
  complete <- nrow(z) == expected_replicates && all(z$status == "success")
  exact_audited <- all(tolower(as.character(z$auto_predicted_method)) == "flat")
  data.frame(
    dataset = z$dataset[[1L]],
    metric = z$metric[[1L]],
    k = z$k[[1L]],
    target_recall = z$target_recall[[1L]],
    complete = complete,
    target_met = complete && (exact_audited ||
      all(num(z$recall_at_k) >= num(z$target_recall) - 1e-12)),
    selected_ivf = all(tolower(as.character(z$auto_predicted_method)) == "ivf"),
    stringsAsFactors = FALSE
  )
})
auto_cells <- do.call(rbind, auto_cells)

route_ratios <- function(comparator) {
  common <- intersect(names(cuda_maps$auto), names(cuda_maps[[comparator]]))
  a <- cuda$auto[cuda_maps$auto[common], , drop = FALSE]
  b <- cuda[[comparator]][cuda_maps[[comparator]][common], , drop = FALSE]
  ok <- a$status == "success" & b$status == "success"
  data.frame(
    dataset = a$dataset[ok], metric = a$metric[ok], k = a$k[ok],
    target_recall = a$target_recall[ok],
    auto_predicted_method = a$auto_predicted_method[ok],
    ratio = num(b$time_sec[ok]) / num(a$time_sec[ok]),
    stringsAsFactors = FALSE
  )
}
cuda_ratios <- lapply(c("exact", "bruteforce", "cagra"), route_ratios)
names(cuda_ratios) <- c("exact", "bruteforce", "cagra")

cuda_datasets <- sort(unique(cuda$auto$dataset))
cuda_table <- do.call(rbind, lapply(cuda_datasets, function(dataset) {
  cells <- auto_cells[auto_cells$dataset == dataset, , drop = FALSE]
  exact <- cuda_ratios$exact[cuda_ratios$exact$dataset == dataset, , drop = FALSE]
  brute <- cuda_ratios$bruteforce[cuda_ratios$bruteforce$dataset == dataset, , drop = FALSE]
  cagra <- cuda_ratios$cagra[cuda_ratios$cagra$dataset == dataset, , drop = FALSE]
  ivf_exact <- exact[tolower(as.character(exact$auto_predicted_method)) == "ivf", , drop = FALSE]
  data.frame(
    dataset = pretty_dataset(dataset),
    auto_cells_completed = sum(cells$complete),
    auto_target_cells_met = sum(cells$target_met),
    auto_timeouts = sum(cuda$auto$dataset == dataset & cuda$auto$status == "timeout"),
    median_ratio_exact_over_auto = median_or_na(num(exact$ratio)),
    median_ratio_bruteforce_over_auto = median_or_na(num(brute$ratio)),
    median_ratio_cagra_over_auto = median_or_na(num(cagra$ratio)),
    ivf_cells_selected = sum(cells$selected_ivf),
    ivf_target_cells_met = sum(cells$selected_ivf & cells$target_met),
    median_ratio_exact_over_ivf = median_or_na(num(ivf_exact$ratio)),
    stringsAsFactors = FALSE
  )
}))

utils::write.csv(
  cpu_table, file.path(args$out_dir, "jss_cpu_per_dataset_performance.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  cuda_table, file.path(args$out_dir, "jss_cuda_per_dataset_performance.csv"),
  row.names = FALSE, na = ""
)
writeLines(c(
  "# Per-dataset performance audit",
  "",
  "Ratios use second-route time divided by first-route time.",
  paste0("CPU datasets: ", nrow(cpu_table), "."),
  paste0("CUDA datasets: ", nrow(cuda_table), "."),
  paste0("CPU faissR timeouts: ", sum(cpu_table$faissR_timeouts), "."),
  paste0("CPU BiocNeighbors timeouts: ", sum(cpu_table$BiocNeighbors_timeouts), "."),
  paste0("CUDA auto timeouts: ", sum(cuda_table$auto_timeouts), "."),
  paste0("CUDA IVF-selected datasets: ", sum(cuda_table$ivf_cells_selected > 0), ".")
), file.path(args$out_dir, "JSS_PER_DATASET_PERFORMANCE_REPORT.md"))

cat("Per-dataset performance audit completed: ", args$out_dir, "\n", sep = "")
