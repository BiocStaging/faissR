#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=04:00:00
#SBATCH --job-name="frJ_cpu_auto_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_cpu_auto_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_cpu_auto_audit_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/cpu_auto_selection/${EXPECTED_FAISSR_VERSION}"
Rscript "${SUITE_ROOT}/validation/cpu_auto_selection/audit_cpu_auto_selection.R" \
  "${ROOT}" "${ROOT}/analysis"
