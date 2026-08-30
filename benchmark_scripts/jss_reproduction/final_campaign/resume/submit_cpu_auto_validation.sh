#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
CAMPAIGN_RESULTS_ROOT="${CAMPAIGN_RESULTS_ROOT:-${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign}"
: "${FAISSR_PACKAGE_COMMIT:?Export the version-pinned 40-character faissR commit}"
: "${SINGULARITY_IMAGE:?Export the checksummed Singularity image path}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal Git commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%d_%H%M%S)"
TASK_DIR="${CAMPAIGN_RESULTS_ROOT}/submissions/cpu_auto_validation_${STAMP}"
mkdir -p "${TASK_DIR}"

python3 "${SUITE_ROOT}/final_campaign/resume/prepare_held_out_resume.py" \
  --suite-root="${SUITE_ROOT}" \
  --results-root="${CAMPAIGN_RESULTS_ROOT}/held_out" \
  --out-dir="${TASK_DIR}" \
  --scope=publication \
  --backends=cpu \
  --methods=faissR_cpu_auto

TASK_FILE="${TASK_DIR}/held_out_resume_cpu.tsv"
N_TASKS="$(( $(wc -l < "${TASK_FILE}") - 1 ))"
if (( N_TASKS == 0 )); then
  echo "CPU automatic validation already has every successful replicate."
  exit 0
fi

export TASK_FILE
export CAMPAIGN_RESULTS_ROOT
export HELD_OUT_RESULTS_ROOT="${CAMPAIGN_RESULTS_ROOT}/held_out"
export EXPECTED_FAISSR_VERSION
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

bash "${SUITE_ROOT}/final_campaign/resume/submit_held_out_resume.sh" \
  cpu "${TASK_FILE}"

echo "Focused CPU-auto task audit: ${TASK_DIR}/held_out_completion.csv"
