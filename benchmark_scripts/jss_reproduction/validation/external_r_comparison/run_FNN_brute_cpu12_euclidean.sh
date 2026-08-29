#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_x_FNN_bru"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_x_FNN_brute_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_x_FNN_brute_%j.err
set -euo pipefail
export METHOD_ID=FNN_brute METHOD_LABEL=FNN_brute_euclidean METHOD_METRIC=euclidean
export INCLUDE_EXTERNAL=TRUE REQUIRED_EXTERNAL_PACKAGE=FNN
export DATASETS=MetRef,COIL20,USPS
exec bash benchmark_scripts/jss_reproduction/validation/external_r_comparison/run_external_r_comparison_common.sh
