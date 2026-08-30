#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_pair_fit_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_pair_fit_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_pair_fit_audit_%j.err

set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/paired_cpu_fitted"
Rscript "${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/paired_cpu_comparison/audit_paired_hnsw.R" "${ROOT}" "${ROOT}/analysis"
