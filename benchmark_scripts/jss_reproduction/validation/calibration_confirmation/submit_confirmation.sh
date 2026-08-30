#!/usr/bin/env bash

set -euo pipefail
: "${CALIBRATION_RESULTS_ROOT:?Export CALIBRATION_RESULTS_ROOT containing the completed screening calibration/real directory}"
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
CONFIRMATION_ID="${CONFIRMATION_ID:-$(date -u +%Y%m%d_%H%M%S)}"
export CONFIRMATION_ID
ROOT="benchmark_scripts/jss_reproduction/validation/calibration_confirmation"

prep=$(sbatch --parsable --export=ALL "${ROOT}/prepare_confirmation_manifests_cpu12.sh")
cpu=$(sbatch --parsable --dependency="afterok:${prep}" --export=ALL "${ROOT}/run_confirmation_cpu12.sh")
cuda=$(sbatch --parsable --dependency="afterok:${prep}" --export=ALL "${ROOT}/run_confirmation_cuda.sh")
audit=$(sbatch --parsable --dependency="afterany:${cpu}:${cuda}" --export=ALL "${ROOT}/run_confirmation_audit_cpu12.sh")

printf 'confirmation_id=%s\nprepare=%s\ncpu=%s\ncuda=%s\naudit=%s\n' \
  "${CONFIRMATION_ID}" "${prep}" "${cpu}" "${cuda}" "${audit}"
