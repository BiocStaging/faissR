#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_mem_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_mem_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_mem_audit_%j.err
set -euo pipefail
: "${RESOURCE_MEMORY_ROOT:?Export RESOURCE_MEMORY_ROOT}"
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
  Rscript "${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/resource_memory/audit_resource_memory.R" \
  "${RESOURCE_MEMORY_ROOT}"
