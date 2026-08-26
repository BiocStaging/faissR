#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
RESUME_DIR="${BASE_DIR}/benchmark_scripts/jss_reproduction/final_campaign/resume"
PLAN="${PLAN:-${RESUME_DIR}/incomplete_calibration.tsv}"

csv_keys() {
  python3 -c 'import csv, sys; csv.field_size_limit(sys.maxsize); f=open(sys.argv[1], newline="", encoding="utf-8"); r=csv.DictReader(f); cols=[x for x in ("dataset","dataset_md5","backend","method","metric","k","candidate_id") if x in (r.fieldnames or [])]; print(len({tuple(row.get(x, "") for x in cols) for row in r}))' "$1"
}

printf '%-5s %-10s %-18s %-15s %12s %12s %12s\n' \
  backend old_job method metric candidates results missing

incomplete=0
while IFS=$'\t' read -r backend original_job method metric observed_missing resume_out_dir original_launcher; do
  [[ "${backend}" == "backend" ]] && continue
  out_dir="${BASE_DIR}/${resume_out_dir}"
  results_file="${out_dir}/${method}_tuning_results.csv"
  candidates_file="${out_dir}/${method}_tuning_candidate_grid.csv"
  results_rows=0
  candidate_rows=0
  [[ -f "${results_file}" ]] && results_rows="$(csv_keys "${results_file}")"
  [[ -f "${candidates_file}" ]] && candidate_rows="$(csv_keys "${candidates_file}")"
  missing=$((candidate_rows-results_rows))
  (( missing < 0 )) && missing=0
  printf '%-5s %-10s %-18s %-15s %12d %12d %12d\n' \
    "${backend}" "${original_job}" "${method}" "${metric}" \
    "${candidate_rows}" "${results_rows}" "${missing}"
  (( missing > 0 )) && incomplete=$((incomplete + 1))
done < "${PLAN}"

echo "Incomplete grids: ${incomplete}"
(( incomplete == 0 ))
