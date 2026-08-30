#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=02:00:00
#SBATCH --job-name="frJ_all_ctl"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_all_ctl_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_all_ctl_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
ROOT="${BASE_DIR}/benchmark_scripts/jss_reproduction/validation"
HERE="${ROOT}/publication_campaign"
: "${JSS_STAGE:?JSS_STAGE is required}"
: "${JSS_COMPLETE_CAMPAIGN_ID:?JSS_COMPLETE_CAMPAIGN_ID is required}"
: "${JSS_COMPLETE_LEDGER_DIR:?JSS_COMPLETE_LEDGER_DIR is required}"
: "${SINGULARITY_IMAGE:?SINGULARITY_IMAGE is required}"
: "${EXPECTED_FAISSR_VERSION:?EXPECTED_FAISSR_VERSION is required}"
: "${FAISSR_PACKAGE_COMMIT:?FAISSR_PACKAGE_COMMIT is required}"
: "${CALIBRATION_RESULTS_ROOT:?CALIBRATION_RESULTS_ROOT is required}"
: "${PUBLICATION_RUN_ID:?PUBLICATION_RUN_ID is required}"
: "${CONFIRMATION_ID:?CONFIRMATION_ID is required}"
: "${RECALL_INFERENCE_ID:?RECALL_INFERENCE_ID is required}"

mkdir -p "${JSS_COMPLETE_LEDGER_DIR}" "${BASE_DIR}/benchmark_logs"

submit_retry() {
  local output status attempt=1
  while (( attempt <= 120 )); do
    set +e
    output=$(sbatch "$@" 2>&1)
    status=$?
    set -e
    if (( status == 0 )); then
      printf '%s\n' "${output%%;*}"
      return 0
    fi
    if grep -Eq 'AssocMaxSubmitJobLimit|QOSMaxSubmitJobPerUserLimit|AssocGrpCpuLimit' <<<"${output}"; then
      echo "Submission quota is full; retry ${attempt}/120 in 60 seconds: ${output}" >&2
      sleep 60
      attempt=$((attempt + 1))
      continue
    fi
    echo "sbatch failed: ${output}" >&2
    return "${status}"
  done
  echo "Submission quota did not clear within two hours" >&2
  return 1
}

record() {
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$1" "$2" \
    >> "${JSS_COMPLETE_LEDGER_DIR}/jobs.tsv"
}

next_controller() {
  local stage=$1 dependency=$2 job
  job=$(submit_retry --parsable --dependency="afterany:${dependency}" \
    --export=ALL,JSS_STAGE="${stage}" \
    "${HERE}/run_complete_campaign_controller_cpu12.sh")
  record "controller:${stage}" "${job}"
  echo "Next stage ${stage}: controller ${job} after ${dependency}"
}

submit_array_stage() {
  local label=$1 range=$2 concurrency=$3 launcher=$4 next=$5 job
  job=$(submit_retry --parsable --array="${range}%${concurrency}" --export=ALL "${launcher}")
  record "${label}" "${job}[${range}]"
  next_controller "${next}" "${job}"
}

echo "Campaign ${JSS_COMPLETE_CAMPAIGN_ID}; stage ${JSS_STAGE}"

case "${JSS_STAGE}" in
  r_comparison)
    output=$(bash "${ROOT}/comprehensive_r_comparison/submit_comprehensive_r_comparison.sh")
    printf '%s\n' "${output}" | tee "${JSS_COMPLETE_LEDGER_DIR}/r_comparison.txt"
    audit=$(awk -F= '$1 == "audit_job" {print $2}' <<<"${output}" | tail -n 1)
    [[ "${audit}" =~ ^[0-9]+$ ]] || { echo "Could not parse R-comparison audit job" >&2; exit 2; }
    next_controller hnsw_prepare "${audit}"
    ;;
  hnsw_prepare)
    job=$(submit_retry --parsable --export=ALL "${ROOT}/paired_cpu_hnsw_pareto/run_prepare_cpu12.sh")
    record hnsw_prepare "${job}"
    next_controller hnsw_cal_1 "${job}"
    ;;
  hnsw_cal_1)
    submit_array_stage hnsw_calibration 1-108 12 "${ROOT}/paired_cpu_hnsw_pareto/run_calibration_cpu12.sh" hnsw_cal_2
    ;;
  hnsw_cal_2)
    submit_array_stage hnsw_calibration 109-216 12 "${ROOT}/paired_cpu_hnsw_pareto/run_calibration_cpu12.sh" hnsw_cal_3
    ;;
  hnsw_cal_3)
    submit_array_stage hnsw_calibration 217-324 12 "${ROOT}/paired_cpu_hnsw_pareto/run_calibration_cpu12.sh" hnsw_cal_4
    ;;
  hnsw_cal_4)
    submit_array_stage hnsw_calibration 325-432 12 "${ROOT}/paired_cpu_hnsw_pareto/run_calibration_cpu12.sh" hnsw_cal_5
    ;;
  hnsw_cal_5)
    submit_array_stage hnsw_calibration 433-504 12 "${ROOT}/paired_cpu_hnsw_pareto/run_calibration_cpu12.sh" hnsw_finalize
    ;;
  hnsw_finalize)
    select=$(submit_retry --parsable --export=ALL "${ROOT}/paired_cpu_hnsw_pareto/run_select_cpu12.sh")
    validation=$(submit_retry --parsable --dependency="afterok:${select}" --export=ALL \
      "${ROOT}/paired_cpu_hnsw_pareto/run_validation_cpu12.sh")
    audit=$(submit_retry --parsable --dependency="afterany:${validation}" --export=ALL \
      "${ROOT}/paired_cpu_hnsw_pareto/run_audit_cpu12.sh")
    record hnsw_select "${select}"
    record hnsw_validation "${validation}"
    record hnsw_audit "${audit}"
    next_controller query_workload "${audit}"
    ;;
  query_workload)
    cpu=$(submit_retry --parsable --export=ALL "${ROOT}/query_workload/run_query_workload_cpu12.sh")
    cuda=$(submit_retry --parsable --export=ALL "${ROOT}/query_workload/run_query_workload_cuda.sh")
    cpu_audit=$(submit_retry --parsable --dependency="afterany:${cpu}" \
      --export=ALL,QUERY_WORKLOAD_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/query_workload/cpu_${cpu}" \
      "${ROOT}/query_workload/run_query_workload_audit_cpu12.sh")
    cuda_audit=$(submit_retry --parsable --dependency="afterany:${cuda}" \
      --export=ALL,QUERY_WORKLOAD_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/query_workload/cuda_${cuda}" \
      "${ROOT}/query_workload/run_query_workload_audit_cpu12.sh")
    record query_cpu "${cpu}"; record query_cuda "${cuda}"
    record query_cpu_audit "${cpu_audit}"; record query_cuda_audit "${cuda_audit}"
    next_controller confirmation_prepare "${cpu_audit}:${cuda_audit}"
    ;;
  confirmation_prepare)
    job=$(submit_retry --parsable --export=ALL \
      "${ROOT}/calibration_confirmation/prepare_confirmation_manifests_cpu12.sh")
    record confirmation_prepare "${job}"
    next_controller confirmation_cpu_1 "${job}"
    ;;
  confirmation_cpu_1)
    submit_array_stage confirmation_cpu 1-108 12 "${ROOT}/calibration_confirmation/run_confirmation_cpu12.sh" confirmation_cpu_2
    ;;
  confirmation_cpu_2)
    submit_array_stage confirmation_cpu 109-216 12 "${ROOT}/calibration_confirmation/run_confirmation_cpu12.sh" confirmation_cpu_3
    ;;
  confirmation_cpu_3)
    submit_array_stage confirmation_cpu 217-324 12 "${ROOT}/calibration_confirmation/run_confirmation_cpu12.sh" confirmation_cuda_1
    ;;
  confirmation_cuda_1)
    submit_array_stage confirmation_cuda 1-108 2 "${ROOT}/calibration_confirmation/run_confirmation_cuda.sh" confirmation_cuda_2
    ;;
  confirmation_cuda_2)
    submit_array_stage confirmation_cuda 109-216 2 "${ROOT}/calibration_confirmation/run_confirmation_cuda.sh" confirmation_cuda_3
    ;;
  confirmation_cuda_3)
    submit_array_stage confirmation_cuda 217-324 2 "${ROOT}/calibration_confirmation/run_confirmation_cuda.sh" confirmation_audit
    ;;
  confirmation_audit)
    audit=$(submit_retry --parsable --export=ALL \
      "${ROOT}/calibration_confirmation/run_confirmation_audit_cpu12.sh")
    record confirmation_audit "${audit}"
    next_controller recall_cpu_1 "${audit}"
    ;;
  recall_cpu_1)
    submit_array_stage recall_cpu 1-108 12 "${ROOT}/recall_inference/run_auto_cpu12.sh" recall_cpu_2
    ;;
  recall_cpu_2)
    submit_array_stage recall_cpu 109-216 12 "${ROOT}/recall_inference/run_auto_cpu12.sh" recall_cpu_3
    ;;
  recall_cpu_3)
    submit_array_stage recall_cpu 217-324 12 "${ROOT}/recall_inference/run_auto_cpu12.sh" recall_cuda_1
    ;;
  recall_cuda_1)
    submit_array_stage recall_cuda 1-108 2 "${ROOT}/recall_inference/run_auto_cuda.sh" recall_cuda_2
    ;;
  recall_cuda_2)
    submit_array_stage recall_cuda 109-216 2 "${ROOT}/recall_inference/run_auto_cuda.sh" recall_cuda_3
    ;;
  recall_cuda_3)
    submit_array_stage recall_cuda 217-324 2 "${ROOT}/recall_inference/run_auto_cuda.sh" recall_audit
    ;;
  recall_audit)
    recall_root="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/recall_inference/${RECALL_INFERENCE_ID}"
    audit=$(submit_retry --parsable --export=ALL,RECALL_INFERENCE_ROOT="${recall_root}" \
      "${ROOT}/recall_inference/run_audit_cpu12.sh")
    record recall_audit "${audit}"
    next_controller gpu_interoperability "${audit}"
    ;;
  gpu_interoperability)
    build=$(submit_retry --parsable --export=ALL \
      "${ROOT}/gpu_resident_interoperability/run_build_consumer_cuda.sh")
    run=$(submit_retry --parsable --dependency="afterok:${build}" --export=ALL \
      "${ROOT}/gpu_resident_interoperability/run_gpu_residency_cuda.sh")
    gpu_root="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/gpu_resident_interoperability/gpu_${run}"
    audit=$(submit_retry --parsable --dependency="afterany:${run}" \
      --export=ALL,GPU_INTEROP_ROOT="${gpu_root}" \
      "${ROOT}/gpu_resident_interoperability/run_audit_cpu12.sh")
    record gpu_consumer_build "${build}"; record gpu_interoperability "${run}"
    record gpu_interoperability_audit "${audit}"
    next_controller memory_cpu "${audit}"
    ;;
  memory_cpu)
    cpu=$(submit_retry --parsable --export=ALL "${ROOT}/resource_memory/run_resource_memory_cpu12.sh")
    record resource_memory_cpu "${cpu}"
    next_controller memory_cuda "${cpu}"
    ;;
  memory_cuda)
    cuda=$(submit_retry --parsable --export=ALL "${ROOT}/resource_memory/run_resource_memory_cuda.sh")
    record resource_memory_cuda "${cuda}"
    next_controller memory_audits "${cuda}"
    ;;
  memory_audits)
    cpu=$(awk -F'\t' '$2 == "resource_memory_cpu" {print $3}' "${JSS_COMPLETE_LEDGER_DIR}/jobs.tsv" | tail -n 1)
    cuda=$(awk -F'\t' '$2 == "resource_memory_cuda" {print $3}' "${JSS_COMPLETE_LEDGER_DIR}/jobs.tsv" | tail -n 1)
    [[ "${cpu}" =~ ^[0-9]+$ && "${cuda}" =~ ^[0-9]+$ ]] || {
      echo "Could not recover resource-memory array identifiers" >&2; exit 2;
    }
    cpu_audit=$(submit_retry --parsable \
      --export=ALL,RESOURCE_MEMORY_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/resource_memory/cpu_${cpu}" \
      "${ROOT}/resource_memory/run_resource_memory_audit_cpu12.sh")
    cuda_audit=$(submit_retry --parsable \
      --export=ALL,RESOURCE_MEMORY_ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/resource_memory/cuda_${cuda}" \
      "${ROOT}/resource_memory/run_resource_memory_audit_cpu12.sh")
    record resource_memory_cpu_audit "${cpu_audit}"
    record resource_memory_cuda_audit "${cuda_audit}"
    next_controller complete "${cpu_audit}:${cuda_audit}"
    ;;
  complete)
    audit_dir="${BASE_DIR}/faissR_JSS_REPRODUCTION/campaign_audit/${JSS_COMPLETE_CAMPAIGN_ID}"
    mkdir -p "${audit_dir}"
    singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" \
      Rscript "${HERE}/audit_publication_campaign.R" \
      --root="${BASE_DIR}/faissR_JSS_REPRODUCTION" \
      --out_dir="${audit_dir}"
    printf 'completed_at=%s\n' "$(date -u +%FT%TZ)" | tee "${JSS_COMPLETE_LEDGER_DIR}/COMPLETE"
    echo "All benchmark modules and their audits have finished and passed the campaign gate."
    ;;
  *)
    echo "Unknown campaign stage: ${JSS_STAGE}" >&2
    exit 2
    ;;
esac
