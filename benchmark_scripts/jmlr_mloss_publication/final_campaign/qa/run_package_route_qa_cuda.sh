#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_qa_gpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_package_route_qa_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_package_route_qa_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.20'
mkdir -p "${BASE_DIR}/benchmark_logs"

OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/qa/cuda_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT_DIR}"
sha256sum "${SINGULARITY_IMAGE}" > "${OUT_DIR}/singularity_image.sha256"
stat "${SINGULARITY_IMAGE}" > "${OUT_DIR}/singularity_image.stat.txt"
nvidia-smi -L > "${OUT_DIR}/nvidia_smi_devices.txt"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript \
  "${SUITE_ROOT}/common/benchmark_package_route_qa.R" \
  --backend=cuda --out_dir="${OUT_DIR}"
