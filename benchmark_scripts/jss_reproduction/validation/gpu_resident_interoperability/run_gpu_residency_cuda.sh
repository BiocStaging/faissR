#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=24:00:00
#SBATCH --array=1-15%2
#SBATCH --job-name="frJ_gpu_res"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_gpu_res_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_gpu_res_%A_%a.err
set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
DATASETS=(MetRef COIL20 MNIST flow18 imagenet)
QUERY_SIZES=(1 32 1024)
DATASET_INDEX=$(( (SLURM_ARRAY_TASK_ID - 1) / 3 ))
SIZE_INDEX=$(( (SLURM_ARRAY_TASK_ID - 1) % 3 ))
DATASET="${DATASETS[${DATASET_INDEX}]}"
QUERY_SIZE="${QUERY_SIZES[${SIZE_INDEX}]}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/gpu_resident_interoperability"
OUT="${ROOT}/gpu_${SLURM_ARRAY_JOB_ID}/task_${SLURM_ARRAY_TASK_ID}_${DATASET}_m${QUERY_SIZE}"
LIB="${ROOT}/consumer_library"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT}"
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" \
  env R_LIBS_USER="${LIB}" Rscript -e \
  'actual<-as.character(packageVersion("faissR")); expected<-Sys.getenv("EXPECTED_FAISSR_VERSION"); if(!identical(actual,expected)) stop("Expected ",expected,"; found ",actual); stopifnot(faissR::cuda_available())'
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" \
  env R_LIBS_USER="${LIB}" Rscript \
  "${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/gpu_resident_interoperability/benchmark_gpu_residency.R" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --dataset="${DATASET}" --query_size="${QUERY_SIZE}" --k=30 --repeats=5 \
  --seed=20260807 --out_dir="${OUT}"
