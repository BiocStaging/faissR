#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --job-name="frJ_r_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_r_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_r_audit_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
: "${COMPREHENSIVE_RESULT_ROOT:?Export COMPREHENSIVE_RESULT_ROOT}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
mkdir -p "${COMPREHENSIVE_RESULT_ROOT}/analysis" "${BASE_DIR}/benchmark_logs"

Rscript --vanilla \
  "${SUITE_ROOT}/validation/comprehensive_r_comparison/audit_comprehensive_r_comparison.R" \
  --root="${COMPREHENSIVE_RESULT_ROOT}" \
  --out_dir="${COMPREHENSIVE_RESULT_ROOT}/analysis" \
  --expected_version="${EXPECTED_FAISSR_VERSION}" \
  --expected_commit="${FAISSR_PACKAGE_COMMIT}"
