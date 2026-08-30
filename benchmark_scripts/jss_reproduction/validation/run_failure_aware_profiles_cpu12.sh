#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_failprof"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_failprof_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_failprof_%j.err

set -euo pipefail
: "${ROBUST_METHOD_SUMMARY:?Export ROBUST_METHOD_SUMMARY as jss_robust_method_summary.csv}"
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
OUT="${FAILURE_PROFILE_OUT:-${BASE_DIR}/faissR_JSS_REPRODUCTION/analysis/failure_aware_${SLURM_JOB_ID}}"
mkdir -p "${OUT}" "${BASE_DIR}/benchmark_logs"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${BASE_DIR}/benchmark_scripts/jss_reproduction/analysis/analyze_failure_aware_profiles.R" \
  --summary="${ROBUST_METHOD_SUMMARY}" --out_dir="${OUT}" \
  --cap_sec="${FAILURE_CAP_SEC:-2000}"
