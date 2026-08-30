#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=01:00:00
#SBATCH --job-name="frJ_work_audit"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_work_audit_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_work_audit_%j.err

set -euo pipefail
: "${QUERY_WORKLOAD_ROOT:?Export QUERY_WORKLOAD_ROOT}"
Rscript benchmark_scripts/jss_reproduction/validation/query_workload/audit_query_workload.R \
  "${QUERY_WORKLOAD_ROOT}"
