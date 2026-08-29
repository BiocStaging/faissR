#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_audit_%j.err
set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/external_r_comparison/cpu"
OUT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/external_r_comparison/analysis_${SLURM_JOB_ID:-manual}_$(date -u +%Y%m%d_%H%M%S)"
singularity exec --cleanenv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" Rscript \
  "${SUITE_ROOT}/analysis/analyze_external_r_comparison.R" \
  --results_root="${ROOT}" --out_dir="${OUT}"
