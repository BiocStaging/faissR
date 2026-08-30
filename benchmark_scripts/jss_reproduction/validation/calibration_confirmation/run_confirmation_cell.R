#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list(repeats = 5L, timeout = 4000L, reference_k = 100L,
              quality_n = 1024L, seed = 20260807L)
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  for (name in c("cell_id", "repeats", "timeout", "reference_k", "quality_n", "seed")) {
    out[[name]] <- as.integer(out[[name]])
  }
  out
}

append_csv <- function(x, path) {
  utils::write.table(
    x, path, sep = ",", row.names = FALSE,
    col.names = !file.exists(path), append = file.exists(path),
    quote = TRUE, na = ""
  )
}

args <- parse_args()
Sys.setenv(FAISSR_TUNING_SOURCE_ONLY = "true")
source(args$helper, local = .GlobalEnv)
manifest <- utils::read.csv(args$manifest, stringsAsFactors = FALSE,
                            check.names = FALSE)
part <- manifest[manifest$confirmation_cell_id == args$cell_id, , drop = FALSE]
if (!nrow(part)) quit(status = 0L)
dataset_manifest <- utils::read.csv(args$dataset_manifest, stringsAsFactors = FALSE)
ds <- dataset_manifest[dataset_manifest$dataset == part$dataset[[1L]], , drop = FALSE]
if (nrow(ds) != 1L) stop("Dataset manifest match is not unique.")
path_column <- dataset_path_column(ds)
dataset_path <- ds[[path_column]][[1L]]
dataset_md5 <- unname(tools::md5sum(dataset_path)[[1L]])
if (!identical(dataset_md5, part$dataset_md5[[1L]])) {
  stop("Dataset fingerprint differs from screening calibration.")
}
reference <- load_reference(
  dataset_path, part$k[[1L]], args$reference_k, args$quality_n,
  args$seed, metric = part$metric[[1L]], dataset_md5 = dataset_md5
)
candidate_columns <- intersect(
  c("candidate_id", "candidate_kind", "n_threads", "output", all_option_columns),
  names(part)
)
plan <- expand.grid(
  candidate_row = seq_len(nrow(part)),
  timing_repeat = seq_len(args$repeats),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
set.seed(args$seed + args$cell_id)
plan <- plan[sample.int(nrow(plan)), , drop = FALSE]
plan$execution_order <- seq_len(nrow(plan))
dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
output <- file.path(args$out_dir, "jss_calibration_confirmation_raw.csv")
Sys.unsetenv("FAISSR_TUNING_SOURCE_ONLY")

for (i in seq_len(nrow(plan))) {
  source_row <- part[plan$candidate_row[[i]], , drop = FALSE]
  candidate <- source_row[, candidate_columns, drop = FALSE]
  config <- list(
    dataset = source_row$dataset[[1L]], dataset_path = dataset_path,
    dataset_md5 = dataset_md5, n = as.integer(source_row$n[[1L]]),
    p = as.integer(source_row$p[[1L]]), backend = source_row$backend[[1L]],
    method = source_row$method[[1L]], metric = source_row$metric[[1L]],
    k = as.integer(source_row$k[[1L]]),
    target_recalls = as.numeric(source_row$target_recall[[1L]]),
    reference_rows = reference$rows, reference_indices = reference$indices,
    reference_status = reference$status %||% NA_character_,
    reference_path = reference$path %||% NA_character_,
    reference_query_n = length(reference$rows %||% integer()),
    candidate = candidate
  )
  result <- run_task(config, args$timeout, args$helper)
  result$confirmation_cell_id <- args$cell_id
  result$target_recall <- source_row$target_recall[[1L]]
  result$screen_rank <- source_row$screen_rank[[1L]]
  result$screen_elapsed_sec <- source_row$screen_elapsed_sec[[1L]]
  result$screen_recall_at_k <- source_row$screen_recall_at_k[[1L]]
  result$screen_winner <- source_row$screen_winner[[1L]]
  result$timing_repeat <- plan$timing_repeat[[i]]
  result$execution_order <- plan$execution_order[[i]]
  result$selection_rule <- source_row$selection_rule[[1L]]
  append_csv(result, output)
}
writeLines(capture.output(sessionInfo()), file.path(args$out_dir, "sessionInfo.txt"))
cat("DONE:", output, "\n")
