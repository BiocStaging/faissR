#!/usr/bin/env bash
set -euo pipefail
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
HERE="benchmark_scripts/jss_reproduction/validation/recall_inference"
RECALL_INFERENCE_ID="${RECALL_INFERENCE_ID:-${EXPECTED_FAISSR_VERSION}}"
export RECALL_INFERENCE_ID
ROOT="/scratch/firenze/NN/faissR_JSS_REPRODUCTION/validation/recall_inference/${RECALL_INFERENCE_ID}"
CPU=$(sbatch --parsable --export=ALL "${HERE}/run_auto_cpu12.sh")
CUDA=$(sbatch --parsable --export=ALL "${HERE}/run_auto_cuda.sh")
AUDIT=$(sbatch --parsable --dependency="afterany:${CPU}:${CUDA}" \
  --export=ALL,RECALL_INFERENCE_ROOT="${ROOT}" "${HERE}/run_audit_cpu12.sh")
printf 'cpu_array=%s\ncuda_array=%s\naudit=%s\nresult_root=%s\n' \
  "${CPU}" "${CUDA}" "${AUDIT}" "${ROOT}"
