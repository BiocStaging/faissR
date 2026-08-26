#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=01:00:00
#SBATCH --job-name="frJ_merge_gpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_merge_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_merge_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SHARD_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/resume_shards"

merge_method() {
  local method="$1"
  local original_rel="$2"
  local original="${BASE_DIR}/${original_rel}"
  local results="${original}/${method}_tuning_results.csv"
  local grid="${original}/${method}_tuning_candidate_grid.csv"
  local stamp backup tmp
  stamp="$(date -u +%Y%m%d_%H%M%S)"
  backup="${results}.pre_mass41_merge_${stamp}"
  tmp="${results}.merge_${SLURM_JOB_ID:-manual}.tmp"

  local shards=()
  while IFS= read -r shard; do
    shards[${#shards[@]}]="${shard}"
  done < <(find "${SHARD_ROOT}" -mindepth 2 -maxdepth 2 -type f \
    -name "${method}_tuning_results.csv" \
    -path "*/${method}_mass41_k*/*" 2>/dev/null | sort)
  if (( ${#shards[@]} == 0 )); then
    echo "No shard results found for ${method}" >&2
    return 1
  fi

  cp -p "${results}" "${backup}"
  python3 - "${results}" "${grid}" "${tmp}" "${shards[@]}" <<'PY'
import csv
import os
import sys

csv.field_size_limit(sys.maxsize)
original, grid_path, output, *shards = sys.argv[1:]
paths = [original] + shards
fieldnames = []
rows_by_key = {}
key_columns = ("dataset", "backend", "method", "metric", "k", "candidate_id")

with open(grid_path, newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle)
    expected = {tuple(row.get(name, "") for name in key_columns) for row in reader}

for path in paths:
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for name in reader.fieldnames or []:
            if name not in fieldnames:
                fieldnames.append(name)
        for row in reader:
            key = tuple(row.get(name, "") for name in key_columns)
            if key in expected and row.get("candidate_id", ""):
                rows_by_key[key] = row

with open(output, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    for key in sorted(rows_by_key):
        writer.writerow(rows_by_key[key])

observed = set(rows_by_key)
print(f"Merged {len(shards)} shard files: {len(observed)}/{len(expected)} candidate keys")
if len(observed) < len(expected):
    print(f"Remaining candidate keys: {len(expected) - len(observed)}")
PY
  mv "${tmp}" "${results}"
  echo "Updated ${results}"
  echo "Backup  ${backup}"
}

merge_method nsg \
  'faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cuda/1197023_20260813_235239'
merge_method vamana \
  'faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cuda/1197027_20260814_130224'

echo "CUDA mass41 shard merge completed. Run audit_resume_completion.sh next."
