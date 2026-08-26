#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
RESUME_DIR="${BASE_DIR}/benchmark_scripts/jss_reproduction/final_campaign/resume"
PLAN="${PLAN:-${RESUME_DIR}/incomplete_calibration.tsv}"
BACKEND_FILTER="${1:-all}"

case "${BACKEND_FILTER}" in
  all|cpu|cuda) ;;
  *) echo "Usage: $0 [all|cpu|cuda]" >&2; exit 2 ;;
esac

: "${FAISSR_PACKAGE_COMMIT:?Export the frozen 40-character faissR commit}"
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -f "${PLAN}" ]]; then
  echo "Resume plan does not exist: ${PLAN}" >&2
  exit 2
fi

export SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Frozen Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

mkdir -p "${BASE_DIR}/benchmark_logs" "${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions"
ledger="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions/resume_${BACKEND_FILTER}_$(date -u +%Y%m%d_%H%M%S).csv"
printf 'backend,original_job,method,metric,resume_out_dir,job_id\n' > "${ledger}"

csv_keys() {
  python3 -c 'import csv, sys; csv.field_size_limit(sys.maxsize); f=open(sys.argv[1], newline="", encoding="utf-8"); r=csv.DictReader(f); cols=[x for x in ("dataset","dataset_md5","backend","method","metric","k","candidate_id") if x in (r.fieldnames or [])]; print(len({tuple(row.get(x, "") for x in cols) for row in r}))' "$1"
}

submitted=0
skipped_complete=0
while IFS=$'\t' read -r backend original_job method metric observed_missing resume_out_dir original_launcher; do
  [[ "${backend}" == "backend" ]] && continue
  if [[ "${BACKEND_FILTER}" != "all" && "${backend}" != "${BACKEND_FILTER}" ]]; then
    continue
  fi

  out_dir="${BASE_DIR}/${resume_out_dir}"
  results_file="${out_dir}/${method}_tuning_results.csv"
  candidates_file="${out_dir}/${method}_tuning_candidate_grid.csv"
  if [[ ! -f "${results_file}" || ! -f "${candidates_file}" ]]; then
    echo "Missing checkpoint files for original job ${original_job}: ${out_dir}" >&2
    exit 2
  fi

  if squeue -h -j "${original_job}" 2>/dev/null | grep -q .; then
    echo "Original job is still active; skipping for now: ${original_job} ${backend} ${method} ${metric}"
    continue
  fi

  resume_marker="${out_dir}/.faissR_resume_job"
  if [[ -s "${resume_marker}" ]]; then
    previous_resume="$(cat "${resume_marker}")"
    if squeue -h -j "${previous_resume}" 2>/dev/null | grep -q .; then
      echo "Resume job is already active; skipping: ${previous_resume} ${backend} ${method} ${metric}"
      continue
    fi
  fi

  results_rows="$(csv_keys "${results_file}")"
  candidate_rows="$(csv_keys "${candidates_file}")"
  if (( results_rows >= candidate_rows )); then
    echo "Already complete: ${backend} ${method} ${metric} (${results_rows}/${candidate_rows})"
    skipped_complete=$((skipped_complete + 1))
    continue
  fi

  wrapper="${RESUME_DIR}/run_resume_${backend/cpu/cpu12}.sh"
  if [[ "${backend}" == "cuda" ]]; then wrapper="${RESUME_DIR}/run_resume_cuda.sh"; fi
  job_id=$(sbatch --parsable \
    --export=ALL,FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}",SINGULARITY_IMAGE="${SINGULARITY_IMAGE}",ORIGINAL_LAUNCHER="${original_launcher}",RESUME_OUT_DIR="${resume_out_dir}" \
    "${wrapper}")
  printf '%s\n' "${job_id}" > "${resume_marker}"
  printf '"%s","%s","%s","%s","%s","%s"\n' \
    "${backend}" "${original_job}" "${method}" "${metric}" "${resume_out_dir}" "${job_id}" >> "${ledger}"
  echo "Submitted ${job_id}: ${backend} ${method} ${metric} (${results_rows}/${candidate_rows}; $((candidate_rows-results_rows)) missing)"
  submitted=$((submitted + 1))
done < "${PLAN}"

echo "Submitted: ${submitted}; already complete: ${skipped_complete}"
echo "Resume ledger: ${ledger}"
