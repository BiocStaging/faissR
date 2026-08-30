#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --array=1-324%2
#SBATCH --job-name="frJ_conf_gpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_conf_gpu_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_conf_gpu_%A_%a.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
: "${CONFIRMATION_ID:?Export CONFIRMATION_ID}"
export EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
MANIFEST="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/calibration_confirmation/manifests/confirmation_cuda.csv"
OUT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/calibration_confirmation/runs/${CONFIRMATION_ID}/cuda/cell_${SLURM_ARRAY_TASK_ID}"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT}"

singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'actual <- as.character(packageVersion("faissR")); expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); if (!identical(actual, expected)) stop("Expected ", expected, "; found ", actual); stopifnot(faissR::cuda_available())'

singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/calibration_confirmation/run_confirmation_cell.R" \
  --manifest="${MANIFEST}" --cell_id="${SLURM_ARRAY_TASK_ID}" \
  --dataset_manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --helper="${SUITE_ROOT}/common/benchmark_method_tuning_from_reference.R" \
  --repeats=5 --timeout=4000 --reference_k=100 --quality_n=1024 \
  --seed=20260807 --out_dir="${OUT}"
