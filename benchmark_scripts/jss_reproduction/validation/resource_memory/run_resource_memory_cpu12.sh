#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --array=1-120%10
#SBATCH --job-name="frJ_mem_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_mem_cpu_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_mem_cpu_%A_%a.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
HERE="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/resource_memory"
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
DATASETS=(MetRef COIL20 MNIST flow18 imagenet)
METHODS=(auto flat hnsw ivf)
MODES=(external self)
index=$((SLURM_ARRAY_TASK_ID - 1))
repeat_id=$((index % 3 + 1)); index=$((index / 3))
mode="${MODES[$((index % 2))]}"; index=$((index / 2))
method="${METHODS[$((index % 4))]}"; index=$((index / 4))
dataset="${DATASETS[$index]}"
OUT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/resource_memory/cpu_${SLURM_ARRAY_JOB_ID}/task_${SLURM_ARRAY_TASK_ID}"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT}"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'stopifnot(identical(as.character(packageVersion("faissR")), Sys.getenv("EXPECTED_FAISSR_VERSION")))'
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${HERE}/benchmark_resource_memory.R" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --dataset="${dataset}" --backend=cpu --method="${method}" \
  --metric=euclidean --k=30 --target_recall=0.99 --query_mode="${mode}" \
  --repeat_id="${repeat_id}" --threads=12 --timeout=12000 \
  --out_dir="${OUT}"
