#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
HERE="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation/publication_campaign"
: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
: "${CALIBRATION_RESULTS_ROOT:?Export CALIBRATION_RESULTS_ROOT}"

if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi
if [[ ! -d "${CALIBRATION_RESULTS_ROOT}/cpu" || ! -d "${CALIBRATION_RESULTS_ROOT}/cuda" ]]; then
  echo "CALIBRATION_RESULTS_ROOT must contain cpu/ and cuda/" >&2
  exit 2
fi

export BASE_DIR SINGULARITY_IMAGE EXPECTED_FAISSR_VERSION
export FAISSR_PACKAGE_COMMIT CALIBRATION_RESULTS_ROOT
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

JSS_COMPLETE_CAMPAIGN_ID="${JSS_COMPLETE_CAMPAIGN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}_$(date -u +%Y%m%d_%H%M%S)}"
COMPREHENSIVE_RUN_ID="${JSS_COMPLETE_CAMPAIGN_ID}"
PUBLICATION_RUN_ID="${JSS_COMPLETE_CAMPAIGN_ID}"
CONFIRMATION_ID="${JSS_COMPLETE_CAMPAIGN_ID}"
RECALL_INFERENCE_ID="${JSS_COMPLETE_CAMPAIGN_ID}"
export JSS_COMPLETE_CAMPAIGN_ID COMPREHENSIVE_RUN_ID PUBLICATION_RUN_ID CONFIRMATION_ID
export RECALL_INFERENCE_ID

LEDGER_DIR="${BASE_DIR}/faissR_JSS_REPRODUCTION/submissions/complete_${JSS_COMPLETE_CAMPAIGN_ID}"
mkdir -p "${LEDGER_DIR}" "${BASE_DIR}/benchmark_logs"
export JSS_COMPLETE_LEDGER_DIR="${LEDGER_DIR}"

CONTROLLER=$(sbatch --parsable \
  --export=ALL,JSS_STAGE=r_comparison \
  "${HERE}/run_complete_campaign_controller_cpu12.sh")

cat > "${LEDGER_DIR}/campaign.txt" <<EOF
campaign_id=${JSS_COMPLETE_CAMPAIGN_ID}
initial_controller=${CONTROLLER}
image=${SINGULARITY_IMAGE}
faissR_version=${EXPECTED_FAISSR_VERSION}
faissR_commit=${FAISSR_PACKAGE_COMMIT}
calibration_results_root=${CALIBRATION_RESULTS_ROOT}
EOF

echo "Complete staged campaign: ${JSS_COMPLETE_CAMPAIGN_ID}"
echo "Initial controller: ${CONTROLLER}"
echo "Ledger: ${LEDGER_DIR}"
echo "Every later phase will be submitted automatically after its predecessor."
