#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --array=1-5%5
#SBATCH --job-name="frJ_work_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_work_cpu_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_work_cpu_%A_%a.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR commit}"
export EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT
DATASETS=(MetRef COIL20 MNIST flow18 imagenet)
DATASET="${DATASETS[$((SLURM_ARRAY_TASK_ID - 1))]}"
OUT_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/query_workload/cpu_${SLURM_ARRAY_JOB_ID}"
OUT_DIR="${OUT_ROOT}/${DATASET}"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT_DIR}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'actual <- as.character(packageVersion("faissR")); expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); if (!identical(actual, expected)) stop("Expected faissR ", expected, "; found ", actual)'

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/query_workload/benchmark_query_workload.R" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --dataset="${DATASET}" --backend=cpu --metric=euclidean --k=30 \
  --methods=auto,flat,ivf,hnsw --query_sizes=1,32,1024,full \
  --full_datasets=MetRef,COIL20,MNIST --repeats=3 --threads=12 \
  --seed=20260807 --target_recall=0.99 --out_dir="${OUT_DIR}"
