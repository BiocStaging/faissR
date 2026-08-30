#!/usr/bin/env bash

set -euo pipefail

: "${COMPARISON:?COMPARISON is required}"
: "${METRIC:?METRIC is required}"
: "${DATASET:?DATASET is required}"
: "${K:?K is required}"

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR experiment commit}"
PUBLICATION_RUN_ID="${PUBLICATION_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Missing Singularity image: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

mkdir -p "${BASE_DIR}/benchmark_logs"
OUT_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/paired_external_cpu_comparison/${PUBLICATION_RUN_ID}/${COMPARISON}/${METRIC}/${DATASET}/k${K}/${SLURM_ARRAY_JOB_ID:-manual}_${SLURM_ARRAY_TASK_ID:-0}"
mkdir -p "${OUT_DIR}"

export FAISSR_PACKAGE_COMMIT EXPECTED_FAISSR_VERSION
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export FAISSR_PAIRED_HELPER="${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R"
export SINGULARITYENV_FAISSR_PAIRED_HELPER="${FAISSR_PAIRED_HELPER}"
export APPTAINERENV_FAISSR_PAIRED_HELPER="${FAISSR_PAIRED_HELPER}"

packages=(faissR)
if [[ "${COMPARISON}" == "exact_FNN" ]]; then
  packages+=(FNN)
else
  packages+=(rnndescent)
fi
PACKAGE_CSV="$(IFS=,; echo "${packages[*]}")"
export PACKAGE_CSV
export SINGULARITYENV_PACKAGE_CSV="${PACKAGE_CSV}"
export APPTAINERENV_PACKAGE_CSV="${PACKAGE_CSV}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); actual <- as.character(packageVersion("faissR")); if (!identical(actual, expected)) stop("Expected faissR ", expected, "; image contains ", actual); for (p in strsplit(Sys.getenv("PACKAGE_CSV"), ",", fixed=TRUE)[[1]]) if (!requireNamespace(p, quietly=TRUE)) stop("Missing package: ", p)'

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/paired_external_cpu_comparison/benchmark_paired_external_cpu.R" \
  --helper="${FAISSR_PAIRED_HELPER}" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --out_dir="${OUT_DIR}" --dataset="${DATASET}" --k="${K}" \
  --comparison="${COMPARISON}" --metric="${METRIC}" \
  --seeds=20260706,20260807 --repeats=3 --threads=12 \
  --timeout=4000 --quality_n=1024 --reference_k=100 --target_recall=0.99
