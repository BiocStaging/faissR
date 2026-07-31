#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_t_brutefo_inne"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_tune_bruteforce_cuda_inner_product_real_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_tune_bruteforce_cuda_inner_product_real_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.20'
mkdir -p "${BASE_DIR}/benchmark_logs"

export METHOD='bruteforce'
export METHOD_LABEL='faissR_bruteforce_inner_product_real'
export BACKEND='cuda'
export METRICS='inner_product'
export DATASETS='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41'
export THREADS="${THREADS:-2}"
export THREAD_VALUES="${THREAD_VALUES:-2}"
export K_VALUES="${K_VALUES:-15,30,50,100}"
export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"
export TIMEOUT="${TIMEOUT:-2000}"
export QUALITY_N="${QUALITY_N:-1024}"
export CALIBRATION_SEED="${CALIBRATION_SEED:-4}"
export GRID_LEVEL="${GRID_LEVEL:-wide}"
export OUTPUT_VALUES="${OUTPUT_VALUES:-double}"
export REAL_MANIFEST="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"
export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration/real/cuda/${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
export SINGULARITY_GPU_FLAG='--nv'
export SINGULARITY_IMAGE
exec bash "${SUITE_ROOT}/common/run_one_inner_product_tuning.sh"
