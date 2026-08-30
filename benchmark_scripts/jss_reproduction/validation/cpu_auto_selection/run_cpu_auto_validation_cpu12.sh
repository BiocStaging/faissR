#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=24:00:00
#SBATCH --array=1-324%12
#SBATCH --job-name="frJ_cpu_auto"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_cpu_auto_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_cpu_auto_%A_%a.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR experiment commit}"

DATASETS=(COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST imagenet MetRef mass41)
METRICS=(euclidean cosine correlation)
K_VALUES=(15 30 50 100)
TARGETS=(0.9 0.95 0.99)
ZERO=$((${SLURM_ARRAY_TASK_ID:?Run as a Slurm array} - 1))
TARGET="${TARGETS[$((ZERO % 3))]}"
ZERO=$((ZERO / 3))
K="${K_VALUES[$((ZERO % 4))]}"
ZERO=$((ZERO / 4))
METRIC="${METRICS[$((ZERO % 3))]}"
DATASET="${DATASETS[$((ZERO / 3))]}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Missing Singularity image: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

export METHOD_ID=faissR_cpu_auto
export METHOD_LABEL="faissR_auto_${METRIC}"
export BACKEND=cpu
export THREADS=12
export METHOD_METRICS="${METRIC}"
export DATASETS="${DATASET}"
export K_VALUES="${K}"
export TARGET_RECALLS="${TARGET}"
export VALIDATION_SEEDS=20260706,20260807
export REPEATS=3
export TIMEOUT=4000
export INCLUDE_EXTERNAL=FALSE
export REQUIRED_EXTERNAL_PACKAGE=''
export INCLUDE_GPU_RESIDENT=FALSE
export RUN_REAL=TRUE
export RUN_SPATIAL=FALSE
export SINGULARITY_GPU_FLAG=''
export EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT SINGULARITY_IMAGE
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export OUT_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/cpu_auto_selection/${EXPECTED_FAISSR_VERSION}/${METRIC}/${DATASET}/k${K}/target_${TARGET}/${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}"

exec bash "${SUITE_ROOT}/common/run_one_method.sh"
