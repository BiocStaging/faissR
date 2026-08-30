#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_conf_prep"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_conf_prep_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_conf_prep_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
ROOT="${CALIBRATION_RESULTS_ROOT:?Export CALIBRATION_RESULTS_ROOT containing the completed screening calibration/real directory}"
if [[ ! -d "${ROOT}/cpu" || ! -d "${ROOT}/cuda" ]]; then
  echo "CALIBRATION_RESULTS_ROOT must contain cpu/ and cuda/: ${ROOT}" >&2
  exit 2
fi
OUT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/calibration_confirmation/manifests"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT}"

for backend in cpu cuda; do
  singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
    Rscript "${SUITE_ROOT}/validation/calibration_confirmation/prepare_confirmation_manifest.R" \
    --calibration_root="${ROOT}" --backend="${backend}" \
    --top_n=3 --max_candidates=5 --family_margin=0.25 \
    --output="${OUT}/confirmation_${backend}.csv"
done
