#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_final_gpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_final_analysis_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_final_analysis_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21.sif}"
export EXPECTED_FAISSR_VERSION='0.99.22'
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR commit embedded in the frozen image}"
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal Git commit" >&2
  exit 2
fi
export FAISSR_PACKAGE_COMMIT
export FAISSR_REQUIRE_FROZEN_IDENTITY=1
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
IMAGE_FAISSR_COMMIT="$(singularity exec --cleanenv "${SINGULARITY_IMAGE}" /bin/sh -c 'printf "%s" "${FAISSR_IMAGE_COMMIT:-}"')"
if [[ ! "${IMAGE_FAISSR_COMMIT}" == "${FAISSR_PACKAGE_COMMIT}" ]]; then
  echo "Frozen campaign requires faissR commit ${FAISSR_PACKAGE_COMMIT}, but the Singularity image reports ${IMAGE_FAISSR_COMMIT:-UNSET}" >&2
  exit 2
fi
mkdir -p "${BASE_DIR}/benchmark_logs"

BACKEND='cuda'
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/held_out/${BACKEND}"
OUT="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/analysis/held_out_${BACKEND}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
AGG="${OUT}/real"
mkdir -p "${AGG}"
run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
run_r "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \
  --results_root="${ROOT}" --out_dir="${AGG}" --backend="${BACKEND}" \
  --datasets='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41' \
  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3
run_r "${SUITE_ROOT}/analysis/analyze_leave_one_dataset_out.R" \
  --analysis_dir="${AGG}" --out_dir="${OUT}/leave_one_dataset_out"
run_r "${SUITE_ROOT}/analysis/build_publication_figures.R" \
  --analysis_dir="${AGG}" --out_dir="${OUT}/figures" --backend="${BACKEND}"
