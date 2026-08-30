#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR experiment commit}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Missing Singularity image: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

MANIFEST="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"
HELPER="${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R"
BENCHMARK="${SUITE_ROOT}/validation/paired_external_cpu_comparison/benchmark_paired_external_cpu.R"
AUDIT="${SUITE_ROOT}/validation/paired_external_cpu_comparison/audit_paired_external_cpu.R"

for path in "${MANIFEST}" "${HELPER}" "${BENCHMARK}" "${AUDIT}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    exit 2
  fi
done

export EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT MANIFEST HELPER BENCHMARK AUDIT
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript --vanilla -e '
required <- c("faissR", "FNN", "rnndescent")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Missing package(s): ", paste(missing, collapse = ", "))
actual <- as.character(packageVersion("faissR"))
expected <- Sys.getenv("EXPECTED_FAISSR_VERSION")
if (!identical(actual, expected)) stop("Expected faissR ", expected, "; image contains ", actual)
for (path in Sys.getenv(c("MANIFEST", "HELPER", "BENCHMARK", "AUDIT"))) {
  if (!file.exists(path)) stop("Container cannot read required file: ", path)
}
manifest <- read.csv(Sys.getenv("MANIFEST"), stringsAsFactors = FALSE)
datasets <- c("COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
              "flow18", "MNIST", "imagenet", "MetRef", "mass41")
if (!all(datasets %in% manifest$dataset)) {
  stop("Dataset manifest lacks: ", paste(setdiff(datasets, manifest$dataset), collapse = ", "))
}
Sys.setenv(FAISSR_JSS_REUSABLE_SOURCE_ONLY = "true")
helpers <- new.env(parent = globalenv())
source(Sys.getenv("HELPER"), local = helpers)
path_column <- helpers$dataset_path_column(manifest)
missing_data <- character()
missing_references <- character()
for (dataset in datasets) {
  row <- manifest[manifest$dataset == dataset, , drop = FALSE]
  path <- row[[path_column]][[1L]]
  if (!file.exists(path)) {
    missing_data <- c(missing_data, paste(dataset, path, sep = ": "))
    next
  }
  fingerprint <- unname(tools::md5sum(path)[[1L]])
  for (metric in c("euclidean", "cosine", "correlation")) {
    for (seed in c(20260706L, 20260807L)) {
      ok <- tryCatch({
        helpers$load_reference(path, metric, 100L, 1024L, seed, fingerprint)
        TRUE
      }, error = function(e) FALSE)
      if (!ok) missing_references <- c(
        missing_references, paste(dataset, metric, seed, sep = "/")
      )
    }
  }
}
if (length(missing_data)) stop("Missing dataset file(s): ", paste(missing_data, collapse = "; "))
if (length(missing_references)) {
  stop("Missing or incompatible exact reference(s): ",
       paste(missing_references, collapse = ", "))
}
cat("faissR:", actual, "\n")
for (package in required[-1L]) {
  cat(package, ":", as.character(packageVersion(package)), "\n")
}
cat("Manifest rows:", nrow(manifest), "\n")
cat("Exact references checked:", length(datasets) * 3L * 2L, "\n")
cat("PAIRED EXTERNAL CPU PREFLIGHT PASSED\n")
'
