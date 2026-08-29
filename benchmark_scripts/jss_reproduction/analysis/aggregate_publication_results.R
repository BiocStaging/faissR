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

split_values <- function(x, default) {
  trimws(strsplit(x %||% default, ",", fixed = TRUE)[[1L]])
}

read_union <- function(files) {
  tables <- lapply(files, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    x$source_file <- normalizePath(path, mustWork = TRUE)
    x$source_mtime <- as.numeric(file.info(path)$mtime)
    x$run_root <- dirname(path)
    x
  })
  columns <- unique(unlist(lapply(tables, names), use.names = FALSE))
  tables <- lapply(tables, function(x) {
    for (name in setdiff(columns, names(x))) x[[name]] <- NA
    x[, columns, drop = FALSE]
  })
  do.call(rbind, tables)
}

latest_method_runs <- function(x) {
  if (!"dataset_md5" %in% names(x)) x$dataset_md5 <- NA_character_
  suite <- ifelse(is.na(x$dataset_suite) | !nzchar(x$dataset_suite), "real", x$dataset_suite)
  key <- paste(x$backend, x$method_id, suite, x$dataset, x$metric, sep = "\r")
  selected <- unlist(lapply(split(seq_len(nrow(x)), key), function(ii) {
    roots <- unique(x$run_root[ii])
    root_time <- vapply(roots, function(root) max(x$source_mtime[ii][x$run_root[ii] == root]), numeric(1))
    ii[x$run_root[ii] == roots[[which.max(root_time)]]]
  }), use.names = FALSE)
  x[sort(selected), , drop = FALSE]
}

expand_external_targets <- function(x, targets) {
  external <- x$implementation != "faissR" | is.na(x$target_recall)
  fixed <- x[!external, , drop = FALSE]
  ext <- x[external, , drop = FALSE]
  if (!nrow(ext)) return(fixed)
  expanded <- do.call(rbind, lapply(targets, function(target) {
    out <- ext
    out$target_recall <- target
    out
  }))
  rbind(fixed, expanded)
}

group_apply <- function(x, columns, fun) {
  key_data <- lapply(x[columns], function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  key <- interaction(key_data, drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(x, key), fun)
  out <- do.call(rbind, rows)
  row.names(out) <- NULL
  out
}

exact_family_rows <- function(x) {
  public <- tolower(as.character(x$public_method))
  method <- tolower(as.character(x$method_id))
  exact_meta <- if ("exact" %in% names(x)) {
    value <- suppressWarnings(as.logical(x$exact))
    !is.na(value) & value
  } else {
    rep(FALSE, nrow(x))
  }
  public %in% c("exact", "flat", "bruteforce", "grid") |
    grepl("_(exact|flat|bruteforce|grid)$", method) | exact_meta
}

selection_eligible_rows <- function(x) {
  if ("selection_eligible" %in% names(x)) {
    value <- suppressWarnings(as.logical(x$selection_eligible))
    value[is.na(value)] <- FALSE
    return(value)
  }
  x$complete_validation &
    (exact_family_rows(x) | (!is.na(x$target_met_all_runs) & x$target_met_all_runs))
}

robust_summary <- function(x, expected_seeds, expected_repeats) {
  if (!"dataset_md5" %in% names(x)) x$dataset_md5 <- NA_character_
  if (!"result_backend" %in% names(x)) x$result_backend <- NA_character_
  if (!"exact" %in% names(x)) x$exact <- NA
  columns <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k", "target_recall",
    "implementation", "implementation_version", "faissR_version",
    "faissR_package_commit",
    "faissR_image_commit", "method_id", "public_method", "kind", "n_threads",
    "result_backend"
  )
  for (name in setdiff(columns, names(x))) x[[name]] <- NA
  group_apply(x, columns, function(part) {
    success <- part$status == "success"
    times <- suppressWarnings(as.numeric(part$time_sec[success]))
    recalls <- suppressWarnings(as.numeric(part$recall_at_k[success]))
    memory_valid <- if ("memory_valid_for_comparison" %in% names(part)) {
      value <- suppressWarnings(as.logical(part$memory_valid_for_comparison))
      success & !is.na(value) & value
    } else {
      rep(FALSE, nrow(part))
    }
    memory <- suppressWarnings(as.numeric(part$peak_rss_gb[memory_valid]))
    gpu_memory <- if ("gpu_memory_peak_mib" %in% names(part)) {
      suppressWarnings(as.numeric(part$gpu_memory_peak_mib[success]))
    } else {
      numeric()
    }
    copies <- suppressWarnings(as.numeric(part$host_copy_sec[success]))
    status_text <- tolower(paste(
      as.character(part$status),
      if ("error" %in% names(part)) as.character(part$error) else ""
    ))
    target <- suppressWarnings(as.numeric(part$target_recall[[1L]]))
    seeds <- unique(part$validation_seed)
    seeds <- seeds[!is.na(seeds)]
    expected_runs <- expected_seeds * expected_repeats
    expected_repeat_ids <- seq_len(expected_repeats)
    observed_pairs <- paste(part$validation_seed, part$repeat_id, sep = "\r")
    complete <- length(seeds) == expected_seeds &&
      nrow(part) == expected_runs &&
      !anyDuplicated(observed_pairs) &&
      all(success) &&
      all(vapply(seeds, function(seed) {
        identical(
          sort(as.integer(part$repeat_id[part$validation_seed == seed])),
          expected_repeat_ids
        )
      }, logical(1L)))
    exact_family <- all(exact_family_rows(part))
    tie_values <- if ("tie_aware_exact_pass" %in% names(part)) {
      suppressWarnings(as.logical(part$tie_aware_exact_pass[success]))
    } else {
      logical()
    }
    direct_exact_audit_available <- length(tie_values) == expected_runs &&
      all(!is.na(tie_values))
    exact_audited <- complete && exact_family &&
      (!direct_exact_audit_available || all(tie_values))
    overlap_target_met <- complete && length(recalls) == expected_runs &&
      all(is.finite(recalls) & recalls >= target)
    approximate_target_met <- if (exact_audited) NA else overlap_target_met
    data.frame(
      part[1L, columns, drop = FALSE],
      n_rows = nrow(part),
      n_success = sum(success),
      n_failed = sum(!success),
      n_timeout = sum(grepl("timeout|timed out|time limit", status_text)),
      n_out_of_memory = sum(grepl("out.of.memory|out of memory|oom", status_text)),
      n_validation_seeds = length(seeds),
      expected_runs = expected_runs,
      complete_validation = complete,
      median_time_sec = if (any(is.finite(times))) median(times[is.finite(times)]) else NA_real_,
      iqr_time_sec = if (sum(is.finite(times)) > 1L) IQR(times[is.finite(times)]) else NA_real_,
      n_valid_host_memory_measurements = sum(is.finite(memory)),
      median_peak_rss_gb = if (any(is.finite(memory))) median(memory[is.finite(memory)]) else NA_real_,
      median_gpu_memory_peak_mib = if (any(is.finite(gpu_memory))) median(gpu_memory[is.finite(gpu_memory)]) else NA_real_,
      median_host_copy_sec = if (any(is.finite(copies))) median(copies[is.finite(copies)]) else NA_real_,
      mean_recall_at_k = if (any(is.finite(recalls))) mean(recalls[is.finite(recalls)]) else NA_real_,
      min_recall_at_k = if (any(is.finite(recalls))) min(recalls[is.finite(recalls)]) else NA_real_,
      mean_run_mean_query_recall_at_k = if (any(is.finite(recalls))) mean(recalls[is.finite(recalls)]) else NA_real_,
      min_run_mean_query_recall_at_k = if (any(is.finite(recalls))) min(recalls[is.finite(recalls)]) else NA_real_,
      target_recall_statistic = "mean_query_recall_at_k",
      target_recall_replicate_rule = "all_prespecified_validation_replicates",
      min_query_recall_role = "diagnostic_only",
      set_overlap_target_met_all_runs = overlap_target_met,
      target_met_all_runs = overlap_target_met,
      target_attained_all_validation_replicates = overlap_target_met,
      exact_family = exact_family,
      exact_audited = exact_audited,
      exact_audit_basis = if (exact_audited && direct_exact_audit_available) {
        "heldout_identifier_or_sorted_distance_multiset"
      } else if (exact_audited) {
        "exhaustive_route_plus_frozen_reference_audit"
      } else {
        "not_exact_audited"
      },
      approximate_target_met = approximate_target_met,
      quality_class = if (exact_audited) "exact-audited" else "approximate",
      selection_eligible = complete &&
        (exact_audited || isTRUE(approximate_target_met)),
      selection_eligibility_basis = if (exact_audited) {
        "exact_audited"
      } else if (isTRUE(approximate_target_met)) {
        "approximate_target_met"
      } else {
        "ineligible"
      },
      stringsAsFactors = FALSE
    )
  })
}

finite_quantile <- function(x, probability) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  unname(quantile(x, probability, names = FALSE, type = 7L))
}

selection_route_identity <- function(x) {
  public <- tolower(as.character(x$public_method))
  method <- tolower(as.character(x$method_id))
  route <- ifelse(!is.na(public) & nzchar(public), public, method)
  exact <- exact_family_rows(x)
  provider <- if ("result_backend" %in% names(x)) {
    tolower(as.character(x$result_backend))
  } else {
    rep(NA_character_, nrow(x))
  }
  provider[is.na(provider) | !nzchar(provider)] <- "unspecified_provider"
  route[exact] <- paste("exact_family", provider[exact], sep = "::")
  route
}

selection_stability <- function(x, expected_seeds, expected_repeats) {
  required <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall", "validation_seed", "repeat_id", "implementation",
    "method_id", "public_method", "status", "time_sec", "recall_at_k",
    "result_backend", "resolved_backend", "auto_predicted_method", "exact"
  )
  for (name in setdiff(required, names(x))) x[[name]] <- NA
  x <- x[x$implementation == "faissR", , drop = FALSE]
  if (!nrow(x)) return(list(
    replicates = data.frame(), cells = data.frame(), summary = data.frame()
  ))

  replicate_keys <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall", "validation_seed", "repeat_id"
  )
  replicates <- group_apply(x, replicate_keys, function(part) {
    success <- part$status == "success"
    is_auto <- tolower(as.character(part$public_method)) == "auto"
    is_auto[is.na(is_auto)] <- FALSE
    explicit <- part[success & !is_auto, , drop = FALSE]
    target <- suppressWarnings(as.numeric(part$target_recall[[1L]]))
    if (nrow(explicit)) {
      recall <- suppressWarnings(as.numeric(explicit$recall_at_k))
      eligible <- exact_family_rows(explicit) |
        (is.finite(recall) & recall >= target)
      explicit <- explicit[eligible, , drop = FALSE]
    }
    if (nrow(explicit)) {
      explicit$selection_route <- selection_route_identity(explicit)
      explicit_time <- suppressWarnings(as.numeric(explicit$time_sec))
      explicit <- explicit[is.finite(explicit_time) & explicit_time > 0, , drop = FALSE]
      if (nrow(explicit)) {
        explicit_time <- suppressWarnings(as.numeric(explicit$time_sec))
        explicit <- explicit[order(explicit_time, explicit$selection_route), , drop = FALSE]
        explicit <- explicit[!duplicated(explicit$selection_route), , drop = FALSE]
      }
    }
    oracle <- if (nrow(explicit)) explicit[1L, , drop = FALSE] else explicit

    auto <- part[success & is_auto, , drop = FALSE]
    auto <- auto[order(suppressWarnings(as.numeric(auto$time_sec))), , drop = FALSE]
    auto <- if (nrow(auto)) auto[1L, , drop = FALSE] else auto
    auto_method <- if (nrow(auto)) {
      value <- tolower(as.character(auto$auto_predicted_method[[1L]]))
      if (is.na(value) || !nzchar(value)) tolower(as.character(auto$resolved_backend[[1L]])) else value
    } else {
      NA_character_
    }
    auto_exact <- !is.na(auto_method) && auto_method %in% c(
      "exact", "flat", "bruteforce", "grid"
    )
    auto_provider <- if (nrow(auto)) tolower(as.character(auto$result_backend[[1L]])) else NA_character_
    if (is.na(auto_provider) || !nzchar(auto_provider)) auto_provider <- "unspecified_provider"
    auto_route <- if (auto_exact) paste("exact_family", auto_provider, sep = "::") else auto_method
    auto_recall <- if (nrow(auto)) suppressWarnings(as.numeric(auto$recall_at_k[[1L]])) else NA_real_
    auto_eligible <- nrow(auto) == 1L &&
      (auto_exact || (is.finite(auto_recall) && auto_recall >= target))
    auto_time <- if (nrow(auto)) suppressWarnings(as.numeric(auto$time_sec[[1L]])) else NA_real_
    oracle_time <- if (nrow(oracle)) suppressWarnings(as.numeric(oracle$time_sec[[1L]])) else NA_real_
    oracle_route <- if (nrow(oracle)) oracle$selection_route[[1L]] else NA_character_

    data.frame(
      part[1L, replicate_keys, drop = FALSE],
      oracle_route = oracle_route,
      oracle_method_id = if (nrow(oracle)) oracle$method_id[[1L]] else NA_character_,
      oracle_time_sec = oracle_time,
      auto_route = auto_route,
      auto_predicted_method = auto_method,
      auto_time_sec = auto_time,
      auto_recall_at_k = auto_recall,
      auto_target_met = auto_eligible,
      auto_oracle_route_agreement = !is.na(auto_route) && !is.na(oracle_route) &&
        identical(auto_route, oracle_route),
      auto_over_oracle = if (auto_eligible && is.finite(auto_time) && auto_time > 0 &&
        is.finite(oracle_time) && oracle_time > 0) auto_time / oracle_time else NA_real_,
      stringsAsFactors = FALSE
    )
  })

  cell_keys <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall"
  )
  expected_runs <- expected_seeds * expected_repeats
  cells <- group_apply(replicates, cell_keys, function(part) {
    oracle <- part$oracle_route[!is.na(part$oracle_route) & nzchar(part$oracle_route)]
    auto <- part$auto_route[!is.na(part$auto_route) & nzchar(part$auto_route)]
    modal <- function(value) {
      if (!length(value)) return(c(route = NA_character_, count = NA_character_))
      tab <- sort(table(value), decreasing = TRUE)
      winners <- sort(names(tab)[tab == max(tab)])
      c(route = winners[[1L]], count = as.character(max(tab)))
    }
    oracle_mode <- modal(oracle)
    auto_mode <- modal(auto)
    ratios <- suppressWarnings(as.numeric(part$auto_over_oracle))
    auto_times <- suppressWarnings(as.numeric(part$auto_time_sec))
    auto_times <- auto_times[is.finite(auto_times) & auto_times > 0]
    data.frame(
      part[1L, cell_keys, drop = FALSE],
      expected_replicates = expected_runs,
      observed_replicates = nrow(part),
      complete_replicates = sum(!is.na(part$oracle_route) & !is.na(part$auto_route)),
      oracle_unique_routes = length(unique(oracle)),
      oracle_modal_route = oracle_mode[["route"]],
      oracle_modal_count = suppressWarnings(as.integer(oracle_mode[["count"]])),
      oracle_modal_fraction = if (length(oracle)) as.integer(oracle_mode[["count"]]) / length(oracle) else NA_real_,
      oracle_route_switch_fraction = if (length(oracle)) 1 - as.integer(oracle_mode[["count"]]) / length(oracle) else NA_real_,
      auto_unique_routes = length(unique(auto)),
      auto_modal_route = auto_mode[["route"]],
      auto_modal_fraction = if (length(auto)) as.integer(auto_mode[["count"]]) / length(auto) else NA_real_,
      auto_target_attainment_fraction = mean(part$auto_target_met, na.rm = TRUE),
      auto_oracle_route_agreement_fraction = mean(part$auto_oracle_route_agreement, na.rm = TRUE),
      median_auto_over_oracle = if (any(is.finite(ratios))) median(ratios[is.finite(ratios)]) else NA_real_,
      q1_auto_over_oracle = finite_quantile(ratios, 0.25),
      q3_auto_over_oracle = finite_quantile(ratios, 0.75),
      auto_runtime_cv = if (length(auto_times) > 1L && mean(auto_times) > 0) {
        stats::sd(auto_times) / mean(auto_times)
      } else {
        NA_real_
      },
      stability_definition = "validation_replicate_oracle_route_modal_frequency",
      stringsAsFactors = FALSE
    )
  })

  summary_keys <- c("backend", "metric", "target_recall")
  summary <- group_apply(cells, summary_keys, function(part) {
    complete <- part$observed_replicates == part$expected_replicates &
      part$complete_replicates == part$expected_replicates
    stable <- complete & part$oracle_unique_routes == 1L
    data.frame(
      part[1L, summary_keys, drop = FALSE],
      expected_cells = nrow(part),
      complete_cells = sum(complete),
      stable_oracle_route_cells = sum(stable),
      stable_oracle_route_fraction = if (any(complete)) mean(stable[complete]) else NA_real_,
      median_oracle_modal_fraction = if (any(complete)) median(part$oracle_modal_fraction[complete], na.rm = TRUE) else NA_real_,
      median_oracle_route_switch_fraction = if (any(complete)) median(part$oracle_route_switch_fraction[complete], na.rm = TRUE) else NA_real_,
      deterministic_auto_route_fraction = if (any(complete)) mean(part$auto_unique_routes[complete] == 1L) else NA_real_,
      median_auto_target_attainment_fraction = if (any(complete)) median(part$auto_target_attainment_fraction[complete], na.rm = TRUE) else NA_real_,
      median_auto_oracle_route_agreement_fraction = if (any(complete)) median(part$auto_oracle_route_agreement_fraction[complete], na.rm = TRUE) else NA_real_,
      median_auto_over_oracle = if (any(complete)) median(part$median_auto_over_oracle[complete], na.rm = TRUE) else NA_real_,
      median_auto_runtime_cv = if (any(complete)) median(part$auto_runtime_cv[complete], na.rm = TRUE) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  list(replicates = replicates, cells = cells, summary = summary)
}

pair_auto_with_external <- function(summary) {
  keys <- c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall"
  )
  group_apply(summary, keys, function(part) {
    auto_flag <- part$implementation == "faissR" &
      tolower(as.character(part$public_method)) == "auto"
    auto_flag[is.na(auto_flag)] <- FALSE
    external_flag <- part$implementation != "faissR"
    external_flag[is.na(external_flag)] <- FALSE
    auto <- part[auto_flag, , drop = FALSE]
    external <- part[external_flag, , drop = FALSE]
    if (!nrow(external)) return(NULL)

    auto_unique <- nrow(auto) == 1L
    auto_complete <- auto_unique && isTRUE(auto$complete_validation[[1L]])
    auto_eligible <- auto_unique && isTRUE(selection_eligible_rows(auto)[[1L]])
    auto_time <- if (auto_unique) auto$median_time_sec[[1L]] else NA_real_

    do.call(rbind, lapply(seq_len(nrow(external)), function(i) {
      comparator <- external[i, , drop = FALSE]
      comparator_complete <- isTRUE(comparator$complete_validation[[1L]])
      comparator_eligible <- isTRUE(selection_eligible_rows(comparator)[[1L]])
      comparator_time <- comparator$median_time_sec[[1L]]
      paired <- auto_eligible && comparator_eligible &&
        is.finite(auto_time) && auto_time > 0 &&
        is.finite(comparator_time) && comparator_time > 0
      comparator_id <- paste(
        comparator$implementation[[1L]], comparator$method_id[[1L]], sep = "::"
      )
      data.frame(
        part[1L, keys, drop = FALSE],
        comparison_type = "faissR_auto_vs_external",
        comparator_id = comparator_id,
        faissr_method = if (auto_unique) auto$method_id[[1L]] else NA_character_,
        comparator_method = comparator$method_id[[1L]],
        faissr_time_sec = auto_time,
        comparator_time_sec = comparator_time,
        faissr_complete = auto_complete,
        comparator_complete = comparator_complete,
        faissr_eligible = auto_eligible,
        comparator_eligible = comparator_eligible,
        faissr_timeouts = if (auto_unique) auto$n_timeout[[1L]] else NA_integer_,
        comparator_timeouts = comparator$n_timeout[[1L]],
        faissr_out_of_memory = if (auto_unique) auto$n_out_of_memory[[1L]] else NA_integer_,
        comparator_out_of_memory = comparator$n_out_of_memory[[1L]],
        paired = paired,
        paired_ratio = if (paired) comparator_time / auto_time else NA_real_,
        ratio_definition = "comparator_time/faissR_auto_time",
        ratio_interpretation = "greater_than_one_favors_faissR",
        pair_status = if (!auto_unique) {
          "missing_or_ambiguous_faissR_auto"
        } else if (!auto_complete) {
          "faissR_auto_incomplete"
        } else if (!auto_eligible) {
          "faissR_auto_ineligible"
        } else if (!comparator_complete) {
          "comparator_incomplete"
        } else if (!comparator_eligible) {
          "comparator_ineligible"
        } else if (!paired) {
          "nonpositive_or_missing_time"
        } else {
          "paired"
        },
        stringsAsFactors = FALSE
      )
    }))
  })
}

pair_auto_with_oracle <- function(best) {
  auto_time <- suppressWarnings(as.numeric(best$auto_time_sec))
  oracle_time <- suppressWarnings(as.numeric(best$faissr_oracle_time_sec))
  paired <- is.finite(auto_time) & auto_time > 0 &
    is.finite(oracle_time) & oracle_time > 0
  data.frame(
    best[, c(
      "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
      "target_recall"
    ), drop = FALSE],
    comparison_type = "faissR_auto_vs_oracle",
    comparator_id = "faissR_empirical_oracle",
    faissr_method = best$auto_method,
    comparator_method = best$faissr_oracle_method,
    faissr_time_sec = auto_time,
    comparator_time_sec = oracle_time,
    faissr_complete = !is.na(best$auto_method),
    comparator_complete = !is.na(best$faissr_oracle_method),
    faissr_eligible = !is.na(best$auto_method),
    comparator_eligible = !is.na(best$faissr_oracle_method),
    faissr_timeouts = NA_integer_,
    comparator_timeouts = NA_integer_,
    faissr_out_of_memory = NA_integer_,
    comparator_out_of_memory = NA_integer_,
    paired = paired,
    paired_ratio = ifelse(paired, auto_time / oracle_time, NA_real_),
    ratio_definition = "faissR_auto_time/faissR_oracle_time",
    ratio_interpretation = "greater_than_one_favors_oracle",
    pair_status = ifelse(paired, "paired", "auto_or_oracle_unavailable"),
    stringsAsFactors = FALSE
  )
}

summarize_pairs_by_dataset <- function(pairs) {
  keys <- c(
    "comparison_type", "backend", "metric", "comparator_id", "dataset",
    "dataset_md5", "dataset_suite", "ratio_definition", "ratio_interpretation"
  )
  group_apply(pairs, keys, function(part) {
    ratios <- part$paired_ratio[part$paired & is.finite(part$paired_ratio)]
    data.frame(
      part[1L, keys, drop = FALSE],
      n_expected_cells = nrow(part),
      n_paired_cells = length(ratios),
      n_unpaired_cells = nrow(part) - length(ratios),
      n_faissr_timeouts = sum(part$faissr_timeouts, na.rm = TRUE),
      n_comparator_timeouts = sum(part$comparator_timeouts, na.rm = TRUE),
      n_faissr_out_of_memory = sum(part$faissr_out_of_memory, na.rm = TRUE),
      n_comparator_out_of_memory = sum(part$comparator_out_of_memory, na.rm = TRUE),
      dataset_median_paired_ratio = if (length(ratios)) median(ratios) else NA_real_,
      dataset_q1_paired_ratio = finite_quantile(ratios, 0.25),
      dataset_q3_paired_ratio = finite_quantile(ratios, 0.75),
      dataset_min_paired_ratio = if (length(ratios)) min(ratios) else NA_real_,
      dataset_max_paired_ratio = if (length(ratios)) max(ratios) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
}

summarize_pairs_across_datasets <- function(dataset_pairs) {
  keys <- c(
    "comparison_type", "backend", "metric", "comparator_id",
    "ratio_definition", "ratio_interpretation"
  )
  group_apply(dataset_pairs, keys, function(part) {
    ratios <- part$dataset_median_paired_ratio[
      is.finite(part$dataset_median_paired_ratio)
    ]
    data.frame(
      part[1L, keys, drop = FALSE],
      n_datasets_expected = nrow(part),
      n_datasets_paired = length(ratios),
      n_cells_expected = sum(part$n_expected_cells),
      n_cells_paired = sum(part$n_paired_cells),
      n_cells_unpaired = sum(part$n_unpaired_cells),
      n_faissr_timeouts = sum(part$n_faissr_timeouts),
      n_comparator_timeouts = sum(part$n_comparator_timeouts),
      n_faissr_out_of_memory = sum(part$n_faissr_out_of_memory),
      n_comparator_out_of_memory = sum(part$n_comparator_out_of_memory),
      median_dataset_paired_ratio = if (length(ratios)) median(ratios) else NA_real_,
      q1_dataset_paired_ratio = finite_quantile(ratios, 0.25),
      q3_dataset_paired_ratio = finite_quantile(ratios, 0.75),
      min_dataset_paired_ratio = if (length(ratios)) min(ratios) else NA_real_,
      max_dataset_paired_ratio = if (length(ratios)) max(ratios) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
}

rank_qualifying <- function(summary) {
  keys <- c("dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k", "target_recall")
  group_apply(summary, keys, function(part) {
    qualifying <- part[selection_eligible_rows(part) &
      is.finite(part$median_time_sec), , drop = FALSE]
    qualifying <- qualifying[order(qualifying$median_time_sec, qualifying$method_id), , drop = FALSE]
    is_faissr_auto <- qualifying$implementation == "faissR" &
      qualifying$public_method == "auto"
    is_faissr_auto[is.na(is_faissr_auto)] <- FALSE
    auto <- qualifying[is_faissr_auto, , drop = FALSE]
    overall <- qualifying[!is_faissr_auto, , drop = FALSE]
    exact_family <- exact_family_rows(overall)
    provider <- as.character(overall$result_backend)
    provider[is.na(provider) | !nzchar(provider)] <- overall$method_id[
      is.na(provider) | !nzchar(provider)
    ]
    route_identity <- ifelse(
      exact_family,
      paste(
        "exact_family", overall$implementation, overall$backend,
        overall$metric, provider, sep = "::"
      ),
      paste("method", overall$method_id, sep = "::")
    )
    overall <- overall[!duplicated(route_identity), , drop = FALSE]
    faissr_oracle <- overall[
      overall$implementation == "faissR",
      ,
      drop = FALSE
    ]
    exact <- overall[
      exact_family_rows(overall), , drop = FALSE
    ]
    pick <- function(tbl, i, column, default = NA) {
      if (nrow(tbl) < i) default else tbl[[column]][[i]]
    }
    data.frame(
      part[1L, keys, drop = FALSE],
      n_complete_methods = sum(part$complete_validation),
      n_qualifying_methods = nrow(qualifying),
      fastest_method = pick(overall, 1L, "method_id", NA_character_),
      fastest_time_sec = pick(overall, 1L, "median_time_sec", NA_real_),
      fastest_recall = pick(overall, 1L, "min_recall_at_k", NA_real_),
      second_method = pick(overall, 2L, "method_id", NA_character_),
      second_time_sec = pick(overall, 2L, "median_time_sec", NA_real_),
      exact_baseline_method = pick(exact, 1L, "method_id", NA_character_),
      exact_baseline_time_sec = pick(exact, 1L, "median_time_sec", NA_real_),
      faissr_oracle_method = pick(
        faissr_oracle, 1L, "method_id", NA_character_
      ),
      faissr_oracle_time_sec = pick(
        faissr_oracle, 1L, "median_time_sec", NA_real_
      ),
      faissr_oracle_recall = pick(
        faissr_oracle, 1L, "min_recall_at_k", NA_real_
      ),
      faissr_oracle_provider = pick(
        faissr_oracle, 1L, "result_backend", NA_character_
      ),
      auto_method = pick(auto, 1L, "method_id", NA_character_),
      auto_time_sec = pick(auto, 1L, "median_time_sec", NA_real_),
      auto_recall = pick(auto, 1L, "min_recall_at_k", NA_real_),
      auto_provider = pick(auto, 1L, "result_backend", NA_character_),
      auto_recall_difference = if (nrow(auto) && nrow(faissr_oracle)) {
        auto$min_recall_at_k[[1L]] - faissr_oracle$min_recall_at_k[[1L]]
      } else {
        NA_real_
      },
      auto_provider_agreement = if (nrow(auto) && nrow(faissr_oracle)) {
        identical(
          as.character(auto$result_backend[[1L]]),
          as.character(faissr_oracle$result_backend[[1L]])
        )
      } else {
        NA
      },
      auto_over_oracle = if (nrow(auto) && nrow(faissr_oracle)) {
        auto$median_time_sec[[1L]] / faissr_oracle$median_time_sec[[1L]]
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  })
}

route_audit <- function(x) {
  success <- x$status == "success"
  auditable <- success & x$implementation == "faissR" &
    !is.na(x$result_backend) & nzchar(x$result_backend)
  requested_backend_bad <- success & !is.na(x$requested_backend) &
    nzchar(x$requested_backend) & x$requested_backend != x$backend
  resolved <- tolower(as.character(x$result_backend))
  cpu_bad <- auditable & x$backend == "cpu" & grepl("cuda|gpu|cuvs", resolved)
  cuda_bad <- auditable & x$backend == "cuda" & !grepl("cuda|gpu|cuvs", resolved)
  requested_method_bad <- success & x$implementation == "faissR" &
    !is.na(x$public_method) & !is.na(x$requested_method) &
    nzchar(x$requested_method) & x$requested_method != x$public_method
  bad <- requested_backend_bad | cpu_bad | cuda_bad | requested_method_bad
  out <- x[bad, , drop = FALSE]
  if (nrow(out)) {
    out$route_audit_reason <- paste(
      ifelse(requested_backend_bad[bad], "requested_backend_mismatch", ""),
      ifelse(cpu_bad[bad] | cuda_bad[bad], "resolved_device_mismatch", ""),
      ifelse(requested_method_bad[bad], "requested_method_mismatch", ""),
      sep = ";"
    )
  }
  out
}

compliance_table <- function(summary) {
  columns <- c("backend", "metric", "target_recall")
  group_apply(summary, columns, function(part) data.frame(
    part[1L, columns, drop = FALSE],
    evaluated_cells = nrow(part),
    complete_cells = sum(part$complete_validation),
    exact_audited_cells = sum(part$complete_validation & part$exact_audited),
    approximate_target_met_cells = sum(
      part$complete_validation & !part$exact_audited &
        !is.na(part$approximate_target_met) & part$approximate_target_met
    ),
    selection_eligible_cells = sum(selection_eligible_rows(part)),
    set_overlap_target_met_cells = sum(
      part$complete_validation & part$set_overlap_target_met_all_runs
    ),
    target_met_cells = sum(part$complete_validation & part$target_met_all_runs),
    completion_fraction = mean(part$complete_validation),
    target_attainment_fraction = if (any(part$complete_validation))
      mean(part$target_met_all_runs[part$complete_validation]) else NA_real_,
    stringsAsFactors = FALSE
  ))
}

write_report <- function(out_dir, files, combined, summary, best, route_errors,
                         paired_summary, stability) {
  lines <- c(
    "# Held-out publication evidence",
    "",
    paste0("- Source result files: ", length(files), "."),
    paste0("- Selected result rows: ", nrow(combined), "."),
    paste0("- Robust method cells: ", nrow(summary), "."),
    paste0("- Complete validation cells: ", sum(summary$complete_validation), "."),
    paste0("- Exact-audited cells: ", sum(summary$complete_validation & summary$exact_audited), "."),
    paste0("- Approximate cells meeting target in every prespecified replicate: ", sum(summary$complete_validation & !summary$exact_audited & !is.na(summary$approximate_target_met) & summary$approximate_target_met), "."),
    paste0("- Selection-eligible cells: ", sum(selection_eligible_rows(summary)), "."),
    paste0("- Successful route mismatches: ", nrow(route_errors), "."),
    "",
    "A complete exhaustive route is eligible after its exactness audit passes: identical neighbour identifiers or an equivalent sorted distance multiset within the frozen tolerance. An approximate route is eligible only when every replicate's mean query-level recall@k reaches the target. Raw set overlap and minimum query recall remain diagnostics for exact routes and cannot make an audited exhaustive route ineligible. Failed, timed-out, unsupported, duplicated, incomplete, and route-mismatched rows remain in the archive.",
    "",
    "Paired performance is the primary timing analysis. Ratios are first computed within identical dataset x metric x k x target cells, then reduced to one median ratio per dataset, and only then summarized across datasets. Thus each dataset is the primary, equally weighted unit. External ratios are comparator_time/faissR_auto_time (>1 favors faissR); selector-regret ratios are faissR_auto_time/faissR_oracle_time (>1 favors the oracle). Unpaired cells, timeouts, and out-of-memory failures remain in the denominators and count columns. Host-memory medians require an explicit fresh-process validity flag; shared-process VmHWM observations and historical rows without the flag are excluded.",
    "",
    paste0("Paired dataset-level summary rows: ", nrow(paired_summary), "."),
    paste0("Selection-stability cells: ", nrow(stability$cells), "."),
    paste0("Complete selection-stability cells: ", sum(
      stability$cells$observed_replicates == stability$cells$expected_replicates &
        stability$cells$complete_replicates == stability$cells$expected_replicates
    ), "."),
    "Selection stability is descriptive. Within each independent validation seed by timing-repeat block, the fastest eligible explicit faissR route is reconstructed. Modal-route frequency, switch frequency, auto/oracle agreement, target retention, runtime coefficient of variation, and auto/oracle timing ratios quantify whether the calibration-informed choice survives independent repetition. The original wide grids were not independently refitted, so these outputs do not claim configuration-level reselection probabilities.",
    "",
    paste0("Complete fastest/second-fastest blocks: ", sum(!is.na(best$fastest_method)), " of ", nrow(best), ".")
  )
  writeLines(lines, file.path(out_dir, "JSS_EVIDENCE_REPORT.md"))
}

main <- function() {
  args <- parse_args()
  root <- normalizePath(args$results_root %||% ".", mustWork = TRUE)
  out_dir <- normalizePath(args$out_dir %||% file.path(root, "analysis"), mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  backend <- tolower(args$backend %||% "all")
  if (!backend %in% c("all", "cpu", "cuda")) stop("`backend` must be all, cpu, or cuda.", call. = FALSE)
  targets <- as.numeric(split_values(args$target_recalls, "0.9,0.95,0.99"))
  expected_seeds <- as.integer(args$expected_seeds %||% 2L)
  expected_repeats <- as.integer(args$expected_repeats %||% 3L)
  datasets <- split_values(args$datasets, "")
  datasets <- datasets[nzchar(datasets)]
  metrics <- split_values(args$metrics, "euclidean,cosine,correlation")
  metrics <- metrics[nzchar(metrics)]

  files <- list.files(root, pattern = "^jmlr_tuned_benchmark_results[.]csv$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/calibration/|/analysis/", files)]
  if (!length(files)) stop("No held-out publication result files were found under `results_root`.", call. = FALSE)
  combined <- read_union(files)
  combined <- combined[combined$metric %in% metrics, , drop = FALSE]
  if (backend != "all") combined <- combined[combined$backend == backend, , drop = FALSE]
  if (length(datasets)) combined <- combined[combined$dataset %in% datasets, , drop = FALSE]
  if (!nrow(combined)) stop("No result rows match the requested backend.", call. = FALSE)
  combined <- latest_method_runs(combined)
  combined <- expand_external_targets(combined, targets)
  combined <- combined[order(combined$dataset, combined$backend, combined$metric, combined$k,
                             combined$target_recall, combined$method_id,
                             combined$validation_seed, combined$repeat_id), , drop = FALSE]
  summary <- robust_summary(combined, expected_seeds, expected_repeats)
  best <- rank_qualifying(summary)
  paired_cells <- rbind(
    pair_auto_with_external(summary),
    pair_auto_with_oracle(best)
  )
  paired_datasets <- summarize_pairs_by_dataset(paired_cells)
  paired_summary <- summarize_pairs_across_datasets(paired_datasets)
  routes <- route_audit(combined)
  compliance <- compliance_table(summary)
  stability <- selection_stability(combined, expected_seeds, expected_repeats)

  write.csv(combined, file.path(out_dir, "jss_publication_results_combined.csv"), row.names = FALSE)
  write.csv(combined[combined$status != "success", , drop = FALSE], file.path(out_dir, "jss_failures_and_unsupported.csv"), row.names = FALSE)
  write.csv(summary, file.path(out_dir, "jss_robust_method_summary.csv"), row.names = FALSE)
  write.csv(best, file.path(out_dir, "jss_fastest_second_exact_and_auto.csv"), row.names = FALSE)
  write.csv(best[, c(
    "dataset", "dataset_md5", "dataset_suite", "backend", "metric", "k",
    "target_recall", "faissr_oracle_method", "faissr_oracle_time_sec",
    "faissr_oracle_recall", "faissr_oracle_provider", "auto_method",
    "auto_time_sec", "auto_recall", "auto_provider",
    "auto_recall_difference", "auto_provider_agreement", "auto_over_oracle"
  ), drop = FALSE],
            file.path(out_dir, "jss_auto_vs_oracle.csv"), row.names = FALSE)
  write.csv(paired_cells, file.path(out_dir, "jss_paired_performance_cells.csv"), row.names = FALSE)
  write.csv(paired_datasets, file.path(out_dir, "jss_paired_performance_by_dataset.csv"), row.names = FALSE)
  write.csv(paired_summary, file.path(out_dir, "jss_paired_performance_summary.csv"), row.names = FALSE)
  write.csv(compliance, file.path(out_dir, "jss_recall_compliance_table.csv"), row.names = FALSE)
  write.csv(routes, file.path(out_dir, "jss_successful_route_mismatches.csv"), row.names = FALSE)
  write.csv(stability$replicates, file.path(out_dir, "jss_selection_stability_replicates.csv"), row.names = FALSE)
  write.csv(stability$cells, file.path(out_dir, "jss_selection_stability_cells.csv"), row.names = FALSE)
  write.csv(stability$summary, file.path(out_dir, "jss_selection_stability_summary.csv"), row.names = FALSE)
  focus <- best[best$k == 30L & abs(best$target_recall - 0.99) < 1e-12, , drop = FALSE]
  write.csv(focus, file.path(out_dir, "jss_main_table_k30_recall099.csv"), row.names = FALSE)
  write_report(out_dir, files, combined, summary, best, routes, paired_summary, stability)
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  outputs <- list.files(out_dir, full.names = TRUE)
  outputs <- outputs[!file.info(outputs)$isdir]
  checksums <- data.frame(file = basename(outputs), md5 = unname(tools::md5sum(outputs)), stringsAsFactors = FALSE)
  write.csv(checksums, file.path(out_dir, "checksums.csv"), row.names = FALSE)
  cat("Wrote held-out evidence to ", out_dir, "\n", sep = "")
}

if (!identical(Sys.getenv("FAISSR_JSS_AGGREGATE_SOURCE_ONLY", unset = ""), "true")) main()
