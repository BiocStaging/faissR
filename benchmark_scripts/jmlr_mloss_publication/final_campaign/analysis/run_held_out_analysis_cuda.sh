#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_final_gpu"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_final_analysis_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_final_analysis_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
mkdir -p "${BASE_DIR}/benchmark_logs"

BACKEND='cuda'
ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out/${BACKEND}"
OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/held_out_${BACKEND}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
AGG="${OUT}/real"
MIPS="${OUT}/mips"
mkdir -p "${AGG}" "${MIPS}"
run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
run_r "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \
  --results_root="${ROOT}" --out_dir="${AGG}" --backend="${BACKEND}" \
  --datasets='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41' \
  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3
run_r "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \
  --results_root="${ROOT}" --out_dir="${MIPS}" --backend="${BACKEND}" \
  --datasets='synthetic_mips_n20000_p32_unit,synthetic_mips_n70000_p128_unit,synthetic_mips_n70000_p512_unit,synthetic_mips_n200000_p64_unit,synthetic_mips_n20000_p32_lognormal,synthetic_mips_n70000_p128_lognormal,synthetic_mips_n70000_p512_lognormal,synthetic_mips_n200000_p64_lognormal,synthetic_mips_n20000_p32_pareto,synthetic_mips_n70000_p128_pareto,synthetic_mips_n70000_p512_pareto,synthetic_mips_n200000_p64_pareto' \
  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3
run_r "${SUITE_ROOT}/analysis/analyze_leave_one_dataset_out.R" \
  --analysis_dir="${AGG}" --out_dir="${OUT}/leave_one_dataset_out"
run_r "${SUITE_ROOT}/analysis/build_publication_figures.R" \
  --analysis_dir="${AGG}" --out_dir="${OUT}/figures" --backend="${BACKEND}"
