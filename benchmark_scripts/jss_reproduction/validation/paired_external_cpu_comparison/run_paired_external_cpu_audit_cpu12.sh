#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=04:00:00
#SBATCH --job-name="frJ_pair_ext_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_pair_ext_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_pair_ext_audit_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
PUBLICATION_RUN_ID="${PUBLICATION_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/paired_external_cpu_comparison/${PUBLICATION_RUN_ID}"
Rscript "${SUITE_ROOT}/validation/paired_external_cpu_comparison/audit_paired_external_cpu.R" \
  "${ROOT}" "${ROOT}/analysis"
