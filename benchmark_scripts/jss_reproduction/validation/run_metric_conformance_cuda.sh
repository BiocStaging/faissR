#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_metric_cuda"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_metric_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_metric_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
STAMP="${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/metric_conformance/cuda_${STAMP}}"

mkdir -p "${OUT_DIR}" "${BASE_DIR}/benchmark_logs"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript -e 'library(faissR); stopifnot(faissR::cuda_available(), faissR::cuvs_available()); cat("faissR CUDA metric preflight OK\n")'
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/common/benchmark_metric_conformance.R" \
  --backend=cuda \
  --out_dir="${OUT_DIR}" \
  --methods=auto,exact,flat,bruteforce,hnsw,ivf,ivfpq,ivfpq_fastscan,nndescent,nsg,vamana,cagra \
  --metrics=euclidean,cosine,correlation \
  --k=15 \
  --target_recall=0.99 \
  --threads=2
