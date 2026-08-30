#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    fields <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[fields[[1L]]]] <- paste(fields[-1L], collapse = "=")
  }
  missing <- setdiff(c("campaign_root", "out_dir"), names(out))
  if (length(missing)) {
    stop("Required arguments: --campaign_root and --out_dir", call. = FALSE)
  }
  out
}

sha256_file <- function(path) {
  command <- if (nzchar(Sys.which("sha256sum"))) {
    c(Sys.which("sha256sum"), path)
  } else if (nzchar(Sys.which("shasum"))) {
    c(Sys.which("shasum"), "-a", "256", path)
  } else {
    stop("A SHA-256 command is required.", call. = FALSE)
  }
  value <- system2(command[[1L]], command[-1L], stdout = TRUE)
  sub("[[:space:]].*$", "", value[[1L]])
}

bind_rows <- function(values) {
  columns <- unique(unlist(lapply(values, names), use.names = FALSE))
  values <- lapply(values, function(value) {
    for (name in setdiff(columns, names(value))) value[[name]] <- NA
    value[, columns, drop = FALSE]
  })
  do.call(rbind, values)
}

relative_path <- function(path, root) {
  prefix <- paste0(normalizePath(root, mustWork = TRUE), .Platform$file.sep)
  sub(paste0("^", prefix), "", normalizePath(path, mustWork = TRUE), fixed = FALSE)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
campaign_root <- normalizePath(args$campaign_root, mustWork = TRUE)
out_dir <- args$out_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
public_metrics <- c("euclidean", "cosine", "correlation")
campaign_version <- "0.99.21"
campaign_commit <- "0903532baf02b340a90921db18edc4deae5ea462"

dimensions <- data.frame(
  dataset = c(
    "COIL20", "FashionMNIST", "flow18",
    "FlowRepository_FR-FCM-ZYRM_files", "imagenet", "mass41", "MetRef",
    "MNIST", "USPS", "synthetic_spatial_n10000_p2_unit",
    "synthetic_spatial_n10000_p3_unit"
  ),
  n = c(1440, 70000, 1000021, 5220347, 1281167, 965282, 873, 70000,
        11000, 10000, 10000),
  p = c(16384, 784, 11, 32, 1024, 14, 375, 784, 256, 2, 3),
  stringsAsFactors = FALSE
)

reference_files <- list.files(
  file.path(campaign_root, "references"),
  pattern = "^faissR_cuda_exact_reference_results[.]csv$",
  recursive = TRUE, full.names = TRUE
)
reference_tables <- lapply(reference_files, function(path) {
  value <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("faissR_version", "faissR_package_commit") %in% names(value))) {
    return(NULL)
  }
  value <- value[
    value$metric %in% public_metrics &
      value$faissR_version == campaign_version &
      value$faissR_package_commit == campaign_commit &
      value$status == "success",
    , drop = FALSE
  ]
  if (!nrow(value)) return(NULL)
  value$record_source <- relative_path(path, campaign_root)
  value
})
reference_tables <- Filter(Negate(is.null), reference_tables)
references <- bind_rows(reference_tables)
references <- merge(references, dimensions, by = "dataset", all.x = TRUE, sort = FALSE)
if (anyNA(references$n) || nrow(references) != 87L) {
  stop("The public exact-reference key must contain 87 dimensioned records.")
}
references$query_n <- pmin(references$n, 1024L)
references$query_sampling <- ifelse(
  references$n <= 1024L, "all_rows", "unique_without_replacement"
)
references$reference_k <- 100L
references$source_group <- ifelse(
  startsWith(references$dataset, "synthetic_spatial_"), "synthetic_spatial", "real"
)
reference_key <- references[, c(
  "source_group", "dataset", "dataset_md5", "n", "p", "metric", "seed",
  "query_n", "query_sampling", "reference_k", "reference_backend_used",
  "cpu_audit_n", "cpu_audit_mean_recall", "cpu_audit_min_recall",
  "cpu_audit_max_distance_error", "cpu_audit_pass", "faissR_version",
  "faissR_package_commit", "faissR_image_commit", "record_source"
)]
reference_key <- reference_key[order(
  reference_key$source_group, reference_key$dataset,
  match(reference_key$metric, public_metrics), reference_key$seed
), ]
utils::write.csv(
  reference_key, file.path(out_dir, "reference_record_dimensions.csv"),
  row.names = FALSE, na = ""
)

grid_files <- list.files(
  file.path(campaign_root, "calibration", "real"),
  pattern = "_tuning_candidate_grid[.]csv$",
  recursive = TRUE, full.names = TRUE
)
grid_tables <- lapply(grid_files, function(path) {
  value <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  value <- value[value$metric %in% public_metrics, , drop = FALSE]
  if (!nrow(value)) return(NULL)
  value$grid_source <- relative_path(path, campaign_root)
  value
})
keep <- !vapply(grid_tables, is.null, logical(1L))
grid_files <- grid_files[keep]
grid_tables <- grid_tables[keep]
if (length(grid_tables) != 63L) {
  stop("Expected 63 public-metric calibration-grid files; found ", length(grid_tables), ".")
}
grid_manifest <- do.call(rbind, Map(function(value, path) {
  data.frame(
    backend = paste(unique(value$backend), collapse = ";"),
    method = paste(unique(value$method), collapse = ";"),
    metric = paste(unique(value$metric), collapse = ";"),
    rows = nrow(value),
    datasets = length(unique(value$dataset)),
    k_values = paste(sort(unique(value$k)), collapse = ";"),
    candidate_ids = length(unique(value$candidate_id)),
    sha256 = sha256_file(path),
    grid_source = relative_path(path, campaign_root),
    stringsAsFactors = FALSE
  )
}, grid_tables, grid_files))
grid_manifest <- grid_manifest[order(
  grid_manifest$backend, grid_manifest$method, grid_manifest$metric
), ]
utils::write.csv(
  grid_manifest, file.path(out_dir, "calibration_candidate_grid_manifest.csv"),
  row.names = FALSE
)

all_grid_rows <- bind_rows(grid_tables)
grid_output <- file.path(out_dir, "calibration_candidate_grid_public.csv.gz")
connection <- gzfile(grid_output, open = "wt")
utils::write.csv(all_grid_rows, connection, row.names = FALSE, na = "")
close(connection)

version_boundaries <- data.frame(
  experiment = c(
    "reference, calibration, and independent-query within-dataset campaign",
    "controlled same-node CPU provider comparison"
  ),
  faissR_version = c("0.99.21", "0.99.25"),
  commit = c(campaign_commit, "b33a70116887474a2ed70d84de0c80bb77e9db66"),
  numerical_scope = c(
    "route QA; exact references; calibration; CUDA installed-policy validation; LOODO reconstruction",
    "standalone cold-call HNSW comparison with BiocNeighbors and RcppHNSW"
  ),
  combination_rule = c(
    "analyzed only with other 0.99.21 campaign rows",
    "not pooled with 0.99.21 elapsed times; every pair independently recall-audited against the archived exact reference"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  version_boundaries, file.path(out_dir, "experiment_version_boundaries.csv"),
  row.names = FALSE
)

release_changes <- data.frame(
  release = c("0.99.22", "0.99.23", "0.99.24", "0.99.25"),
  relevant_change = c(
    "Added session backend precedence; benchmark calls use explicit backends.",
    "Restricted the public metrics to Euclidean, cosine, and correlation; removed inner-product evidence; refactored input and route metadata.",
    "Added Bioconductor metadata and centralized suppression of expected optional-runtime warnings.",
    "Restored Windows eligibility and added the controlled CPU comparison and its independent recall audit."
  ),
  validity_control = c(
    "No 0.99.21 timing was relabelled or rerun under this release.",
    "The article filters the older archive to the same three retained metrics; controlled 0.99.25 routes were re-audited rather than assumed unchanged.",
    "No nearest-neighbor timing result is transferred from this release.",
    "Its elapsed times form a separate experiment and are never pooled with the 0.99.21 campaign."
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  release_changes, file.path(out_dir, "experiment_version_changes.csv"),
  row.names = FALSE
)

summary <- data.frame(
  artifact = c(
    "reference_record_dimensions.csv", "calibration_candidate_grid_manifest.csv",
    "calibration_candidate_grid_public.csv.gz", "experiment_version_boundaries.csv",
    "experiment_version_changes.csv"
  ),
  rows = c(nrow(reference_key), nrow(grid_manifest), nrow(all_grid_rows),
           nrow(version_boundaries), nrow(release_changes)),
  sha256 = vapply(file.path(out_dir, c(
    "reference_record_dimensions.csv", "calibration_candidate_grid_manifest.csv",
    "calibration_candidate_grid_public.csv.gz", "experiment_version_boundaries.csv",
    "experiment_version_changes.csv"
  )), sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
utils::write.csv(
  summary, file.path(out_dir, "consistency_artifact_manifest.csv"),
  row.names = FALSE
)

cat("Reference records:", nrow(reference_key), "\n")
cat("Calibration grid files:", nrow(grid_manifest), "\n")
cat("Instantiated candidate rows:", nrow(all_grid_rows), "\n")
