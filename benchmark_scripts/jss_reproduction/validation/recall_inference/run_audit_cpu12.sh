#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_recall_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_recall_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_recall_audit_%j.err

set -euo pipefail
: "${RECALL_INFERENCE_ROOT:?Export RECALL_INFERENCE_ROOT}"
Rscript benchmark_scripts/jss_reproduction/analysis/analyze_recall_inference.R \
  --root="${RECALL_INFERENCE_ROOT}" \
  --out_dir="${RECALL_INFERENCE_ROOT}/analysis"
