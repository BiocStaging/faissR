#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=01:00:00
#SBATCH --job-name="frJ_gpu_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_gpu_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_gpu_audit_%j.err
set -euo pipefail
: "${GPU_INTEROP_ROOT:?Export GPU_INTEROP_ROOT}"
Rscript benchmark_scripts/jss_reproduction/validation/gpu_resident_interoperability/audit_gpu_residency.R \
  --root="${GPU_INTEROP_ROOT}"
