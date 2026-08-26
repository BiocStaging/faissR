#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
RESUME_DIR="${BASE_DIR}/benchmark_scripts/jss_reproduction/final_campaign/resume"
WRAPPER="${RESUME_DIR}/run_resume_cuda_mass41_shard.sh"

: "${FAISSR_PACKAGE_COMMIT:?Export the frozen 40-character faissR commit}"
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi

export SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Frozen Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi
if [[ ! -x "${WRAPPER}" ]]; then
  echo "Shard wrapper is missing or not executable: ${WRAPPER}" >&2
  exit 2
fi

declare -A ORIGINAL_DIRS=(
  [nsg]='faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cuda/1197023_20260813_235239'
  [vamana]='faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cuda/1197027_20260814_130224'
)

missing_for_k() {
  python3 -c 'import csv, sys
csv.field_size_limit(sys.maxsize)
grid, results, dataset, kval = sys.argv[1:]
def keys(path):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        return {(r.get("dataset", ""), r.get("k", ""), r.get("candidate_id", ""))
                for r in rows if r.get("dataset", "") == dataset and r.get("k", "") == kval}
expected = keys(grid)
observed = keys(results)
print(len(expected - observed))' "$1" "$2" "$3" "$4"
}

mkdir -p "${BASE_DIR}/benchmark_logs" \
  "${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions"
ledger="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions/mass41_cuda_shards_$(date -u +%Y%m%d_%H%M%S).csv"
printf 'method,k,missing_before,job_id,original_out_dir\n' > "${ledger}"

submitted=0
for method in nsg vamana; do
  original_rel="${ORIGINAL_DIRS[${method}]}"
  original="${BASE_DIR}/${original_rel}"
  grid="${original}/${method}_tuning_candidate_grid.csv"
  results="${original}/${method}_tuning_results.csv"
  [[ -f "${grid}" && -f "${results}" ]] || {
    echo "Missing checkpoint files in ${original}" >&2
    exit 2
  }

  for kval in 15 30 50 100; do
    missing="$(missing_for_k "${grid}" "${results}" mass41 "${kval}")"
    if (( missing == 0 )); then
      echo "Already complete: ${method} mass41 k=${kval}"
      continue
    fi

    marker="${original}/.faissR_mass41_k${kval}_job"
    if [[ -s "${marker}" ]]; then
      previous="$(cat "${marker}")"
      if squeue -h -j "${previous}" 2>/dev/null | grep -q .; then
        echo "Shard already active: ${previous} ${method} mass41 k=${kval}"
        continue
      fi
    fi

    job_id="$(sbatch --parsable \
      --export=ALL,FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}",SINGULARITY_IMAGE="${SINGULARITY_IMAGE}",METHOD="${method}",K_VALUE="${kval}",ORIGINAL_OUT_DIR="${original_rel}" \
      "${WRAPPER}")"
    printf '%s\n' "${job_id}" > "${marker}"
    printf '"%s","%s","%s","%s","%s"\n' \
      "${method}" "${kval}" "${missing}" "${job_id}" "${original_rel}" >> "${ledger}"
    echo "Submitted ${job_id}: ${method} mass41 k=${kval} (${missing} missing)"
    submitted=$((submitted + 1))
  done
done

echo "Submitted shards: ${submitted}"
echo "Submission ledger: ${ledger}"
