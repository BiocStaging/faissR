#!/usr/bin/env bash
set -euo pipefail

ROOT="benchmark_scripts/jss_reproduction/validation"
phase="${1:-list}"

list_phases() {
  cat <<'EOF'
all                      staged quota-safe run of every phase below
r_comparison             same-node comparison with seven external R packages
hnsw_pareto              recall-matched HNSW Pareto calibration/validation
query_workload           m=1,32,1024,n and repeated-query amortization
calibration_confirmation five isolated timings for shortlisted candidates
recall_inference         tie-aware recall and query-bootstrap lower bounds
gpu_interoperability     device-resident consumer and host-transfer decomposition
resource_memory          isolated host/device peak-memory measurements
EOF
}

if [[ "${phase}" == "list" ]]; then
  list_phases
  exit 0
fi

: "${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
if [[ ! -f "${SINGULARITY_IMAGE}" ]]; then
  echo "Singularity image does not exist: ${SINGULARITY_IMAGE}" >&2
  exit 2
fi
if [[ ! "${FAISSR_PACKAGE_COMMIT}" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "FAISSR_PACKAGE_COMMIT must be a 40-character hexadecimal commit" >&2
  exit 2
fi

export SINGULARITYENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
ledger_root="/scratch/firenze/NN/faissR_JSS_REPRODUCTION/submissions"
mkdir -p "${ledger_root}"
ledger="${ledger_root}/${phase}_$(date -u +%Y%m%d_%H%M%S).txt"

case "${phase}" in
  all)
    bash "${ROOT}/publication_campaign/submit_complete_campaign.sh" | tee "${ledger}"
    ;;
  r_comparison)
    bash "${ROOT}/comprehensive_r_comparison/submit_comprehensive_r_comparison.sh" | tee "${ledger}"
    ;;
  hnsw_pareto)
    bash "${ROOT}/paired_cpu_hnsw_pareto/submit_pareto.sh" | tee "${ledger}"
    ;;
  query_workload)
    bash "${ROOT}/query_workload/submit_query_workload.sh" | tee "${ledger}"
    ;;
  calibration_confirmation)
    bash "${ROOT}/calibration_confirmation/submit_confirmation.sh" | tee "${ledger}"
    ;;
  recall_inference)
    bash "${ROOT}/recall_inference/submit_recall_inference.sh" | tee "${ledger}"
    ;;
  gpu_interoperability)
    bash "${ROOT}/gpu_resident_interoperability/submit_gpu_interop.sh" | tee "${ledger}"
    ;;
  resource_memory)
    bash "${ROOT}/resource_memory/submit_resource_memory.sh" | tee "${ledger}"
    ;;
  *)
    echo "Unknown phase: ${phase}" >&2
    list_phases >&2
    exit 2
    ;;
esac

echo "Submission ledger: ${ledger}"
