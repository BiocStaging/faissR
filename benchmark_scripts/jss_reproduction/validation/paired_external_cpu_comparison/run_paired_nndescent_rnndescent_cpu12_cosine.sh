#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --array=1-36%12
#SBATCH --job-name="frJ_pair_nnd_c"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_pair_nnd_c_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_pair_nnd_c_%A_%a.err

set -euo pipefail
DATASETS=(COIL20 USPS FashionMNIST FlowRepository_FR-FCM-ZYRM_files flow18 MNIST imagenet MetRef mass41)
K_VALUES=(15 30 50 100)
ZERO=$((${SLURM_ARRAY_TASK_ID:?Run as a Slurm array} - 1))
export DATASET="${DATASETS[$((ZERO / 4))]}"
export K="${K_VALUES[$((ZERO % 4))]}"
export COMPARISON=nndescent_rnndescent
export METRIC=cosine
exec bash "${SUITE_ROOT:-/scratch/firenze/NN/benchmark_scripts/jss_reproduction}/validation/paired_external_cpu_comparison/run_paired_external_cpu_common.sh"
