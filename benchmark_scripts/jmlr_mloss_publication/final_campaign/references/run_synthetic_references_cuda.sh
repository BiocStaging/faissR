#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_ref_synth"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_reference_synthetic_cuda_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_reference_synthetic_cuda_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"
export EXPECTED_FAISSR_VERSION='0.99.19'
mkdir -p "${BASE_DIR}/benchmark_logs"

COMMON_DIR="${SUITE_ROOT}/common"
SYNTH_DIR="${BASE_DIR}/Data/JMLR_synthetic_MIPS"
SYNTH_MANIFEST="${SYNTH_DIR}/jmlr_synthetic_mips_manifest.csv"
OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/references/synthetic_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
SEEDS="${SEEDS:-4,20260706,20260807}"
mkdir -p "${OUT_DIR}" "${SYNTH_DIR}"
run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
run_r -e 'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); library(faissR); stopifnot(faissR::cuda_available()); cat("CUDA reference preflight OK: ", installed, "\n", sep = "")'
if [[ ! -f "${SYNTH_MANIFEST}" ]]; then
  run_r "${COMMON_DIR}/make_jmlr_synthetic_mips_manifest.R" --out_dir="${SYNTH_DIR}" --manifest="${SYNTH_MANIFEST}"
fi
run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \
  --manifest="${SYNTH_MANIFEST}" --out_dir="${OUT_DIR}/mips" \
  --datasets='synthetic_mips_n20000_p32_unit,synthetic_mips_n70000_p128_unit,synthetic_mips_n70000_p512_unit,synthetic_mips_n200000_p64_unit,synthetic_mips_n20000_p32_lognormal,synthetic_mips_n70000_p128_lognormal,synthetic_mips_n70000_p512_lognormal,synthetic_mips_n200000_p64_lognormal,synthetic_mips_n20000_p32_pareto,synthetic_mips_n70000_p128_pareto,synthetic_mips_n70000_p512_pareto,synthetic_mips_n200000_p64_pareto' \
  --metrics=inner_product --seeds="${SEEDS}" --reference_k=100 \
  --quality_n=1024 --audit_n=64 --audit_max_ops=5e9 \
  --audit_atol=1e-5 --audit_rtol=1e-4 --threads=2 --timeout=2000 --resume=TRUE
run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \
  --manifest="${SYNTH_MANIFEST}" --out_dir="${OUT_DIR}/spatial" \
  --datasets='synthetic_spatial_n10000_p2_unit,synthetic_spatial_n10000_p3_unit' \
  --metrics=euclidean --seeds="${SEEDS}" --reference_k=100 \
  --quality_n=1024 --audit_n=64 --audit_max_ops=5e9 \
  --audit_atol=1e-5 --audit_rtol=1e-4 --threads=2 --timeout=2000 --resume=TRUE
