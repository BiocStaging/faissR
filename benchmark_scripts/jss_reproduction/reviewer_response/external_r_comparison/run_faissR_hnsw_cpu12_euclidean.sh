#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_fr_h_e"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_h_e_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_h_e_%j.err
set -euo pipefail
export METHOD_ID=faissR_cpu_hnsw METHOD_LABEL=faissR_hnsw_euclidean METHOD_METRIC=euclidean
exec bash benchmark_scripts/jss_reproduction/reviewer_response/external_r_comparison/run_external_r_comparison_common.sh
