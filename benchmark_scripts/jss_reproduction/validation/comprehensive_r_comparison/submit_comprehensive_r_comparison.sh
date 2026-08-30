#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
HERE="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/comprehensive_r_comparison"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
export SINGULARITY_IMAGE EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Missing Singularity image: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi
for path in \
  "${HERE}/benchmark_comprehensive_r_comparison.R" \
  "${HERE}/audit_comprehensive_r_comparison.R" \
  "${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"
do
  [[ -f "${path}" ]] || { echo "Missing required file: ${path}" >&2; exit 2; }
done

export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript --vanilla -e '
packages <- c("faissR", "FNN", "RANN", "rnndescent", "BiocNeighbors",
              "Rnanoflann", "RcppAnnoy", "RcppHNSW")
missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing)) stop("Image lacks required package(s): ", paste(missing, collapse = ", "))
actual <- as.character(packageVersion("faissR"))
expected <- Sys.getenv("EXPECTED_FAISSR_VERSION")
if (!identical(actual, expected)) stop("Expected faissR ", expected, "; found ", actual)
base <- "/scratch/firenze/NN"
helper <- file.path(base, "benchmark_scripts/jss_reproduction/common/benchmark_reusable_external_indexes.R")
Sys.setenv(FAISSR_JSS_REUSABLE_SOURCE_ONLY = "true")
helpers <- new.env(parent = globalenv())
source(helper, local = helpers)
manifest <- read.csv(file.path(base, "Data/float32_dataset_manifest_jmlr.csv"), stringsAsFactors = FALSE)
datasets <- c("COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
              "flow18", "MNIST", "imagenet", "MetRef", "mass41")
path_column <- helpers$dataset_path_column(manifest)
for (dataset in datasets) {
  row <- manifest[manifest$dataset == dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Manifest does not contain exactly one row for ", dataset)
  path <- row[[path_column]][[1L]]
  if (!file.exists(path)) stop("Missing dataset: ", path)
  fingerprint <- unname(tools::md5sum(path)[[1L]])
  for (metric in c("euclidean", "cosine", "correlation")) {
    for (seed in c(20260706L, 20260807L)) {
      helpers$load_reference(path, metric, 100L, 1024L, seed, fingerprint)
    }
  }
}
cat(paste(packages, vapply(packages, function(x) as.character(packageVersion(x)), character(1L)), sep = "="), sep = "\n")
cat("Exact references checked:", length(datasets) * 3L * 2L, "\n")
cat("\nCOMPREHENSIVE R COMPARISON PREFLIGHT PASSED\n")
'

RUN_ID="${COMPREHENSIVE_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}_$(date -u +%Y%m%d_%H%M%S)}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/comprehensive_r_comparison/${RUN_ID}"
mkdir -p "${ROOT}" "${BASE_DIR}/faissR_JSS_REPRODUCTION/submissions" "${BASE_DIR}/benchmark_logs"

ARRAY_JOB=$(sbatch --parsable --export=ALL,COMPREHENSIVE_RUN_ID="${RUN_ID}" \
  "${HERE}/run_comprehensive_r_comparison_cpu12.sh")
AUDIT_JOB=$(sbatch --parsable --dependency="afterany:${ARRAY_JOB}" \
  --export=ALL,COMPREHENSIVE_RESULT_ROOT="${ROOT}",COMPREHENSIVE_RUN_ID="${RUN_ID}" \
  "${HERE}/run_comprehensive_r_comparison_audit_cpu12.sh")

LEDGER="${BASE_DIR}/faissR_JSS_REPRODUCTION/submissions/comprehensive_r_${RUN_ID}.txt"
printf 'run_id=%s\narray_job=%s\naudit_job=%s\nresult_root=%s\n' \
  "${RUN_ID}" "${ARRAY_JOB}" "${AUDIT_JOB}" "${ROOT}" | tee "${LEDGER}"
echo "All jobs are submitted. No manual follow-up submission is required."
