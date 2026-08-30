#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_hres_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_heldout_resume_cpu12_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_heldout_resume_cpu12_%A_%a.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
TASK_FILE="${TASK_FILE:?TASK_FILE is required}"
TASK_ID="${SLURM_ARRAY_TASK_ID:?Submit this launcher with --array}"
line="$(sed -n "$((TASK_ID + 1))p" "${TASK_FILE}")"
ORIGINAL_LAUNCHER="$(printf '%s\n' "${line}" | cut -f1)"
DATASET="$(printf '%s\n' "${line}" | cut -f2)"
RESUME_RESULTS_DIRS="$(printf '%s\n' "${line}" | cut -f3)"
MISSING="$(printf '%s\n' "${line}" | cut -f4)"

export RESUME_RESULTS_DIRS
DATASET_LABEL="$(printf '%s' "${DATASET}" | tr -c 'A-Za-z0-9_' '_')"
HELD_OUT_RESULTS_ROOT="${HELD_OUT_RESULTS_ROOT:-${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out}"
export SHARD_OUT_DIR="${HELD_OUT_RESULTS_ROOT}/cpu/resume/${SLURM_ARRAY_JOB_ID}_${TASK_ID}_${DATASET_LABEL}"
mkdir -p "${SHARD_OUT_DIR}"

tmp_launcher="$(mktemp "${TMPDIR:-/tmp}/faissR_heldout_cpu_XXXXXX.sh")"
trap 'rm -f "${tmp_launcher}"' EXIT
sed \
  -e "s|^export DATASETS=.*$|export DATASETS='${DATASET}'|" \
  -e 's|^export OUT_DIR=.*$|export OUT_DIR="${SHARD_OUT_DIR}"|' \
  -e 's|^export EXPECTED_FAISSR_VERSION=.*$|export EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?EXPECTED_FAISSR_VERSION is required}"|' \
  "${ORIGINAL_LAUNCHER}" > "${tmp_launcher}"

echo "Dataset shard ${DATASET}; ${MISSING} cells were missing before resume"
bash "${tmp_launcher}"
