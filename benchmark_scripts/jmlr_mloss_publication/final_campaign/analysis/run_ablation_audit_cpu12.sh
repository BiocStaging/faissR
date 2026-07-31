#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_abl_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_ablation_audit_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_ablation_audit_cpu12_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.18'
mkdir -p "${BASE_DIR}/benchmark_logs"

run_r() { singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
ROOT="${BASE_DIR}/faissR_JMLR_MLOSS"
OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/ablations_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT}"
run_r "${SUITE_ROOT}/analysis/aggregate_systems_ablations.R" \
  --ablations_root="${ROOT}" --out_dir="${OUT}" \
  --datasets=COIL20,MNIST,flow18,mass41
