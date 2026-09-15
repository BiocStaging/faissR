#!/usr/bin/env Rscript

# Recompute the reported tuned-HNSW and query-workload evidence without a GPU.
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- gsub("~+~", " ", sub("^--file=", "", arg[[1L]]), fixed = TRUE)
here <- dirname(normalizePath(script, mustWork = TRUE))
repo <- dirname(dirname(here))
bundle <- file.path(here, "completed_systems", "results.tar.gz")
expected <- strsplit(readLines(file.path(here, "completed_systems",
                                         "checksums.sha256"))[[1L]], "\\s+")[[1L]][[1L]]
command <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
args <- if (command == "shasum") c("-a", "256", bundle) else bundle
observed <- sub("[[:space:]].*$", "",
                system2(command, shQuote(args), stdout = TRUE)[[1L]])
stopifnot(identical(observed, expected))
out <- Sys.getenv("FAISSR_JSS_SYSTEMS_OUT", tempfile("faissR-systems-"))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
members <- utils::untar(bundle, list = TRUE)
stopifnot(!any(grepl("(^/|(^|/)\\.\\.(/|$))", members)))
work_dir <- tempfile("verified-input-", tmpdir = out)
dir.create(work_dir)
stopifnot(utils::untar(bundle, exdir = work_dir) == 0L)
validation <- file.path(repo, "benchmark_scripts", "jss_reproduction", "validation")
run <- function(script, args) {
    status <- system2("Rscript", shQuote(c(script, args)))
    if (status != 0L) stop("Audit failed: ", script)
}
roots <- list.dirs(file.path(work_dir, "paired_cpu_hnsw_pareto"), recursive = FALSE)
stopifnot(length(roots) == 1L)
run(file.path(validation, "paired_cpu_hnsw_pareto", "audit_validation.R"),
    paste0("--root=", roots[[1L]]))
pairs <- read.csv(file.path(roots[[1L]], "validation_paired_summary.csv"))
stopifnot(nrow(pairs) == 72L, sum(pairs$both_target_met) == 63L,
          sum(pairs$both_fitted_target_met) == 63L)
validation_files <- list.files(
    file.path(roots[[1L]], "validation"),
    pattern = "^jss_paired_hnsw_raw[.]csv$",
    recursive = TRUE,
    full.names = TRUE
)
validation_runs <- do.call(rbind, lapply(validation_files, read.csv))
stopifnot(length(validation_files) == 72L, nrow(validation_runs) == 720L,
          all(validation_runs$status == "success"))
tuned <- do.call(rbind, lapply(split(pairs, pairs$comparator), function(x) {
    z <- x[x$both_target_met, ]
    f <- x[x$both_fitted_target_met, ]
    data.frame(comparator = x$comparator[[1L]], eligible_pairs = nrow(z),
               cold_median = median(z$comparator_over_faissR),
               build_median = median(f$comparator_over_faissR_build),
               fitted_query_median = median(f$comparator_over_faissR_fitted_query))
}))
stopifnot(isTRUE(all.equal(round(tuned$cold_median, 2), c(6.55, 1.67))))
write.csv(tuned, file.path(out, "tuned_hnsw_table.csv"), row.names = FALSE)
workloads <- list.dirs(file.path(work_dir, "query_workload"), recursive = FALSE)
stopifnot(length(workloads) == 2L)
work <- do.call(rbind, lapply(workloads, function(root) {
    run(file.path(validation, "query_workload", "audit_query_workload.R"), root)
    read.csv(file.path(root, "jss_query_workload_summary.csv"))
}))
stopifnot(nrow(work) == 120L, all(work$status == "complete"),
          sum(work$cache_hit_observed[work$backend == "cpu"]) == 60L,
          sum(work$cache_hit_observed[work$backend == "cuda"]) == 0L)
hnsw <- subset(work, backend == "cpu" & requested_method == "hnsw")
stopifnot(nrow(hnsw) == 15L, all(hnsw$warm_query_sec < hnsw$flat_cold_sec),
          median(hnsw$break_even_batches_vs_rebuilt_flat) == 13)
write.csv(work, file.path(out, "query_workload_cells.csv"), row.names = FALSE)
systems_evidence <- data.frame(
    evidence = c(
        "Independently tuned HNSW route runs",
        "Independently tuned HNSW target-matched provider pairs",
        "CPU query-workload cells",
        "CUDA query-workload cells"
    ),
    passing_or_completed = c(
        sum(validation_runs$status == "success"),
        sum(pairs$both_target_met),
        sum(work$backend == "cpu" & work$status == "complete"),
        sum(work$backend == "cuda" & work$status == "complete")
    ),
    total = c(
        nrow(validation_runs), nrow(pairs),
        sum(work$backend == "cpu"), sum(work$backend == "cuda")
    ),
    stringsAsFactors = FALSE
)
write.csv(
    systems_evidence,
    file.path(out, "completed_systems_evidence.csv"),
    row.names = FALSE
)
writeLines("COMPLETED SYSTEMS EVIDENCE AUDIT PASSED",
           file.path(out, "COMPLETED_SYSTEMS_AUDIT.txt"))
print(tuned, row.names = FALSE)
cat("COMPLETED SYSTEMS EVIDENCE AUDIT PASSED\n")
