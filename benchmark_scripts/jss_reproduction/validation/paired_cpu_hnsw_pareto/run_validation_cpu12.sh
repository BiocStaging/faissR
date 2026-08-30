#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH --time=48:00:00
#SBATCH --array=1-72%12
#SBATCH --job-name="frJ_hp_val"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/frJ_hp_val_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/frJ_hp_val_%A_%a.err
set -euo pipefail
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jss_reproduction}"
IMAGE="${SINGULARITY_IMAGE:?Export SINGULARITY_IMAGE}"
: "${EXPECTED_FAISSR_VERSION:?Export EXPECTED_FAISSR_VERSION}"
: "${FAISSR_PACKAGE_COMMIT:?Export FAISSR_PACKAGE_COMMIT}"
PUBLICATION_RUN_ID="${PUBLICATION_RUN_ID:-${EXPECTED_FAISSR_VERSION}_${FAISSR_PACKAGE_COMMIT:0:7}}"
ROOT="${BASE_DIR}/faissR_JSS_REPRODUCTION/validation/paired_cpu_hnsw_pareto/${PUBLICATION_RUN_ID}"
MANIFEST="${ROOT}/selected_configuration_manifest.csv"

eval "$(Rscript -e '
x<-read.csv(commandArgs(TRUE)[1]); z<-x[x$task_id==as.integer(commandArgs(TRUE)[2]),]; stopifnot(nrow(z)==1L)
q<-function(x) shQuote(as.character(x)); for(n in names(z)[-1]) cat(toupper(n),"=",q(z[[n]]),"\n",sep="")
' "${MANIFEST}" "${SLURM_ARRAY_TASK_ID}")"

OUT="${ROOT}/validation/task_${SLURM_ARRAY_TASK_ID}"
mkdir -p "${OUT}" "${BASE_DIR}/benchmark_logs"
export FAISSR_PACKAGE_COMMIT EXPECTED_FAISSR_VERSION
export FAISSR_PAIRED_HELPER="${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R"
export SINGULARITYENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"
export APPTAINERENV_FAISSR_PACKAGE_COMMIT="${FAISSR_PACKAGE_COMMIT}"

singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${IMAGE}" \
  Rscript "${SUITE_ROOT}/validation/paired_cpu_comparison/benchmark_paired_hnsw.R" \
  --helper="${FAISSR_PAIRED_HELPER}" \
  --manifest="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv" \
  --out_dir="${OUT}" --dataset="${DATASET}" --k="${K}" \
  --comparator="${COMPARATOR}" --seeds=20260807 --repeats=5 \
  --threads=12 --timeout=12000 --quality_n=1024 --reference_k=100 \
  --target_recall=0.99 --phases=both \
  --faiss_hnsw_m="${FAISS_HNSW_M}" \
  --faiss_ef_construction="${FAISS_EF_CONSTRUCTION}" \
  --faiss_ef_search="${FAISS_EF_SEARCH}" \
  --comparator_hnsw_m="${COMPARATOR_HNSW_M}" \
  --comparator_ef_construction="${COMPARATOR_EF_CONSTRUCTION}" \
  --comparator_ef_search="${COMPARATOR_EF_SEARCH}"
