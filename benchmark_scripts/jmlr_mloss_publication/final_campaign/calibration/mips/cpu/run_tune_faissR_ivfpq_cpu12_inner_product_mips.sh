#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_t_ivfpq_inne"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_tune_ivfpq_cpu12_inner_product_mips_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_tune_ivfpq_cpu12_inner_product_mips_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
mkdir -p "${BASE_DIR}/benchmark_logs"

export METHOD='ivfpq'
export METHOD_LABEL='faissR_ivfpq_inner_product_mips'
export BACKEND='cpu'
export METRICS='inner_product'
export DATASETS='synthetic_mips_n20000_p32_unit,synthetic_mips_n70000_p128_unit,synthetic_mips_n70000_p512_unit,synthetic_mips_n200000_p64_unit,synthetic_mips_n20000_p32_lognormal,synthetic_mips_n70000_p128_lognormal,synthetic_mips_n70000_p512_lognormal,synthetic_mips_n200000_p64_lognormal,synthetic_mips_n20000_p32_pareto,synthetic_mips_n70000_p128_pareto,synthetic_mips_n70000_p512_pareto,synthetic_mips_n200000_p64_pareto'
export THREADS="${THREADS:-12}"
export THREAD_VALUES="${THREAD_VALUES:-12}"
export K_VALUES="${K_VALUES:-15,30,50,100}"
export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"
export TIMEOUT="${TIMEOUT:-2000}"
export QUALITY_N="${QUALITY_N:-1024}"
export CALIBRATION_SEED="${CALIBRATION_SEED:-4}"
export GRID_LEVEL="${GRID_LEVEL:-wide}"
export OUTPUT_VALUES="${OUTPUT_VALUES:-double}"
export REAL_MANIFEST="${BASE_DIR}/Data/JMLR_synthetic_MIPS/jmlr_synthetic_mips_manifest.csv"
export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration/mips/cpu/${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
export SINGULARITY_GPU_FLAG=''
export SINGULARITY_IMAGE
exec bash "${SUITE_ROOT}/common/run_one_inner_product_tuning.sh"
