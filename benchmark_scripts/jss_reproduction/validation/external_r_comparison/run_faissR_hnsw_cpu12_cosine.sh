#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_fr_h_c"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_h_c_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_h_c_%j.err
set -euo pipefail
export METHOD_ID=faissR_cpu_hnsw METHOD_LABEL=faissR_hnsw_cosine METHOD_METRIC=cosine
exec bash benchmark_scripts/jss_reproduction/validation/external_r_comparison/run_external_r_comparison_common.sh
