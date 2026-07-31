#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_h_faissR__eucl"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_hold_faissR_vamana_cuda_euclidean_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_hold_faissR_vamana_cuda_euclidean_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.20'
mkdir -p "${BASE_DIR}/benchmark_logs"

export METHOD_ID='faissR_cuda_vamana'
export METHOD_LABEL='faissR_vamana_euclidean'
export BACKEND='cuda'
export THREADS="${THREADS:-2}"
export METHOD_METRICS='euclidean'
export DATASETS='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41'
export K_VALUES="${K_VALUES:-15,30,50,100}"
export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"
export VALIDATION_SEEDS="${VALIDATION_SEEDS:-20260706,20260807}"
export REPEATS="${REPEATS:-3}"
export TIMEOUT="${TIMEOUT:-2000}"
export INCLUDE_EXTERNAL='FALSE'
export REQUIRED_EXTERNAL_PACKAGE=''
export INCLUDE_GPU_RESIDENT='TRUE'
export RUN_REAL='TRUE'
export RUN_MIPS='FALSE'
export RUN_SPATIAL='FALSE'
export MIPS_DATASETS='synthetic_mips_n20000_p32_unit,synthetic_mips_n70000_p128_unit,synthetic_mips_n70000_p512_unit,synthetic_mips_n200000_p64_unit,synthetic_mips_n20000_p32_lognormal,synthetic_mips_n70000_p128_lognormal,synthetic_mips_n70000_p512_lognormal,synthetic_mips_n200000_p64_lognormal,synthetic_mips_n20000_p32_pareto,synthetic_mips_n70000_p128_pareto,synthetic_mips_n70000_p512_pareto,synthetic_mips_n200000_p64_pareto'
export SPATIAL_DATASETS='synthetic_spatial_n10000_p2_unit,synthetic_spatial_n10000_p3_unit'
export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out/cuda/faissR_vamana/${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
export SINGULARITY_GPU_FLAG='--nv'
export SINGULARITY_IMAGE
exec bash "${SUITE_ROOT}/common/run_one_method.sh"
