#!/usr/bin/env bash
set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
export PUBLICATION_RUN_ID="${PUBLICATION_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}}"
HERE="benchmark_scripts/jss_reproduction/validation/paired_cpu_hnsw_pareto"
PREP=$(sbatch --parsable --export=ALL "${HERE}/run_prepare_cpu12.sh")
CAL=$(sbatch --parsable --dependency="afterok:${PREP}" --export=ALL "${HERE}/run_calibration_cpu12.sh")
SELECT=$(sbatch --parsable --dependency="afterany:${CAL}" --export=ALL "${HERE}/run_select_cpu12.sh")
VALIDATE=$(sbatch --parsable --dependency="afterok:${SELECT}" --export=ALL "${HERE}/run_validation_cpu12.sh")
AUDIT=$(sbatch --parsable --dependency="afterany:${VALIDATE}" --export=ALL "${HERE}/run_audit_cpu12.sh")
printf 'prepare=%s\ncalibration=%s\nselect=%s\nvalidation=%s\naudit=%s\n' \
  "${PREP}" "${CAL}" "${SELECT}" "${VALIDATE}" "${AUDIT}"
