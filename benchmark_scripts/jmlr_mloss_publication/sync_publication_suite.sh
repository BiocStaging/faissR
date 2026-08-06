#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 /path/to/HPC-mirror-root" >&2
  echo "The target root must contain benchmark_scripts/ and will not be cleaned." >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$1"
TARGET_SUITE="${TARGET_ROOT}/benchmark_scripts/jmlr_mloss_publication"
SOURCE_CAMPAIGN="${SCRIPT_DIR}/final_campaign"
TARGET_CAMPAIGN="${TARGET_SUITE}/final_campaign"

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required to synchronize the publication suite." >&2
  exit 2
fi
if [[ ! -f "${SOURCE_CAMPAIGN}/submit_campaign.R" ]]; then
  echo "Source campaign is incomplete: submit_campaign.R is missing." >&2
  exit 2
fi

mkdir -p "${TARGET_SUITE}"
rsync -a "${SCRIPT_DIR}/" "${TARGET_SUITE}/"

source_count="$(find "${SOURCE_CAMPAIGN}" -type f -name '*.sh' | wc -l | tr -d ' ')"
target_count="$(find "${TARGET_CAMPAIGN}" -type f -name '*.sh' | wc -l | tr -d ' ')"
if [[ "${source_count}" != "277" || "${target_count}" != "277" ]]; then
  echo "Expected 277 launchers; source=${source_count}, target=${target_count}." >&2
  echo "The target may contain obsolete extra files; inspect it before submission." >&2
  exit 2
fi

source_submitter_sha="$(shasum -a 256 "${SOURCE_CAMPAIGN}/submit_campaign.R" | awk '{print $1}')"
target_submitter_sha="$(shasum -a 256 "${TARGET_CAMPAIGN}/submit_campaign.R" | awk '{print $1}')"
if [[ "${source_submitter_sha}" != "${target_submitter_sha}" ]]; then
  echo "submit_campaign.R checksum differs after synchronization." >&2
  exit 2
fi

find "${TARGET_CAMPAIGN}" -type f -name '*.sh' -print0 |
  xargs -0 -n1 bash -n

echo "Publication suite synchronized successfully."
echo "Target: ${TARGET_SUITE}"
echo "Launchers: ${target_count}"
echo "submit_campaign.R SHA-256: ${target_submitter_sha}"
echo
echo "On the HPC, start with:"
echo "  cd /scratch/firenze/NN"
echo "  export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda_faissR_0.99.21.sif"
echo "  Rscript benchmark_scripts/jmlr_mloss_publication/final_campaign/submit_campaign.R --phase=list"
echo "  Rscript benchmark_scripts/jmlr_mloss_publication/final_campaign/submit_campaign.R --phase=qa"
