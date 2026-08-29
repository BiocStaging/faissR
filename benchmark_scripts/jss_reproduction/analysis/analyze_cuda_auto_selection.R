#!/usr/bin/env Rscript

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) y else x
}

parse_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[parts[[1L]]]] <- if (length(parts) > 1L) {
      paste(parts[-1L], collapse = "=")
    } else "TRUE"
  }
  out
}

parse_ivf_specs <- function(header_path) {
  lines <- readLines(header_path, warn = FALSE)
  start <- grep("static const HpcIvfSpec hpc_ivf_specs\\[\\]", lines)
  if (length(start) != 1L) stop("Cannot isolate hpc_ivf_specs in ", header_path)
  tail <- lines[seq.int(start + 1L, length(lines))]
  stop_at <- which(grepl("^};", trimws(tail)))[[1L]]
  block <- tail[seq_len(stop_at - 1L)]
  pattern <- paste0(
    '^\\s*\\{"([^"]+)",\\s*"([^"]+)",\\s*',
    '([0-9]+),\\s*([0-9]+),\\s*([0-9]+),\\s*([0-9]+),\\s*"([^"]+)"\\},?'
  )
  matched <- grepl(pattern, block)
  fields <- strcapture(
    pattern, block[matched],
    proto = list(
      backend = character(), shape_group = character(), k = integer(),
      target_code = integer(), nlist = integer(), nprobe = integer(),
      parameter_basis = character()
    )
  )
  fields$target_recall <- fields$target_code / 100
  fields
}

consistent_value <- function(x, label) {
  values <- unique(x[!is.na(x) & nzchar(as.character(x))])
  if (length(values) > 1L) stop("Inconsistent ", label, " across repeats.")
  if (length(values)) values[[1L]] else NA
}

collapse_cell <- function(part) {
  data.frame(
    part[1L, c("dataset", "dataset_md5", "n", "p", "shape_group",
                "metric", "k", "target_recall"), drop = FALSE],
    selected_method = consistent_value(part$auto_predicted_method, "selected method"),
    resolved_backend = consistent_value(part$result_backend, "resolved backend"),
    auto_reason = consistent_value(part$auto_reason, "auto reason"),
    tuning_rule = consistent_value(part$tuning_rule, "tuning rule"),
    n_validation_runs = nrow(part),
    stringsAsFactors = FALSE
  )
}

frequency_rows <- function(cells, dimension, value) {
  tab <- table(factor(cells$selected_method, levels = c("flat", "ivf")))
  data.frame(
    grouping_dimension = dimension,
    grouping_value = as.character(value),
    selected_method = names(tab),
    n_cells = as.integer(tab),
    total_cells = nrow(cells),
    fraction = as.integer(tab) / nrow(cells),
    stringsAsFactors = FALSE
  )
}

main <- function() {
  args <- parse_args()
  analysis_dir <- normalizePath(args$analysis_dir %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(
    args$out_dir %||% file.path(analysis_dir, "cuda_auto_selection"),
    mustWork = FALSE
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  combined_path <- file.path(analysis_dir, "jss_publication_results_combined.csv")
  if (!file.exists(combined_path)) {
    stop("Run aggregate_publication_results.R first.", call. = FALSE)
  }
  metrics <- strsplit(args$metrics %||% "euclidean,cosine,correlation", ",", fixed = TRUE)[[1L]]
  metrics <- trimws(metrics[nzchar(trimws(metrics))])
  combined <- read.csv(combined_path, stringsAsFactors = FALSE, check.names = FALSE)
  is_auto <- combined$backend == "cuda" & combined$implementation == "faissR" &
    (tolower(combined$public_method) == "auto" | grepl("_auto$", combined$method_id)) &
    combined$metric %in% metrics & combined$status == "success"
  auto <- combined[is_auto, , drop = FALSE]
  if (!nrow(auto)) stop("No successful CUDA automatic-selection rows found.", call. = FALSE)

  keys <- c("dataset", "dataset_md5", "metric", "k", "target_recall")
  grouping <- interaction(auto[keys], drop = TRUE, lex.order = TRUE)
  cells <- do.call(rbind, lapply(split(auto, grouping), collapse_cell))
  rownames(cells) <- NULL

  if (!is.null(args$package_root)) {
    package_root <- normalizePath(args$package_root, mustWork = TRUE)
  } else {
    file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    raw_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else ""
    script_path <- if (nzchar(raw_path) && file.exists(raw_path)) {
      normalizePath(raw_path, mustWork = TRUE)
    } else ""
    default_root <- if (nzchar(script_path)) {
      dirname(dirname(dirname(script_path)))
    } else getwd()
    package_root <- normalizePath(default_root, mustWork = TRUE)
  }
  header_path <- args$tuning_header %||% file.path(package_root, "src", "nn_hpc_tuning_tables.hpp")
  if (!file.exists(header_path)) {
    stop("Cannot find the frozen IVF tuning table: ", header_path, call. = FALSE)
  }
  ivf_specs <- parse_ivf_specs(header_path)
  ivf_specs <- ivf_specs[ivf_specs$backend == "cuda", , drop = FALSE]
  cells <- merge(
    cells, ivf_specs[, c("shape_group", "k", "target_recall", "nlist", "nprobe",
                         "parameter_basis")],
    by = c("shape_group", "k", "target_recall"), all.x = TRUE, sort = FALSE
  )
  cells$nlist[cells$selected_method != "ivf"] <- NA_integer_
  cells$nprobe[cells$selected_method != "ivf"] <- NA_integer_
  cells$parameter_basis[cells$selected_method != "ivf"] <- NA_character_
  if (any(cells$selected_method == "ivf" &
          (!is.finite(cells$nlist) | !is.finite(cells$nprobe)))) {
    stop("An IVF-selected cell lacks frozen nlist/nprobe metadata.", call. = FALSE)
  }
  cells$decision_signature <- ifelse(
    cells$selected_method == "ivf",
    paste("ivf", cells$nlist, cells$nprobe, sep = ":"),
    cells$selected_method
  )
  cells <- cells[order(cells$dataset, cells$metric, cells$k, cells$target_recall), ]
  write.csv(cells, file.path(out_dir, "jss_cuda_auto_selection_cells.csv"), row.names = FALSE)

  frequencies <- frequency_rows(cells, "overall", "all")
  for (dimension in c("metric", "target_recall", "dataset", "k")) {
    for (value in unique(cells[[dimension]])) {
      part <- cells[cells[[dimension]] == value, , drop = FALSE]
      frequencies <- rbind(frequencies, frequency_rows(part, dimension, value))
    }
  }
  write.csv(
    frequencies,
    file.path(out_dir, "jss_cuda_auto_selection_frequencies.csv"),
    row.names = FALSE
  )

  sensitivity_keys <- c("dataset", "dataset_md5", "metric", "k")
  sensitivity_group <- interaction(cells[sensitivity_keys], drop = TRUE, lex.order = TRUE)
  sensitivity <- do.call(rbind, lapply(split(cells, sensitivity_group), function(part) {
    part <- part[order(part$target_recall), , drop = FALSE]
    by_method <- split(part$decision_signature, part$selected_method)
    data.frame(
      part[1L, sensitivity_keys, drop = FALSE],
      method_at_090 = part$selected_method[match(0.90, part$target_recall)],
      method_at_095 = part$selected_method[match(0.95, part$target_recall)],
      method_at_099 = part$selected_method[match(0.99, part$target_recall)],
      decision_at_090 = part$decision_signature[match(0.90, part$target_recall)],
      decision_at_095 = part$decision_signature[match(0.95, part$target_recall)],
      decision_at_099 = part$decision_signature[match(0.99, part$target_recall)],
      method_changes_with_target = length(unique(part$selected_method)) > 1L,
      parameters_change_within_method = any(vapply(by_method, function(x) {
        length(unique(x)) > 1L
      }, logical(1L))),
      decision_changes_with_target = length(unique(part$decision_signature)) > 1L,
      stringsAsFactors = FALSE
    )
  }))
  rownames(sensitivity) <- NULL
  write.csv(
    sensitivity,
    file.path(out_dir, "jss_cuda_auto_target_sensitivity.csv"),
    row.names = FALSE
  )

  writeLines(c(
    "# CUDA automatic-selection decomposition", "",
    paste0("Automatic-selection cells: ", nrow(cells), "."),
    paste0("Flat selections: ", sum(cells$selected_method == "flat"), "."),
    paste0("IVF selections: ", sum(cells$selected_method == "ivf"), "."),
    paste0("Dataset-metric-k strata: ", nrow(sensitivity), "."),
    paste0("Strata where target recall changed the method: ",
           sum(sensitivity$method_changes_with_target), "."),
    paste0("Strata where target recall changed numeric parameters within a method: ",
           sum(sensitivity$parameters_change_within_method), "."),
    paste0("Strata where target recall changed either method or numeric parameters: ",
           sum(sensitivity$decision_changes_with_target), "."), "",
    "Frequencies are reported separately by metric, target, dataset, and k. Numeric IVF decisions use the nlist and nprobe values in the package's frozen C++ tuning table."
  ), file.path(out_dir, "JSS_CUDA_AUTO_SELECTION_REPORT.md"))
}

main()
