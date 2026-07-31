#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_w_BiocNei_cosi"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_reusable_BiocNeighbors_hnsw_cpu12_cosine_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_reusable_BiocNeighbors_hnsw_cpu12_cosine_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.19'
mkdir -p "${BASE_DIR}/benchmark_logs"

MANIFEST="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"
ROUTE='BiocNeighbors_hnsw'
export REQUIRED_EXTERNAL_PACKAGE='BiocNeighbors'
METRIC='cosine'
DATASETS='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41'
OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/reusable_external/${ROUTE}_${METRIC}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT_DIR}"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript -e 'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); package <- Sys.getenv("REQUIRED_EXTERNAL_PACKAGE"); if (!requireNamespace(package, quietly = TRUE)) stop("Frozen reusable-index campaign requires R package ", package); cat("faissR reusable-index preflight OK: ", installed, "; ", package, " ", as.character(utils::packageVersion(package)), "\n", sep = "")'
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript \
  "${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R" \
  --manifest="${MANIFEST}" --out_dir="${OUT_DIR}" \
  --route="${ROUTE}" --metric="${METRIC}" --datasets="${DATASETS}" \
  --k_values=15,30,50,100 --seeds=20260706,20260807 \
  --threads=12 --repeats=3 --timeout=2000 \
  --quality_n=1024 --reference_k=100
