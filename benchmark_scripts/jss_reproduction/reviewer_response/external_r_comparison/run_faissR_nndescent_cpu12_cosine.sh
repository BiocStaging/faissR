#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_fr_nd_c"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_nd_c_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_fr_nd_c_%j.err
set -euo pipefail
export METHOD_ID=faissR_cpu_nndescent METHOD_LABEL=faissR_nndescent_cosine METHOD_METRIC=cosine
exec bash benchmark_scripts/jss_reproduction/reviewer_response/external_r_comparison/run_external_r_comparison_common.sh
