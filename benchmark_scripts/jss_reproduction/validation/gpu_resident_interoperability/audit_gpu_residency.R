#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- sub("^--root=", "", args[grepl("^--root=", args)])
root <- normalizePath(root, mustWork = TRUE)
files <- list.files(
  root, "jss_gpu_resident_interoperability_raw[.]csv$",
  recursive = TRUE, full.names = TRUE
)
if (length(files) != 15L) {
  stop("Expected 15 GPU result files; found ", length(files), ".")
}
x <- do.call(rbind, lapply(files, read.csv, stringsAsFactors = FALSE))
if (nrow(x) != 75L) stop("Expected 75 repetitions; found ", nrow(x), ".")
x$contract_pass <- x$status == "success" &
  x$result_residency_before_copy == "cuda" &
  x$device_to_host_copies_before_copy == 0L &
  x$host_result_dimensions_pass & x$c_api_consumer_pass &
  x$c_api_version == 1L & is.finite(x$checksum_index) &
  is.finite(x$checksum_distance) & x$consumer_host_bytes == 16

keys <- c("dataset", "requested_query_n", "query_n", "k")
summary <- do.call(rbind, lapply(
  split(x, interaction(x[keys], drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    z[1L, keys, drop = FALSE],
    repetitions = nrow(z), successes = sum(z$status == "success"),
    contract_passes = sum(z$contract_pass),
    median_search_sec = median(z$search_sec[z$status == "success"]),
    median_resident_consumer_sec =
      median(z$resident_consumer_sec[z$status == "success"]),
    median_explicit_host_copy_sec =
      median(z$explicit_host_copy_sec[z$status == "success"]),
    median_host_copy_over_consumer = median(
      z$explicit_host_copy_sec[z$status == "success"] /
        z$resident_consumer_sec[z$status == "success"]
    ),
    median_device_result_bytes =
      median(z$device_result_bytes[z$status == "success"]),
    median_device_peak_mib = median(
      z$device_peak_mib[z$status == "success"], na.rm = TRUE
    ),
    median_host_peak_rss_kib = median(
      z$host_peak_rss_kib[z$status == "success"], na.rm = TRUE
    ),
    stringsAsFactors = FALSE
  )
))
write.csv(summary, file.path(root, "jss_gpu_resident_interoperability_summary.csv"),
          row.names = FALSE)
write.csv(x[!x$contract_pass, ],
          file.path(root, "jss_gpu_resident_interoperability_failures.csv"),
          row.names = FALSE)

report <- c(
  "# GPU-resident interoperability audit", "",
  sprintf("Result files: %d / 15.", length(files)),
  sprintf("Repetitions: %d / 75.", nrow(x)),
  sprintf("Successful route runs: %d / 75.", sum(x$status == "success")),
  sprintf("Residency and C-ABI contract passes: %d / 75.", sum(x$contract_pass)),
  "",
  "The resident-consumer phase launches a downstream CUDA kernel over both",
  "device buffers and copies only two checksum scalars to the host. The host",
  "phase explicitly materializes both complete neighbor matrices. These are",
  "transfer-decomposition measurements of the same faissR GPU result, not an",
  "algorithm comparison against a host-resident route."
)
writeLines(report, file.path(root, "JSS_GPU_RESIDENT_INTEROPERABILITY_REPORT.md"))
cat(paste(report, collapse = "\n"), "\n")
if (!all(x$contract_pass)) stop("GPU residency/interoperability audit failed.")
cat("GPU RESIDENCY/INTEROPERABILITY AUDIT PASSED\n")
