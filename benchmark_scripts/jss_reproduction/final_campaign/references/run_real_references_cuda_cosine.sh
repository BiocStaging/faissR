#!/usr/bin/env bash

#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --gres=gpu:l40s:1
#SBATCH --time=48:00:00
#SBATCH --job-name="frJ_ref_cosin"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_reference_real_cuda_cosine_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_reference_real_cuda_cosine_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21.sif}"
export EXPECTED_FAISSR_VERSION='0.99.22'
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR commit embedded in the frozen image}"
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal Git commit" >&2
  exit 2
fi
export FAISSR_PACKAGE_COMMIT
export FAISSR_REQUIRE_FROZEN_IDENTITY=1
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
IMAGE_FAISSR_COMMIT="$(singularity exec --cleanenv "${SINGULARITY_IMAGE}" /bin/sh -c 'printf "%s" "${FAISSR_IMAGE_COMMIT:-}"')"
if [[ ! "${IMAGE_FAISSR_COMMIT}" == "${FAISSR_PACKAGE_COMMIT}" ]]; then
  echo "Frozen campaign requires faissR commit ${FAISSR_PACKAGE_COMMIT}, but the Singularity image reports ${IMAGE_FAISSR_COMMIT:-UNSET}" >&2
  exit 2
fi
mkdir -p "${BASE_DIR}/benchmark_logs"

COMMON_DIR="${SUITE_ROOT}/common"
DATA_ROOT="${BASE_DIR}/Data"
REAL_MANIFEST="${DATA_ROOT}/float32_dataset_manifest_jmlr.csv"
METRIC='cosine'
DATASETS='COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41'
OUT_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/final_campaign/references/real_${METRIC}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"
SEEDS="${SEEDS:-4,20260706,20260807}"
mkdir -p "${OUT_DIR}"
run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }
run_r -e 'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); library(faissR); stopifnot(faissR::cuda_available(), faissR::faiss_gpu_available()); cat("CUDA exact-reference preflight OK: ", installed, "\n", sep = "")'
if [[ ! -f "${REAL_MANIFEST}" ]]; then
  run_r "${COMMON_DIR}/make_hpc_float32_manifest.R" --data_root="${DATA_ROOT}" --out="${REAL_MANIFEST}"
fi
run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \
  --manifest="${REAL_MANIFEST}" --out_dir="${OUT_DIR}" \
  --datasets="${DATASETS}" --metrics="${METRIC}" --seeds="${SEEDS}" \
  --reference_k=100 --quality_n=1024 --audit_n=64 \
  --audit_max_ops=5e9 --audit_atol=1e-5 --audit_rtol=1e-4 \
  --threads=2 --timeout=2000 --resume=TRUE
