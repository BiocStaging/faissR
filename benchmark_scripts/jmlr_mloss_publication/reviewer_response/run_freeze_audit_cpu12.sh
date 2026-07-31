#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_freeze_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_freeze_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_freeze_cpu12_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
MANIFEST="${MANIFEST:-${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv}"
PROVENANCE="${PROVENANCE:-${BASE_DIR}/Data/dataset_provenance_jss.csv}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/faissR_JMLR_MLOSS/cpu}"
STAMP="${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${BASE_DIR}/faissR_JMLR_MLOSS/reviewer_response/freeze/cpu_${STAMP}}"
DATASETS="${DATASETS:-COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41}"

mkdir -p "${OUT_DIR}" "${BASE_DIR}/benchmark_logs"
export FAISSR_CONTAINER_PATH="${SINGULARITY_IMAGE}"
export FAISSR_CONTAINER_SHA256="$(sha256sum "${SINGULARITY_IMAGE}" | awk '{print $1}')"
: "${FAISSR_PACKAGE_COMMIT:?Set FAISSR_PACKAGE_COMMIT to the immutable faissR Git commit tested by this container}"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" \
  --env FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}" \
  --env FAISSR_CONTAINER_PATH="${FAISSR_CONTAINER_PATH}" \
  --env FAISSR_CONTAINER_SHA256="${FAISSR_CONTAINER_SHA256}" \
  "${SINGULARITY_IMAGE}" Rscript "${SUITE_ROOT}/analysis/audit_publication_freeze.R" \
  --manifest="${MANIFEST}" --provenance="${PROVENANCE}" \
  --results_root="${RESULTS_ROOT}" --out_dir="${OUT_DIR}" \
  --datasets="${DATASETS}" --strict=true
