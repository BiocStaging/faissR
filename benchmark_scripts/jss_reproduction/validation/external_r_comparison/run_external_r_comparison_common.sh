#!/usr/bin/env bash

set -euo pipefail

: "${METHOD_ID:?METHOD_ID is required}"
: "${METHOD_LABEL:?METHOD_LABEL is required}"
: "${METHOD_METRIC:?METHOD_METRIC is required}"

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif}"
EXPECTED_FAISSR_VERSION="${EXPECTED_FAISSR_VERSION:-0.99.21}"
: "${FAISSR_PACKAGE_COMMIT:?Export the 40-character faissR commit embedded in the frozen image}"

if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal Git commit" >&2
  exit 2
fi
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi

export EXPECTED_FAISSR_VERSION FAISSR_PACKAGE_COMMIT SINGULARITY_IMAGE
export FAISSR_REQUIRE_FROZEN_IDENTITY=1
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_REQUIRE_FROZEN_IDENTITY=1

IMAGE_VERSION="$(singularity exec --cleanenv "${SINGULARITY_IMAGE}" Rscript -e 'cat(as.character(utils::packageVersion("faissR")))')"
IMAGE_COMMIT="$(singularity exec --cleanenv "${SINGULARITY_IMAGE}" /bin/sh -c 'printf "%s" "${FAISSR_IMAGE_COMMIT:-}"')"
if [[ "${IMAGE_VERSION}" != "${EXPECTED_FAISSR_VERSION}" ]]; then
  echo "Expected faissR ${EXPECTED_FAISSR_VERSION}; image contains ${IMAGE_VERSION}" >&2
  exit 2
fi
if [[ "${IMAGE_COMMIT}" != "${FAISSR_PACKAGE_COMMIT}" ]]; then
  echo "Expected commit ${FAISSR_PACKAGE_COMMIT}; image reports ${IMAGE_COMMIT:-UNSET}" >&2
  exit 2
fi

mkdir -p "${BASE_DIR}/benchmark_logs"

export BACKEND=cpu
export THREADS="${THREADS:-12}"
export METHOD_METRICS="${METHOD_METRIC}"
export DATASETS="${DATASETS:-COIL20,USPS,FashionMNIST,FlowRepository_FR-FCM-ZYRM_files,flow18,MNIST,imagenet,MetRef,mass41}"
export K_VALUES="${K_VALUES:-15,30,50,100}"
export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"
export VALIDATION_SEEDS="${VALIDATION_SEEDS:-20260706,20260807}"
export REPEATS="${REPEATS:-3}"
export TIMEOUT="${TIMEOUT:-2000}"
export INCLUDE_EXTERNAL="${INCLUDE_EXTERNAL:-FALSE}"
export REQUIRED_EXTERNAL_PACKAGE="${REQUIRED_EXTERNAL_PACKAGE:-}"
export INCLUDE_GPU_RESIDENT=FALSE
export RUN_REAL=TRUE
export RUN_SPATIAL=FALSE
export SINGULARITY_GPU_FLAG=''
export OUT_DIR="${OUT_DIR:-${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/external_r_comparison/cpu/${METHOD_LABEL}/${SLURM_JOB_ID:-manual}_$(date -u +%Y%m%d_%H%M%S)}"

exec bash "${SUITE_ROOT}/common/run_one_method.sh"
