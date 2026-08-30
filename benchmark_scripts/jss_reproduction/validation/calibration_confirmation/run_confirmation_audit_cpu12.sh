#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_conf_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_conf_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_conf_audit_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${CONFIRMATION_ID:?Export CONFIRMATION_ID}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/calibration_confirmation/runs/${CONFIRMATION_ID}"
MANIFEST_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/calibration_confirmation/manifests"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/calibration_confirmation/audit_confirmation.R" \
  "${ROOT}" "${MANIFEST_DIR}" 5
