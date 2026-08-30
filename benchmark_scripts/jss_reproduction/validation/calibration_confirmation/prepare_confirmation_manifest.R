#!/usr/bin/env Rscript

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list(
    calibration_root = "",
    backend = "cuda",
    output = "confirmation_manifest.csv",
    top_n = 3L,
    max_candidates = 5L,
    family_margin = 0.25
  )
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  out$top_n <- as.integer(out$top_n)
  out$max_candidates <- as.integer(out$max_candidates)
  out$family_margin <- as.numeric(out$family_margin)
  out
}

bind_rows <- function(values) {
  columns <- unique(unlist(lapply(values, names), use.names = FALSE))
  values <- lapply(values, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, values)
}

logical_value <- function(x) {
  tolower(as.character(x)) %in% c("true", "t", "1")
}

args <- parse_args()
if (!nzchar(args$calibration_root) || !dir.exists(args$calibration_root)) {
  stop("--calibration_root must name the completed screening calibration/real directory")
}
files <- list.files(
  file.path(args$calibration_root, args$backend),
  pattern = "_tuning_results[.]csv$", recursive = TRUE, full.names = TRUE
)
if (!length(files)) stop("No calibration result files found for ", args$backend)
raw <- bind_rows(lapply(files, function(path) {
  x <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  x$source_file <- normalizePath(path, mustWork = TRUE)
  x
}))
raw <- raw[
  raw$backend == args$backend &
    raw$metric %in% c("euclidean", "cosine", "correlation") &
    raw$status == "success" & is.finite(raw$elapsed_sec) &
    is.finite(raw$recall_at_k),
  , drop = FALSE
]
if (!nrow(raw)) stop("No successful public-metric calibration rows.")

candidate_key <- interaction(
  raw[c("backend", "method", "dataset", "metric", "k", "candidate_id")],
  drop = TRUE, lex.order = TRUE
)
raw <- raw[!duplicated(candidate_key, fromLast = TRUE), , drop = FALSE]
targets <- c(0.90, 0.95, 0.99)
base_cells <- unique(raw[c("dataset", "backend", "metric", "k")])
base_cells <- base_cells[do.call(order, base_cells), , drop = FALSE]

selected <- list()
cell_index <- 0L
for (i in seq_len(nrow(base_cells))) {
  cell <- base_cells[i, , drop = FALSE]
  part <- raw[
    raw$dataset == cell$dataset & raw$backend == cell$backend &
      raw$metric == cell$metric & raw$k == cell$k,
    , drop = FALSE
  ]
  for (target in targets) {
    exact <- if ("exact" %in% names(part)) logical_value(part$exact) else FALSE
    exact[is.na(exact)] <- FALSE
    feasible <- part[exact | part$recall_at_k >= target, , drop = FALSE]
    if (!nrow(feasible)) next
    feasible <- feasible[order(
      feasible$elapsed_sec, -feasible$recall_at_k,
      feasible$method, feasible$candidate_id
    ), , drop = FALSE]
    feasible$screen_rank <- seq_len(nrow(feasible))
    best_time <- feasible$elapsed_sec[[1L]]
    primary <- head(feasible, args$top_n)
    family_first <- feasible[!duplicated(feasible$method), , drop = FALSE]
    family_first <- family_first[
      family_first$elapsed_sec <= best_time * (1 + args$family_margin),
      , drop = FALSE
    ]
    keep <- unique(c(
      paste(primary$method, primary$candidate_id, sep = "\r"),
      paste(family_first$method, family_first$candidate_id, sep = "\r")
    ))
    key <- paste(feasible$method, feasible$candidate_id, sep = "\r")
    confirmation <- feasible[key %in% keep, , drop = FALSE]
    confirmation <- head(confirmation, args$max_candidates)
    cell_index <- cell_index + 1L
    confirmation$confirmation_cell_id <- cell_index
    confirmation$target_recall <- target
    confirmation$screen_elapsed_sec <- confirmation$elapsed_sec
    confirmation$screen_recall_at_k <- confirmation$recall_at_k
    confirmation$screen_winner <- confirmation$screen_rank == 1L
    confirmation$selection_rule <- paste0(
      "top", args$top_n, "_plus_family_winners_within_",
      format(args$family_margin, trim = TRUE), "_cap", args$max_candidates
    )
    selected[[length(selected) + 1L]] <- confirmation
  }
}
manifest <- bind_rows(selected)
manifest <- manifest[order(
  manifest$confirmation_cell_id, manifest$screen_rank,
  manifest$method, manifest$candidate_id
), , drop = FALSE]
dir.create(dirname(args$output), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(manifest, args$output, row.names = FALSE)
summary <- unique(manifest[c(
  "confirmation_cell_id", "dataset", "backend", "metric", "k", "target_recall"
)])
utils::write.csv(
  summary,
  sub("[.]csv$", "_cells.csv", args$output),
  row.names = FALSE
)
cat("Confirmation cells:", nrow(summary), "\n")
cat("Candidate rows:", nrow(manifest), "\n")
cat("Manifest:", normalizePath(args$output, mustWork = TRUE), "\n")
