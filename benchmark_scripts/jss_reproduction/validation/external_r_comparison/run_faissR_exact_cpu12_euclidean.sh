#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_fr_exact"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_exact_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_exact_%j.err
set -euo pipefail
export METHOD_ID=faissR_cpu_exact METHOD_LABEL=faissR_exact_euclidean METHOD_METRIC=euclidean
exec bash benchmark_scripts/jss_reproduction/validation/external_r_comparison/run_external_r_comparison_common.sh
