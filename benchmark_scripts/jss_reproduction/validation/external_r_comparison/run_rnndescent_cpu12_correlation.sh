#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_rnnd_r"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_rnnd_r_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_rnnd_r_%j.err
set -euo pipefail
export METHOD_ID=rnndescent_nnd METHOD_LABEL=rnndescent_nnd_correlation METHOD_METRIC=correlation
export INCLUDE_EXTERNAL=TRUE REQUIRED_EXTERNAL_PACKAGE=rnndescent
exec bash benchmark_scripts/jss_reproduction/validation/external_r_comparison/run_external_r_comparison_common.sh
