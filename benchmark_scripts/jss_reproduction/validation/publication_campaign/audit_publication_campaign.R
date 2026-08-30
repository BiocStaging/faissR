#!/usr/bin/env Rscript

parse_args <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[pair[[1L]]]] <- paste(pair[-1L], collapse = "=")
  }
  if (is.null(out$root) || is.null(out$out_dir)) {
    stop("Provide --root and --out_dir.", call. = FALSE)
  }
  out
}

args <- parse_args()
specification <- data.frame(
  module = c(
    "r_comparison", "hnsw_pareto", "query_workload_cpu",
    "query_workload_cuda", "calibration_confirmation", "recall_inference",
    "gpu_interoperability", "resource_memory_cpu", "resource_memory_cuda"
  ),
  report = c(
    "JSS_COMPREHENSIVE_R_COMPARISON_REPORT.md",
    "JSS_PAIRED_CPU_HNSW_PARETO_REPORT.md",
    "JSS_QUERY_WORKLOAD_REPORT.md", "JSS_QUERY_WORKLOAD_REPORT.md",
    "JSS_CALIBRATION_CONFIRMATION_REPORT.md", "JSS_RECALL_INFERENCE_REPORT.md",
    "JSS_GPU_RESIDENT_INTEROPERABILITY_REPORT.md",
    "JSS_RESOURCE_MEMORY_REPORT.md", "JSS_RESOURCE_MEMORY_REPORT.md"
  ),
  path_hint = c(
    "comprehensive_r_comparison", "paired_cpu_hnsw_pareto",
    "query_workload/cpu_", "query_workload/cuda_", "calibration_confirmation",
    "recall_inference", "gpu_resident_interoperability",
    "resource_memory/cpu_", "resource_memory/cuda_"
  ), stringsAsFactors = FALSE
)

all_reports <- list.files(
  args$root, pattern = "[.]md$", recursive = TRUE, full.names = TRUE
)
rows <- lapply(seq_len(nrow(specification)), function(i) {
  candidates <- all_reports[
    basename(all_reports) == specification$report[[i]] &
      grepl(specification$path_hint[[i]], all_reports, fixed = TRUE)
  ]
  if (length(candidates)) {
    info <- file.info(candidates)
    selected <- candidates[[which.max(info$mtime)]]
    text <- paste(readLines(selected, warn = FALSE), collapse = "\n")
  } else {
    selected <- NA_character_
    text <- ""
  }
  data.frame(
    module = specification$module[[i]], report_found = length(candidates) > 0L,
    latest_report = selected,
    explicit_fail_marker = grepl("AUDIT FAILED|Design audit: FAIL", text),
    explicit_pass_marker = grepl(
      "AUDIT PASSED|Design audit: PASS|Complete cells:|Cells:", text
    ), stringsAsFactors = FALSE
  )
})
audit <- do.call(rbind, rows)
audit$ready_for_manuscript <- audit$report_found & !audit$explicit_fail_marker
dir.create(args$out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(audit, file.path(args$out_dir, "jss_publication_campaign_audit.csv"), row.names = FALSE)
report <- c(
  "# JSS publication campaign audit", "",
  sprintf("Modules with reports: %d / %d.", sum(audit$report_found), nrow(audit)),
  sprintf("Modules without an explicit failure marker: %d / %d.", sum(audit$ready_for_manuscript), nrow(audit)),
  "", capture.output(print(audit, row.names = FALSE)), "",
  "A report is necessary but not sufficient for publication. Before numerical",
  "claims are regenerated, inspect the module CSV manifest, Slurm exit states,",
  "package version, package commit, image checksum, and documented audit rule."
)
writeLines(report, file.path(args$out_dir, "JSS_PUBLICATION_CAMPAIGN_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!all(audit$ready_for_manuscript)) quit(status = 1L)
