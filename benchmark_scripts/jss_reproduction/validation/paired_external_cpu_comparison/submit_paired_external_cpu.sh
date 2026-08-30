#!/usr/bin/env bash

set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR experiment commit}"
export PUBLICATION_RUN_ID="${PUBLICATION_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}}"

ROOT="${SUITE_ROOT:-/scratch/firenze/NN/benchmark_scripts/jss_reproduction}/validation/paired_external_cpu_comparison"
bash "${ROOT}/preflight_paired_external_cpu.sh"

jobs=()
for launcher in \
  run_paired_exact_fnn_cpu12_euclidean.sh \
  run_paired_nndescent_rnndescent_cpu12_euclidean.sh \
  run_paired_nndescent_rnndescent_cpu12_cosine.sh \
  run_paired_nndescent_rnndescent_cpu12_correlation.sh
do
  job=$(sbatch --parsable \
    --export=ALL,SINGULARITY_IMAGE="${SINGULARITY_IMAGE}",EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION}",FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}" \
    "${ROOT}/${launcher}")
  jobs+=("${job}")
  echo "${job}  ${launcher}"
done
dependency=$(IFS=:; echo "${jobs[*]}")
audit=$(sbatch --parsable --dependency="afterany:${dependency}" --export=ALL \
  "${ROOT}/run_paired_external_cpu_audit_cpu12.sh")
echo "${audit}  audit"
