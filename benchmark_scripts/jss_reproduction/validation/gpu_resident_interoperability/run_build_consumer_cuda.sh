#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=00:30:00
#SBATCH --job-name="frJ_gpu_cons"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_gpu_cons_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_gpu_cons_%j.err
set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
SOURCE="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/gpu_resident_interoperability/consumer/faissRGpuConsumer"
LIB="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/gpu_resident_interoperability/consumer_library"
mkdir -p "${BASE_DIR}/benchmark_logs" "${LIB}"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" \
  R CMD INSTALL --preclean --library="${LIB}" "${SOURCE}"
singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" \
  env R_LIBS_USER="${LIB}" Rscript -e \
  'stopifnot(requireNamespace("faissRGpuConsumer", quietly=TRUE)); cat("GPU consumer package ready\n")'
