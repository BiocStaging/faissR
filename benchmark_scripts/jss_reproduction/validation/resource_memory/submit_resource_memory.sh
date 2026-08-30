#!/usr/bin/env bash
set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
HERE="benchmark_scripts/jss_reproduction/validation/resource_memory"
ROOT="/scratch/firenze/NN/faissR_JSS_REPRODUCTION/validation/resource_memory"
CPU=$(sbatch --parsable --export=ALL "${HERE}/run_resource_memory_cpu12.sh")
CUDA=$(sbatch --parsable --export=ALL "${HERE}/run_resource_memory_cuda.sh")
CPU_AUDIT=$(sbatch --parsable --dependency="afterany:${CPU}" --export=ALL,RESOURCE_MEMORY_ROOT="${ROOT}/cpu_${CPU}" "${HERE}/run_resource_memory_audit_cpu12.sh")
CUDA_AUDIT=$(sbatch --parsable --dependency="afterany:${CUDA}" --export=ALL,RESOURCE_MEMORY_ROOT="${ROOT}/cuda_${CUDA}" "${HERE}/run_resource_memory_audit_cpu12.sh")
printf 'cpu_array=%s\ncuda_array=%s\ncpu_audit=%s\ncuda_audit=%s\n' "${CPU}" "${CUDA}" "${CPU_AUDIT}" "${CUDA_AUDIT}"
