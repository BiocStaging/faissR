#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_metric_cpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_metric_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_metric_cpu12_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
STAMP="${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${BASE_DIR}/faissR_JMLR_MLOSS/reviewer_response/metric_conformance/cpu_${STAMP}}"

mkdir -p "${OUT_DIR}" "${BASE_DIR}/benchmark_logs"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'library(faissR); stopifnot(faissR::faiss_available()); cat("faissR CPU metric preflight OK\n")'
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/common/benchmark_metric_conformance.R" \
  --backend=cpu \
  --out_dir="${OUT_DIR}" \
  --methods=auto,exact,flat,bruteforce,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana \
  --metrics=euclidean,cosine,correlation,inner_product \
  --k=15 \
  --target_recall=0.99 \
  --threads=12
