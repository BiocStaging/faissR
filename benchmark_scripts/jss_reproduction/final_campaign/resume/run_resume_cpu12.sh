#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_resume_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_resume_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_resume_cpu12_%j.err

set -euo pipefail

: "${ORIGINAL_LAUNCHER:?ORIGINAL_LAUNCHER is required}"
: "${RESUME_OUT_DIR:?RESUME_OUT_DIR is required}"
: "${FAISSR_PACKAGE_COMMIT:?FAISSR_PACKAGE_COMMIT is required}"

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
ORIGINAL_LAUNCHER="${BASE_DIR}/${ORIGINAL_LAUNCHER#${BASE_DIR}/}"
RESUME_OUT_DIR="${BASE_DIR}/${RESUME_OUT_DIR#${BASE_DIR}/}"

if [[ ! -f "${ORIGINAL_LAUNCHER}" ]]; then
  echo "Original launcher does not exist: ${ORIGINAL_LAUNCHER}" >&2
  exit 2
fi
if [[ ! -d "${RESUME_OUT_DIR}" ]]; then
  echo "Original result directory does not exist: ${RESUME_OUT_DIR}" >&2
  exit 2
fi

export BASE_DIR RESUME_OUT_DIR FAISSR_PACKAGE_COMMIT
export RESUME_STATUSES='success,unsupported,unavailable,timeout,skipped_previous_timeout,failed,missing_reference'
export SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

tmp_launcher="$(mktemp "${TMPDIR:-/tmp}/faissR_resume_cpu_XXXXXX.sh")"
trap 'rm -f "${tmp_launcher}"' EXIT

sed \
  's|^export OUT_DIR=.*$|export OUT_DIR="${RESUME_OUT_DIR}"|' \
  "${ORIGINAL_LAUNCHER}" > "${tmp_launcher}"

if ! grep -q '^export OUT_DIR="${RESUME_OUT_DIR}"$' "${tmp_launcher}"; then
  echo "Could not replace OUT_DIR in ${ORIGINAL_LAUNCHER}" >&2
  exit 2
fi

echo "Resuming ${ORIGINAL_LAUNCHER}"
echo "Existing output: ${RESUME_OUT_DIR}"
bash "${tmp_launcher}"
