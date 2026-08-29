#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --array=1-72%12
#SBATCH --job-name="frJ_pair_hnsw"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_pair_hnsw_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_pair_hnsw_%A_%a.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the frozen 40-character faissR commit}"

DATASETS=(COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST imagenet MetRef mass41)
K_VALUES=(15 30 50 100)
COMPARATORS=(BiocNeighbors_hnsw RcppHNSW_hnsw)
TASK_ID="${SLURM_ARRAY_TASK_ID:?This launcher must run as a Slurm array}"
ZERO=$((TASK_ID - 1))
COMPARATOR="${COMPARATORS[$((ZERO % 2))]}"
ZERO=$((ZERO / 2))
K="${K_VALUES[$((ZERO % 4))]}"
DATASET="${DATASETS[$((ZERO / 4))]}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Missing Singularity image: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

mkdir -p "${BASE_DIR}/benchmark_logs"
OUT_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/paired_cpu_comparison/${DATASET}/k${K}/${COMPARATOR}_${SLURM_ARRAY_JOB_ID}_${TASK_ID}"
mkdir -p "${OUT_DIR}"

export FAISSR_PACKAGE_COMMIT EXPECTED_FAISSR_VERSION
export FAISSR_REQUIRE_FROZEN_IDENTITY=1
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
export FAISSR_PAIRED_HELPER="${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R"
export SINGULARITYENV_FAISSR_PAIRED_HELPER="${FAISSR_PAIRED_HELPER}"
export APPTAINERENV_FAISSR_PAIRED_HELPER="${FAISSR_PAIRED_HELPER}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); actual <- as.character(packageVersion("faissR")); if (!identical(actual, expected)) stop("Expected faissR ", expected, "; image contains ", actual); for (p in c("BiocNeighbors", "RcppHNSW")) if (!requireNamespace(p, quietly=TRUE)) stop("Missing comparator package: ", p)'

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/paired_cpu_comparison/benchmark_paired_hnsw.R" \
  --helper="${FAISSR_PAIRED_HELPER}" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --out_dir="${OUT_DIR}" --dataset="${DATASET}" --k="${K}" \
  --comparator="${COMPARATOR}" --seeds=20260706,20260807 \
  --repeats=5 --threads=12 --timeout=4000 --quality_n=1024 \
  --reference_k=100 --target_recall=0.99
