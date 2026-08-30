#!/usr/bin/env bash

set -euo pipefail

BACKEND="${1:?Usage: submit_held_out_resume.sh cpu|cuda TASK_FILE}"
TASK_FILE="${2:?Usage: submit_held_out_resume.sh cpu|cuda TASK_FILE}"
: "${FAISSR_PACKAGE_COMMIT:?Export the version-pinned 40-character faissR commit}"
: "${SINGULARITY_IMAGE:?Export the checksummed Singularity image path}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
TASK_FILE="$(readlink -f "${TASK_FILE}")"
N_TASKS="$(( $(wc -l < "${TASK_FILE}") - 1 ))"

if (( N_TASKS < 1 )); then
  echo "No incomplete held-out shards are listed in ${TASK_FILE}."
  exit 0
fi

case "${BACKEND}" in
  cpu)
    RUNNER="${SUITE_ROOT}/final_campaign/resume/run_held_out_shard_cpu12.sh"
    MAX_CONCURRENT="${MAX_CONCURRENT:-12}"
    ;;
  cuda)
    RUNNER="${SUITE_ROOT}/final_campaign/resume/run_held_out_shard_cuda.sh"
    MAX_CONCURRENT="${MAX_CONCURRENT:-2}"
    ;;
  *)
    echo "Backend must be cpu or cuda." >&2
    exit 2
    ;;
esac

job_id="$(sbatch --parsable \
  --array="1-${N_TASKS}%${MAX_CONCURRENT}" \
  --export=ALL,TASK_FILE="${TASK_FILE}",FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}",SINGULARITY_IMAGE="${SINGULARITY_IMAGE}",EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION}",SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}",APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}" \
  "${RUNNER}")"

echo "Submitted ${BACKEND} held-out resume array ${job_id} with ${N_TASKS} tasks (max ${MAX_CONCURRENT} concurrent)."
