#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_cal_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_calibration_audit_cpu12_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_calibration_audit_cpu12_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
mkdir -p "${BASE_DIR}/benchmark_logs"

run_r() { singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration"
OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/calibration_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT}/real" "${OUT}/mips"
run_r "${SUITE_ROOT}/analysis/aggregate_calibration_results.R" \
  --calibration_root="${ROOT}/real" --out_dir="${OUT}/real" \
  --datasets='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41' \
  --metrics=euclidean,cosine,correlation,inner_product \
  --k_values=15,30,50,100 --target_recalls=0.9,0.95,0.99
run_r "${SUITE_ROOT}/analysis/aggregate_calibration_results.R" \
  --calibration_root="${ROOT}/mips" --out_dir="${OUT}/mips" \
  --datasets='synthetic_mips_n20000_p32_unit,synthetic_mips_n70000_p128_unit,synthetic_mips_n70000_p512_unit,synthetic_mips_n200000_p64_unit,synthetic_mips_n20000_p32_lognormal,synthetic_mips_n70000_p128_lognormal,synthetic_mips_n70000_p512_lognormal,synthetic_mips_n200000_p64_lognormal,synthetic_mips_n20000_p32_pareto,synthetic_mips_n70000_p128_pareto,synthetic_mips_n70000_p512_pareto,synthetic_mips_n200000_p64_pareto' \
  --metrics=inner_product --k_values=15,30,50,100 \
  --target_recalls=0.9,0.95,0.99
