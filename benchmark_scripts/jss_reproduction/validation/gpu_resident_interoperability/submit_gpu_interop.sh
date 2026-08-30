#!/usr/bin/env bash
set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
HERE="benchmark_scripts/jss_reproduction/validation/gpu_resident_interoperability"
BUILD=$(sbatch --parsable --export=ALL "${HERE}/run_build_consumer_cuda.sh")
RUN=$(sbatch --parsable --dependency="afterok:${BUILD}" --export=ALL \
  "${HERE}/run_gpu_residency_cuda.sh")
ROOT="/scratch/firenze/NN/faissR_JSS_REPRODUCTION/validation/gpu_resident_interoperability/gpu_${RUN}"
AUDIT=$(sbatch --parsable --dependency="afterany:${RUN}" \
  --export=ALL,GPU_INTEROP_ROOT="${ROOT}" "${HERE}/run_audit_cpu12.sh")
printf 'consumer_build=%s\ngpu_array=%s\naudit=%s\nresult_root=%s\n' \
  "${BUILD}" "${RUN}" "${AUDIT}" "${ROOT}"
