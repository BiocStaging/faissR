#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_warm_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_reusable_external_audit_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_reusable_external_audit_cpu12_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.18'
mkdir -p "${BASE_DIR}/benchmark_logs"

run_r() { singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/reusable_external"
OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/reusable_external_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT}"
run_r "${SUITE_ROOT}/analysis/aggregate_reusable_external_indexes.R" \
  --results_root="${ROOT}" --out_dir="${OUT}"
