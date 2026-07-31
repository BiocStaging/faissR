#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_t_exact_eucl"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_tune_exact_cpu12_euclidean_real_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_tune_exact_cpu12_euclidean_real_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.20'
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR commit embedded in the frozen image}"
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal Git commit" >&2
  exit 2
fi
export FAISSR_PACKAGE_COMMIT
IMAGE_FAISSR_COMMIT="$(singularity exec --cleanenv "${SINGULARITY_IMAGE}" /bin/sh -c 'printf "%s" "${FAISSR_IMAGE_COMMIT:-}"')"
if [[ ! "${IMAGE_FAISSR_COMMIT}" == "${FAISSR_PACKAGE_COMMIT}" ]]; then
  echo "Frozen campaign requires faissR commit ${FAISSR_PACKAGE_COMMIT}, but the Singularity image reports ${IMAGE_FAISSR_COMMIT:-UNSET}" >&2
  exit 2
fi
mkdir -p "${BASE_DIR}/benchmark_logs"

export METHOD='exact'
export METHOD_LABEL='faissR_exact_euclidean_real'
export BACKEND='cpu'
export METRICS='euclidean'
export DATASETS='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41'
export THREADS="${THREADS:-12}"
export THREAD_VALUES="${THREAD_VALUES:-12}"
export K_VALUES="${K_VALUES:-15,30,50,100}"
export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"
export TIMEOUT="${TIMEOUT:-2000}"
export QUALITY_N="${QUALITY_N:-1024}"
export CALIBRATION_SEED="${CALIBRATION_SEED:-4}"
export GRID_LEVEL="${GRID_LEVEL:-wide}"
export OUTPUT_VALUES="${OUTPUT_VALUES:-double}"
export REAL_MANIFEST="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"
export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration/real/cpu/${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
export SINGULARITY_GPU_FLAG=''
export SINGULARITY_IMAGE
exec bash "${SUITE_ROOT}/common/run_one_inner_product_tuning.sh"
