#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    value <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[value[[1L]]]] <- paste(value[-1L], collapse = "=")
  }
  needed <- c("campaign_root", "analysis_dir", "out_dir")
  if (length(setdiff(needed, names(out)))) {
    stop("Required arguments: --campaign_root, --analysis_dir, --out_dir")
  }
  out
}

read_required <- function(path) {
  if (!file.exists(path)) stop("Missing table source: ", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

write_table <- function(x, number, slug, caption, out_dir) {
  filename <- sprintf("table_%02d_%s.csv", number, slug)
  utils::write.csv(x, file.path(out_dir, filename), row.names = FALSE, na = "")
  data.frame(
    table_number = number, file = filename, caption = caption,
    rows = nrow(x), columns = ncol(x), stringsAsFactors = FALSE
  )
}

pretty_dataset <- function(x) {
  x[x == "FlowRepository_FR-FCM-ZYRM_files"] <- "FR-FCM-ZYRM"
  x[x == "imagenet"] <- "ImageNet features"
  x
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
campaign_root <- normalizePath(args$campaign_root, mustWork = TRUE)
analysis_dir <- normalizePath(args$analysis_dir, mustWork = TRUE)
out_dir <- args$out_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

methods <- data.frame(
  public_method = c(
    "exact / flat / bruteforce", "grid", "hnsw", "ivf", "ivfpq",
    "ivfpq_fastscan", "cagra", "nndescent_style",
    "nsg_style / vamana_style"
  ),
  family = c(
    "exhaustive", "exact low-dimensional", "navigable graph",
    "inverted file", "IVF with product quantization",
    "fast accumulation IVF-PQ", "CUDA graph",
    "derived refinement or cuVS NN-descent",
    "package-owned derived refinements"
  ),
  principal_controls = c(
    "query batch and resource reuse", "cell width and query expansion",
    "graph degree; construction and search effort", "lists and probed lists",
    "lists; probes; subquantizers; code width",
    "IVF-PQ controls; block size; refinement",
    "graph degrees and search width", "candidate pool and iterations",
    "seed graph; degree; search breadth"
  ), stringsAsFactors = FALSE
)

datasets <- data.frame(
  dataset = c(
    "COIL20", "FashionMNIST", "flow18", "FR-FCM-ZYRM",
    "ImageNet features", "mass41", "MetRef", "MNIST", "USPS"
  ),
  rows = c(1440, 70000, 1000021, 5220347, 1281167, 965282, 873, 70000, 11000),
  variables = c(16384, 784, 11, 32, 1024, 14, 375, 784, 256),
  stringsAsFactors = FALSE
)

summary <- read_required(file.path(analysis_dir, "jss_robust_method_summary.csv"))
routes <- summary[summary$method_id %in% c("faissR_cuda_auto", "faissR_cpu_hnsw"), ]
heldout <- do.call(rbind, lapply(
  split(routes, interaction(routes$method_id, routes$metric, routes$target_recall,
                            drop = TRUE)),
  function(z) data.frame(
    route = if (z$method_id[[1L]] == "faissR_cuda_auto") "CUDA automatic" else "CPU HNSW",
    metric = z$metric[[1L]], target_recall = z$target_recall[[1L]],
    attained = sum(z$selection_eligible), total = nrow(z), stringsAsFactors = FALSE
  )
))
heldout <- heldout[order(heldout$route, heldout$metric, heldout$target_recall), ]

auto_cells_source <- read_required(file.path(
  analysis_dir, "cuda_auto_selection", "jss_cuda_auto_selection_cells.csv"
))
auto_selection <- as.data.frame(table(
  metric = auto_cells_source$metric,
  target_recall = auto_cells_source$target_recall,
  selected_method = auto_cells_source$selected_method
), stringsAsFactors = FALSE)
auto_selection <- auto_selection[auto_selection$Freq > 0L, ]
names(auto_selection)[[4L]] <- "n_cells"

per_cpu <- read_required(file.path(
  analysis_dir, "per_dataset", "jss_cpu_per_dataset_performance.csv"
))
per_cuda <- read_required(file.path(
  analysis_dir, "per_dataset", "jss_cuda_per_dataset_performance.csv"
))
selector_regret <- read_required(file.path(
  analysis_dir, "selector_regret", "jss_selector_regret_summary.csv"
))
ratio_row <- function(label, x) {
  x <- x[is.finite(x)]
  data.frame(
    comparison = label, datasets = length(x), median = stats::median(x),
    q1 = unname(stats::quantile(x, 0.25)), q3 = unname(stats::quantile(x, 0.75)),
    minimum = min(x), maximum = max(x), stringsAsFactors = FALSE
  )
}
paired <- rbind(
  ratio_row("CPU HNSW, prespecified interfaces", per_cpu$median_ratio_BiocNeighbors_over_faissR),
  ratio_row("CPU HNSW, recall-equivalent", per_cpu$median_recall_equivalent_ratio),
  ratio_row("CUDA automatic / exact", per_cuda$median_ratio_exact_over_auto),
  ratio_row("CUDA automatic / brute force", per_cuda$median_ratio_bruteforce_over_auto),
  ratio_row("CUDA automatic / CAGRA", per_cuda$median_ratio_cagra_over_auto),
  ratio_row("CUDA IVF-selected / exact", per_cuda$median_ratio_exact_over_ivf)
)

environment <- data.frame(
  component = c(
    "Operating system", "R", "Linear algebra", "CPU execution",
    "GPU execution", "NVIDIA driver",
    "Calibration/reference/held-out representation",
    "Controlled CPU provider representation",
    "faissR, calibration/validation snapshot", "faissR, controlled CPU comparison",
    "FAISS GPU/cuVS build", "RAPIDS cuVS", "CUDA toolkit",
    "External CPU comparators", "Frozen campaign container"
  ),
  configuration = c(
    "Debian GNU/Linux 13 (trixie) in Singularity",
    "4.5.3, x86_64-conda-linux-gnu", "OpenBLAS 0.3.33; LAPACK 3.12.0",
    "UCT ada partition; 12 requested threads per job",
    "NVIDIA L40S; 46,068 MiB; compute capability 8.9", "595.58.03",
    "Direct float32 input for timed calibration, reference, held-out, and CUDA selector rows",
    "Same R double matrix for both routes; faissR conversion included inside its timer",
    "0.99.21; commit 0903532baf02b340a90921db18edc4deae5ea462",
    "0.99.25; commit b33a70116887474a2ed70d84de0c80bb77e9db66",
    "1.14.3", "libcuvs 26.06", "13.2",
    "BiocNeighbors 2.4.0; RcppHNSW 0.7.0",
    "SHA-256 0cd4d0df406bd0075046b16d2e8a4d3ae78ee61d98e6d47c639986e28ea6f203"
  ), stringsAsFactors = FALSE
)

grid <- data.frame(
  method = c(
    "Exhaustive Flat/brute force", "Grid", "HNSW", "IVF", "IVF-PQ",
    "IVF-PQ FastScan", "CAGRA", "NN-descent-derived refinement",
    "NSG-/Vamana-derived refinements"
  ),
  tuned_quantities = c(
    "query batch size; threads; resource reuse", "cell width; expansion",
    "degree; construction effort; search effort", "lists; probed lists",
    "IVF controls; subquantizers; code width; query batch",
    "IVF-PQ controls; block size; refinement",
    "graph degree; intermediate degree; build strategy; search width",
    "candidate pool; degree; iterations", "seed size; output degree; search breadth"
  ), stringsAsFactors = FALSE
)

stability_dir <- file.path(analysis_dir, "calibration_stability")
missing <- read_required(file.path(
  stability_dir, "jss_calibration_missing_by_backend_method_reason.csv"
))
missing$failure_reason <- sub("out_of_memory_or_killed", "memory_kill", missing$failure_reason)
missing_wide <- reshape(
  missing, idvar = c("backend", "method"), timevar = "failure_reason",
  direction = "wide"
)
names(missing_wide) <- sub("unavailable_operating_points[.]", "", names(missing_wide))
for (name in c("timeout", "memory_kill")) {
  if (!name %in% names(missing_wide)) missing_wide[[name]] <- 0L
  missing_wide[[name]][is.na(missing_wide[[name]])] <- 0L
}

config <- read_required(file.path(
  stability_dir, "jss_calibration_configuration_near_tie_summary.csv"
))
family <- read_required(file.path(
  stability_dir, "jss_calibration_method_family_near_tie_summary.csv"
))
selection_stability <- rbind(
  transform(config, comparison = paste("configuration", scope)),
  transform(family, comparison = paste("method_family", scope))
)
selection_stability <- selection_stability[, c(
  "comparison", "operating_points", "median_relative_margin", "second_within_5_percent"
)]
calibration_validation <- read_required(file.path(
  stability_dir, "jss_calibration_to_validation_summary.csv"
))

calibration_audits <- list.dirs(file.path(campaign_root, "analysis"), recursive = TRUE)
calibration_audits <- calibration_audits[file.exists(file.path(
  calibration_audits, "jss_calibration_recommendations.csv"
))]
if (!length(calibration_audits)) stop("No version-pinned calibration audit directory was found.")
audit_counts <- vapply(calibration_audits, function(path) {
  value <- read_required(file.path(path, "jss_calibration_recommendations.csv"))
  sum(value$metric %in% c("euclidean", "cosine", "correlation"))
}, integer(1L))
calibration_audits <- calibration_audits[[which.max(audit_counts)]]
recommendations <- read_required(file.path(
  calibration_audits, "jss_calibration_recommendations.csv"
))
recommendations <- recommendations[
  recommendations$metric %in% c("euclidean", "cosine", "correlation"),
]
planned <- nrow(recommendations) + sum(missing$unavailable_operating_points)

qa_files <- list.files(
  file.path(campaign_root, "qa"), "^jss_package_route_qa[.]csv$",
  recursive = TRUE, full.names = TRUE
)
qa <- do.call(rbind, lapply(qa_files, read_required))
qa <- qa[qa$conformance_pass %in% TRUE, ]
qa_count <- function(backend) length(unique(paste(
  qa$method[qa$backend == backend], qa$metric[qa$backend == backend],
  qa$query_mode[qa$backend == backend], sep = "\r"
)))

loodo <- read_required(file.path(
  analysis_dir, "leave_one_dataset_out", "jss_leave_one_dataset_out.csv"
))
route_confusion <- read_required(file.path(
  analysis_dir, "leave_one_dataset_out", "jss_leave_one_dataset_out_route_confusion.csv"
))
grouped_loodo <- read_required(file.path(
  analysis_dir, "grouped_leave_domain_out", "jss_grouped_leave_domain_out_summary.csv"
))
auto_rows <- summary[summary$method_id == "faissR_cuda_auto", ]
cpu_rows <- summary[summary$method_id == "faissR_cpu_hnsw", ]
evidence <- data.frame(
  evidence = c(
    "CPU route-contract cells", "CUDA route-contract cells",
    "Completed calibration operating points", "Approximate calibration targets met",
    "CUDA automatic held-out cells", "CPU HNSW held-out cells",
    "CUDA LOODO operating-point cells", "CUDA LOODO method-family agreement"
  ),
  passing_or_completed = c(
    qa_count("cpu"), qa_count("cuda"), nrow(recommendations),
    sum(!recommendations$exact & recommendations$target_met),
    sum(auto_rows$selection_eligible), sum(cpu_rows$selection_eligible),
    sum(loodo$crossfit_operating_point_met, na.rm = TRUE),
    sum(loodo$crossfit_method_agreement, na.rm = TRUE)
  ),
  total = c(
    48, 52, planned, sum(!recommendations$exact), nrow(auto_rows), nrow(cpu_rows),
    nrow(loodo), nrow(loodo)
  ), stringsAsFactors = FALSE
)

auto_cells <- auto_cells_source
auto_by_dataset <- as.data.frame.matrix(table(
  pretty_dataset(auto_cells$dataset), auto_cells$selected_method
))
auto_by_dataset$dataset <- row.names(auto_by_dataset)
row.names(auto_by_dataset) <- NULL
auto_by_dataset <- auto_by_dataset[, c("dataset", setdiff(names(auto_by_dataset), "dataset"))]

decision <- function(label, dataset_set, k, target) {
  z <- auto_cells[
    auto_cells$dataset %in% dataset_set & auto_cells$metric == "euclidean" &
      auto_cells$k == k & abs(auto_cells$target_recall - target) < 1e-12,
  ]
  methods <- unique(tolower(z$selected_method))
  if (length(methods) != 1L) stop("Non-unique recorded route decision for ", label)
  if (methods == "flat") return("Flat")
  values <- unique(paste0("(", z$nlist, ", ", z$nprobe, ")"))
  if (length(values) != 1L) stop("Non-unique recorded IVF parameters for ", label)
  values
}
shape_sets <- list(
  "Large low-dimensional" = c("flow18", "FlowRepository_FR-FCM-ZYRM_files", "mass41"),
  "ImageNet features" = "imagenet"
)
ivf_decisions <- do.call(rbind, lapply(names(shape_sets), function(shape) {
  do.call(rbind, lapply(c(15, 30, 50, 100), function(k) data.frame(
    shape = shape, k = k,
    target_090 = decision(shape, shape_sets[[shape]], k, 0.90),
    target_095 = decision(shape, shape_sets[[shape]], k, 0.95),
    target_099 = decision(shape, shape_sets[[shape]], k, 0.99),
    stringsAsFactors = FALSE
  )))
}))

assert_equal <- function(observed, expected, label, tolerance = 0) {
  pass <- length(observed) == length(expected) && all(
    if (is.numeric(observed) || is.numeric(expected)) {
      abs(as.numeric(observed) - as.numeric(expected)) <= tolerance
    } else {
      as.character(observed) == as.character(expected)
    }
  )
  if (!isTRUE(pass)) {
    stop("Manuscript consistency assertion failed for ", label, ".")
  }
}

assert_equal(nrow(heldout), 18L, "held-out table row count")
assert_equal(sum(heldout$attained[heldout$route == "CUDA automatic"]), 324L,
             "CUDA automatic target attainment")
assert_equal(sum(heldout$attained[heldout$route == "CPU HNSW"]), 304L,
             "CPU HNSW target attainment")
assert_equal(sum(auto_cells$selected_method == "flat"), 280L, "CUDA Flat selections")
assert_equal(sum(auto_cells$selected_method == "ivf"), 44L, "CUDA IVF selections")
assert_equal(paired$median, c(18.45, 21.64, 0.99, 0.87, 2.23, 4.59),
             "paired speed-ratio medians", tolerance = 0.005)
assert_equal(sum(missing$unavailable_operating_points[missing$failure_reason == "timeout"]),
             306L, "calibration time limits")
assert_equal(sum(missing$unavailable_operating_points[missing$failure_reason == "memory_kill"]),
             45L, "calibration memory kills")
assert_equal(evidence$passing_or_completed,
             c(48, 52, 6453, 3653, 324, 304, 324, 300),
             "evidence audit numerator")
assert_equal(evidence$total, c(48, 52, 6804, 4725, 324, 324, 324, 324),
             "evidence audit denominator")
assert_equal(nrow(per_cpu), 9L, "CPU per-dataset rows")
assert_equal(nrow(per_cuda), 9L, "CUDA per-dataset rows")
assert_equal(selector_regret$median_regret[selector_regret$policy == "installed"],
             1.096462, "installed selector median regret", tolerance = 0.000001)
assert_equal(selector_regret$median_regret[selector_regret$policy == "cross_fitted"],
             1.0, "cross-fitted selector median regret", tolerance = 0.000001)
assert_equal(sum(grouped_loodo$n_cells), 324L, "grouped domain holdout cells")
assert_equal(sum(grouped_loodo$n_operating_points_met), 320L,
             "grouped domain holdout target attainment")

tables <- list(
  write_table(methods, 1, "method_families", "Nearest-neighbor method families", out_dir),
  write_table(datasets, 2, "datasets", "Datasets used in the evaluation", out_dir),
  write_table(heldout, 3, "heldout_target_attainment", "Held-out target attainment", out_dir),
  write_table(auto_selection, 4, "cuda_auto_selection", "CUDA automatic route selection", out_dir),
  write_table(paired, 5, "paired_speed_ratios", "Matched-cell end-to-end speed ratios", out_dir),
  write_table(environment, 6, "computational_environment", "Computational environment", out_dir),
  write_table(grid, 7, "calibration_parameters", "Method-specific calibration parameters", out_dir),
  write_table(missing_wide, 8, "unavailable_calibration", "Unavailable calibration points", out_dir),
  write_table(selection_stability, 9, "selection_stability", "Selection sensitivity", out_dir),
  write_table(calibration_validation, 10, "calibration_validation", "Calibration-to-validation change", out_dir),
  write_table(evidence, 11, "evidence_audit", "Evidence used by the article", out_dir),
  write_table(per_cpu, 12, "cpu_per_dataset", "CPU results by dataset", out_dir),
  write_table(per_cuda, 13, "cuda_per_dataset", "CUDA results by dataset", out_dir),
  write_table(auto_by_dataset, 14, "cuda_auto_by_dataset", "CUDA automatic routes by dataset", out_dir),
  write_table(
    ivf_decisions, 15, "cuda_ivf_decisions",
    "Version-pinned CUDA IVF decisions", out_dir
  ),
  write_table(
    selector_regret, 16, "selector_feasible_route_regret",
    "CUDA selector feasible-route regret", out_dir
  ),
  write_table(
    route_confusion, 17, "selector_route_confusion",
    "Compiled, cross-fitted, and oracle route confusion", out_dir
  ),
  write_table(
    grouped_loodo, 18, "grouped_leave_domain_out",
    "Grouped leave-one-domain-out sensitivity", out_dir
  )
)
manifest <- do.call(rbind, tables)
manifest$sha256 <- vapply(file.path(out_dir, manifest$file), function(path) {
  if (requireNamespace("openssl", quietly = TRUE)) {
    con <- file(path, "rb"); on.exit(close(con), add = TRUE)
    return(as.character(openssl::sha256(con)))
  }
  command <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
  args <- if (command == "shasum") c("-a", "256", path) else path
  sub("[[:space:]].*$", "", system2(command, args, stdout = TRUE)[[1L]])
}, character(1L))
manifest$recreated <- TRUE
utils::write.csv(manifest, file.path(out_dir, "manuscript_table_manifest.csv"), row.names = FALSE)
if (nrow(manifest) != 18L || !all(manifest$rows > 0L) || !all(manifest$recreated)) {
  stop("Not every manuscript table was recreated.")
}
writeLines(
  c("MANUSCRIPT TABLE AUDIT PASSED", paste0("Tables recreated: ", nrow(manifest), "/18")),
  file.path(out_dir, "MANUSCRIPT_TABLE_AUDIT.txt")
)
cat("Recreated and audited 18 manuscript tables in ", out_dir, "\n", sep = "")
