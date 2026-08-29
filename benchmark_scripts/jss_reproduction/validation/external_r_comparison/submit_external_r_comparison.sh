#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
HERE="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/external_r_comparison"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character commit embedded in the frozen image}"
: "${SINGULARITY_IMAGE:?Export the frozen Singularity image path}"

launchers=(
  run_faissR_exact_cpu12_euclidean.sh
  run_FNN_brute_cpu12_euclidean.sh
  run_faissR_hnsw_cpu12_euclidean.sh
  run_faissR_hnsw_cpu12_cosine.sh
  run_RcppHNSW_cpu12_euclidean.sh
  run_RcppHNSW_cpu12_cosine.sh
  run_faissR_nndescent_cpu12_euclidean.sh
  run_faissR_nndescent_cpu12_cosine.sh
  run_faissR_nndescent_cpu12_correlation.sh
  run_rnndescent_cpu12_euclidean.sh
  run_rnndescent_cpu12_cosine.sh
  run_rnndescent_cpu12_correlation.sh
)

job_ids=()
for launcher in "${launchers[@]}"; do
  job_id="$(sbatch --parsable --export=ALL "${HERE}/${launcher}")"
  job_ids+=("${job_id}")
  printf '%s  %s\n' "${job_id}" "${launcher}"
done

dependency="$(IFS=:; echo "${job_ids[*]}")"
audit_id="$(sbatch --parsable --dependency="afterany:${dependency}" --export=ALL "${HERE}/run_external_r_comparison_audit_cpu12.sh")"
printf '%s  %s\n' "${audit_id}" "run_external_r_comparison_audit_cpu12.sh"
