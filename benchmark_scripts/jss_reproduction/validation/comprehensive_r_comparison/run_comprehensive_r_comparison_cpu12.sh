#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --array=1-216%12
#SBATCH --job-name="frJ_r_all"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_r_all_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_r_all_%A_%a.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
: "${COMPREHENSIVE_RUN_ID:?COMPREHENSIVE_RUN_ID is assigned by the submitter}"

DATASETS=(COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST imagenet MetRef mass41)
METRICS=(euclidean cosine correlation)
K_VALUES=(15 30 50 100)
SEEDS=(20260706 20260807)

zero=$((${SLURM_ARRAY_TASK_ID:?Run as a Slurm array} - 1))
seed=${SEEDS[$((zero % 2))]}
zero=$((zero / 2))
k=${K_VALUES[$((zero % 4))]}
zero=$((zero / 4))
metric=${METRICS[$((zero % 3))]}
zero=$((zero / 3))
dataset=${DATASETS[$zero]}

ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/comprehensive_r_comparison/${COMPREHENSIVE_RUN_ID}"
OUT="${ROOT}/task_$(printf '%03d' "${SLURM_ARRAY_TASK_ID}")_${dataset}_${metric}_k${k}_seed${seed}"
mkdir -p "${BASE_DIR}/benchmark_logs" "${OUT}"

export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript --vanilla \
  "${SUITE_ROOT}/validation/comprehensive_r_comparison/benchmark_comprehensive_r_comparison.R" \
  --dataset="${dataset}" --metric="${metric}" --k="${k}" \
  --validation_seed="${seed}" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --suite_root="${SUITE_ROOT}" --out_dir="${OUT}" \
  --threads=12 --repeats=3 --timeout=1200 --target_recall=0.99 \
  --quality_n=1024 --reference_k=100
