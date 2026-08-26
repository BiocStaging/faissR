#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
RESUME_DIR="${BASE_DIR}/benchmark_scripts/jss_reproduction/final_campaign/resume"
WRAPPER="${RESUME_DIR}/run_resume_cpu_ivfpq_shard.sh"
ORIGINAL_REL='faissR_JSS_REPRODUCTION/final_campaign/calibration/real/cpu/1189779_20260807_204531'
ORIGINAL="${BASE_DIR}/${ORIGINAL_REL}"
GRID="${ORIGINAL}/ivfpq_tuning_candidate_grid.csv"
RESULTS="${ORIGINAL}/ivfpq_tuning_results.csv"

: "${FAISSR_PACKAGE_COMMIT:?Export the frozen 40-character faissR commit}"
export SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
[[ -f "${GRID}" && -f "${RESULTS}" && -x "${WRAPPER}" && -f "${SINGULARITY_IMAGE}" ]] || {
  echo "Missing IVFPQ checkpoint, wrapper, or frozen image" >&2
  exit 2
}

missing_for_cell() {
  python3 -c 'import csv, sys
csv.field_size_limit(sys.maxsize)
grid, results, dataset, kval = sys.argv[1:]
def keys(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return {(r.get("dataset", ""), r.get("k", ""), r.get("candidate_id", ""))
                for r in csv.DictReader(handle)
                if r.get("dataset", "") == dataset and r.get("k", "") == kval}
print(len(keys(grid) - keys(results)))' "$1" "$2" "$3" "$4"
}

mkdir -p "${BASE_DIR}/benchmark_logs" \
  "${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions"
ledger="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/submissions/ivfpq_cpu_shards_$(date -u +%Y%m%d_%H%M%S).csv"
printf 'dataset,k,missing_before,job_id,original_out_dir\n' > "${ledger}"

submitted=0
for dataset in COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST imagenet MetRef mass41; do
  for kval in 15 30 50 100; do
    missing="$(missing_for_cell "${GRID}" "${RESULTS}" "${dataset}" "${kval}")"
    (( missing > 0 )) || continue
    marker="${ORIGINAL}/.faissR_ivfpq_${dataset}_k${kval}_job"
    if [[ -s "${marker}" ]]; then
      previous="$(cat "${marker}")"
      if squeue -h -j "${previous}" 2>/dev/null | grep -q .; then
        echo "Shard already active: ${previous} ${dataset} k=${kval}"
        continue
      fi
    fi
    job_id="$(sbatch --parsable \
      --export=ALL,FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}",SINGULARITY_IMAGE="${SINGULARITY_IMAGE}",DATASET="${dataset}",K_VALUE="${kval}",ORIGINAL_OUT_DIR="${ORIGINAL_REL}" \
      "${WRAPPER}")"
    printf '%s\n' "${job_id}" > "${marker}"
    printf '"%s","%s","%s","%s","%s"\n' \
      "${dataset}" "${kval}" "${missing}" "${job_id}" "${ORIGINAL_REL}" >> "${ledger}"
    echo "Submitted ${job_id}: CPU IVFPQ ${dataset} k=${kval} (${missing} missing)"
    submitted=$((submitted + 1))
  done
done
echo "Submitted shards: ${submitted}"
echo "Submission ledger: ${ledger}"
