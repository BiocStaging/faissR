#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_select_cuda"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_select_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_select_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/faissR_JMLR_MLOSS/cuda}"
STAMP="${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_DIR:-${BASE_DIR}/faissR_JMLR_MLOSS/reviewer_response/selector/cuda_${STAMP}}"
AGGREGATE_DIR="${OUT_DIR}/aggregate"
DATASETS="${DATASETS:-COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41}"

mkdir -p "${AGGREGATE_DIR}" "${BASE_DIR}/benchmark_logs"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \
  --results_root="${RESULTS_ROOT}" --out_dir="${AGGREGATE_DIR}" --backend=cuda \
  --datasets="${DATASETS}" \
  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/analysis/analyze_leave_one_dataset_out.R" \
  --analysis_dir="${AGGREGATE_DIR}" --out_dir="${OUT_DIR}/leave_one_dataset_out"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${SUITE_ROOT}/analysis/build_publication_figures.R" \
  --analysis_dir="${AGGREGATE_DIR}" --out_dir="${OUT_DIR}/figures" --backend=cuda
