#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=01:00:00
#SBATCH --job-name="frJ_merge_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_merge_cpu_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_merge_cpu_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SHARD_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/resume_shards"
ORIGINAL="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cpu/1189779_20260807_204531"
RESULTS="${ORIGINAL}/ivfpq_tuning_results.csv"
GRID="${ORIGINAL}/ivfpq_tuning_candidate_grid.csv"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
BACKUP="${RESULTS}.pre_shard_merge_${STAMP}"
TMP="${RESULTS}.merge_${SLURM_JOB_ID:-manual}.tmp"

shards=()
while IFS= read -r shard; do shards[${#shards[@]}]="${shard}"; done < <(
  find "${SHARD_ROOT}" -mindepth 2 -maxdepth 2 -type f \
    -name 'ivfpq_tuning_results.csv' -path '*/ivfpq_cpu_*/*' 2>/dev/null | sort
)
(( ${#shards[@]} > 0 )) || { echo "No CPU IVFPQ shard results found" >&2; exit 1; }

cp -p "${RESULTS}" "${BACKUP}"
python3 - "${RESULTS}" "${GRID}" "${TMP}" "${shards[@]}" <<'PY'
import csv
import sys

csv.field_size_limit(sys.maxsize)
original, grid_path, output, *shards = sys.argv[1:]
key_columns = ("dataset", "backend", "method", "metric", "k", "candidate_id")
with open(grid_path, newline="", encoding="utf-8") as handle:
    expected = {tuple(row.get(name, "") for name in key_columns)
                for row in csv.DictReader(handle)}
fieldnames = []
rows = {}
for path in [original] + shards:
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for name in reader.fieldnames or []:
            if name not in fieldnames:
                fieldnames.append(name)
        for row in reader:
            key = tuple(row.get(name, "") for name in key_columns)
            if key in expected and row.get("candidate_id", ""):
                rows[key] = row
with open(output, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    for key in sorted(rows):
        writer.writerow(rows[key])
print(f"Merged {len(shards)} CPU shard files: {len(rows)}/{len(expected)} candidate keys")
print(f"Remaining candidate keys: {len(expected) - len(rows)}")
PY
mv "${TMP}" "${RESULTS}"
echo "Updated ${RESULTS}"
echo "Backup  ${BACKUP}"
