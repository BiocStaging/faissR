#!/usr/bin/env bash
set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"

HERE="benchmark_scripts/jss_reproduction/validation/query_workload"
RESULTS="/scratch/firenze/NN/faissR_JSS_REPRODUCTION/validation/query_workload"

CPU=$(sbatch --parsable --export=ALL "${HERE}/run_query_workload_cpu12.sh")
CUDA=$(sbatch --parsable --export=ALL "${HERE}/run_query_workload_cuda.sh")
CPU_AUDIT=$(sbatch --parsable --dependency="afterany:${CPU}" \
  --export=ALL,QUERY_WORKLOAD_ROOT="${RESULTS}/cpu_${CPU}" \
  "${HERE}/run_query_workload_audit_cpu12.sh")
CUDA_AUDIT=$(sbatch --parsable --dependency="afterany:${CUDA}" \
  --export=ALL,QUERY_WORKLOAD_ROOT="${RESULTS}/cuda_${CUDA}" \
  "${HERE}/run_query_workload_audit_cpu12.sh")

printf 'cpu_array=%s\ncuda_array=%s\ncpu_audit=%s\ncuda_audit=%s\n' \
  "${CPU}" "${CUDA}" "${CPU_AUDIT}" "${CUDA_AUDIT}"
