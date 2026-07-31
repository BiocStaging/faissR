#!/usr/bin/env Rscript

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (!length(file_arg)) return(normalizePath(getwd(), mustWork = TRUE))
  normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)
}

campaign_dir <- dirname(script_path())
description_path <- normalizePath(
  file.path(campaign_dir, "..", "..", "..", "DESCRIPTION"),
  mustWork = TRUE
)
publication_version <- unname(read.dcf(description_path)[1L, "Version"])
real_datasets <- paste(
  c(
    "COIL20", "USPS", "FashionMNIST",
    "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST", "imagenet",
    "MetRef", "mass41"
  ),
  collapse = ","
)
mips_datasets <- paste(
  as.vector(outer(
    c(
      "synthetic_mips_n20000_p32",
      "synthetic_mips_n70000_p128",
      "synthetic_mips_n70000_p512",
      "synthetic_mips_n200000_p64"
    ),
    c("unit", "lognormal", "pareto"),
    paste,
    sep = "_"
  )),
  collapse = ","
)
spatial_datasets <- paste(
  c("synthetic_spatial_n10000_p2_unit", "synthetic_spatial_n10000_p3_unit"),
  collapse = ","
)
metrics <- c("euclidean", "cosine", "correlation", "inner_product")
cpu_tuning_methods <- c(
  "bruteforce", "exact", "flat", "hnsw", "ivf", "ivfpq",
  "ivfpq_fastscan", "nndescent", "nsg", "vamana"
)
cuda_tuning_methods <- c(cpu_tuning_methods, "cagra")

generated_sections <- c(
  "calibration", "held_out", "references", "reusable_external",
  "ablations", "qa", "analysis"
)
unlink(file.path(campaign_dir, generated_sections), recursive = TRUE, force = TRUE)

shell_quote <- function(x) {
  paste0("'", gsub("'", "'\"'\"'", x, fixed = TRUE), "'")
}

write_executable <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0755")
}

sha256_file <- function(path) {
  sha256sum <- Sys.which("sha256sum")
  shasum <- Sys.which("shasum")
  if (nzchar(sha256sum)) {
    line <- system2(sha256sum, shQuote(path), stdout = TRUE)
  } else if (nzchar(shasum)) {
    line <- system2(shasum, c("-a", "256", shQuote(path)), stdout = TRUE)
  } else {
    return(NA_character_)
  }
  sub("[[:space:]].*$", "", line[[1L]])
}

slurm_header <- function(backend, job_name, log_stem) {
  resources <- if (identical(backend, "cpu")) {
    c(
      "#!/usr/bin/env bash",
      "",
      "#SBATCH --account=immunology",
      "#SBATCH --partition=ada",
      "#SBATCH --nodes=1",
      "#SBATCH --ntasks=12",
      "#SBATCH --time=48:00:00"
    )
  } else {
    c(
      "#!/usr/bin/env bash",
      "",
      "#SBATCH --account=l40sfree",
      "#SBATCH --partition=l40s",
      "#SBATCH --nodes=1",
      "#SBATCH --ntasks=2",
      "#SBATCH --gres=gpu:l40s:1",
      "#SBATCH --time=48:00:00"
    )
  }
  c(
    resources,
    sprintf('#SBATCH --job-name="%s"', job_name),
    "#SBATCH --chdir=/scratch/firenze/NN",
    sprintf(
      "#SBATCH --output=/scratch/firenze/NN/benchmark_logs/%s_%%j.out",
      log_stem
    ),
    sprintf(
      "#SBATCH --error=/scratch/firenze/NN/benchmark_logs/%s_%%j.err",
      log_stem
    ),
    "",
    "set -euo pipefail",
    ""
  )
}

common_environment <- c(
  'BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"',
  'SUITE_ROOT="${SUITE_ROOT:-${BASE_DIR}/benchmark_scripts/jmlr_mloss_publication}"',
  'SINGULARITY_IMAGE="${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}"',
  sprintf(
    "export EXPECTED_FAISSR_VERSION=%s",
    shell_quote(publication_version)
  ),
  'mkdir -p "${BASE_DIR}/benchmark_logs"',
  ""
)

write_calibration <- function(backend, method, metric, suite) {
  is_cpu <- identical(backend, "cpu")
  suffix <- if (is_cpu) "cpu12" else "cuda"
  directory <- file.path(campaign_dir, "calibration", suite, backend)
  filename <- sprintf(
    "run_tune_faissR_%s_%s_%s_%s.sh",
    method, suffix, metric, suite
  )
  method_label <- sprintf("faissR_%s_%s_%s", method, metric, suite)
  datasets <- if (identical(suite, "real")) real_datasets else mips_datasets
  manifest <- if (identical(suite, "real")) {
    '${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv'
  } else {
    '${BASE_DIR}/Data/JMLR_synthetic_MIPS/jmlr_synthetic_mips_manifest.csv'
  }
  lines <- c(
    slurm_header(
      backend,
      sprintf("frJ_t_%s_%s", substr(method, 1L, 7L), substr(metric, 1L, 4L)),
      sprintf("frJ_tune_%s_%s_%s_%s", method, suffix, metric, suite)
    ),
    common_environment,
    sprintf('export METHOD=%s', shell_quote(method)),
    sprintf('export METHOD_LABEL=%s', shell_quote(method_label)),
    sprintf('export BACKEND=%s', shell_quote(backend)),
    sprintf('export METRICS=%s', shell_quote(metric)),
    sprintf('export DATASETS=%s', shell_quote(datasets)),
    sprintf('export THREADS="${THREADS:-%d}"', if (is_cpu) 12L else 2L),
    sprintf('export THREAD_VALUES="${THREAD_VALUES:-%s}"', if (is_cpu) "12" else "2"),
    'export K_VALUES="${K_VALUES:-15,30,50,100}"',
    'export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"',
    'export TIMEOUT="${TIMEOUT:-2000}"',
    'export QUALITY_N="${QUALITY_N:-1024}"',
    'export CALIBRATION_SEED="${CALIBRATION_SEED:-4}"',
    'export GRID_LEVEL="${GRID_LEVEL:-wide}"',
    'export OUTPUT_VALUES="${OUTPUT_VALUES:-double}"',
    sprintf('export REAL_MANIFEST="%s"', manifest),
    sprintf(
      'export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration/%s/%s/${SLURM_JOB_ID:-manual}_$(date +%%Y%%m%%d_%%H%%M%%S)"',
      suite, backend
    ),
    sprintf('export SINGULARITY_GPU_FLAG=%s', shell_quote(if (is_cpu) "" else "--nv")),
    'export SINGULARITY_IMAGE',
    'exec bash "${SUITE_ROOT}/common/run_one_inner_product_tuning.sh"'
  )
  write_executable(file.path(directory, filename), lines)
}

cpu_specs <- data.frame(
  method_id = c(
    paste0("faissR_cpu_", c("auto", cpu_tuning_methods, "grid")),
    "BiocNeighbors_annoy", "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
    "RANN_bd", "RANN_kd", "RcppAnnoy_euclidean", "Rnanoflann_standard",
    "FNN_kd", "FNN_cover", "FNN_brute", "nabor_auto", "nabor_brute",
    "rnndescent_bruteforce", "rnndescent_nnd", "rnndescent_rnnd",
    "rnndescent_rpf", "uwot_nearest_neighbors"
  ),
  label = c(
    paste0("faissR_", c("auto", cpu_tuning_methods, "grid")),
    "BiocNeighbors_annoy", "BiocNeighbors_exhaustive", "BiocNeighbors_hnsw",
    "RANN_bd", "RANN_kd", "RcppAnnoy_euclidean", "Rnanoflann_standard",
    "FNN_kd", "FNN_cover", "FNN_brute", "nabor_auto", "nabor_brute",
    "rnndescent_bruteforce", "rnndescent_nnd", "rnndescent_rnnd",
    "rnndescent_rpf", "uwot_nearest_neighbors"
  ),
  metrics = I(c(
    rep(list(metrics), 1L + length(cpu_tuning_methods)),
    list("euclidean"),
    rep(list(c("euclidean", "cosine")), 3L),
    rep(list("euclidean"), 14L)
  )),
  external = c(
    rep(FALSE, 2L + length(cpu_tuning_methods)),
    rep(TRUE, 17L)
  ),
  spatial = c(
    rep(FALSE, 1L + length(cpu_tuning_methods)),
    TRUE,
    rep(FALSE, 17L)
  ),
  stringsAsFactors = FALSE
)

cuda_specs <- data.frame(
  method_id = c(
    paste0("faissR_cuda_", c("auto", cuda_tuning_methods)),
    paste0(
      "faissR_cuda_gpu_resident_",
      c("auto", "bruteforce", "exact", "flat")
    ),
    "faissR_cuda_grid", "cuda_ml_knn"
  ),
  label = c(
    paste0("faissR_", c("auto", cuda_tuning_methods)),
    paste0(
      "faissR_gpu_resident_",
      c("auto", "bruteforce", "exact", "flat")
    ),
    "faissR_grid", "cuda_ml_knn"
  ),
  metrics = I(c(
    rep(list(metrics), 1L + length(cuda_tuning_methods) + 4L),
    list("euclidean"), list("euclidean")
  )),
  external = c(
    rep(FALSE, 1L + length(cuda_tuning_methods) + 4L + 1L),
    TRUE
  ),
  spatial = c(
    rep(FALSE, 1L + length(cuda_tuning_methods) + 4L),
    TRUE, FALSE
  ),
  stringsAsFactors = FALSE
)

external_package_for <- function(method_id) {
  prefixes <- c(
    BiocNeighbors = "BiocNeighbors",
    RANN = "RANN",
    RcppAnnoy = "RcppAnnoy",
    Rnanoflann = "Rnanoflann",
    FNN = "FNN",
    nabor = "nabor",
    rnndescent = "rnndescent",
    uwot = "uwot"
  )
  matched <- names(prefixes)[startsWith(method_id, names(prefixes))]
  if (!length(matched)) return("")
  unname(prefixes[[matched[[1L]]]])
}

write_held_out <- function(backend, spec, metric) {
  is_cpu <- identical(backend, "cpu")
  suffix <- if (is_cpu) "cpu12" else "cuda"
  directory <- file.path(campaign_dir, "held_out", backend)
  filename <- sprintf(
    "run_%s_%s_%s.sh",
    gsub("[^A-Za-z0-9_]+", "_", spec$label), suffix, metric
  )
  is_spatial <- isTRUE(spec$spatial)
  is_external <- isTRUE(spec$external)
  is_faiss <- startsWith(spec$method_id, "faissR_")
  run_mips <- is_faiss && identical(metric, "inner_product") && !is_spatial
  required_external_package <- if (is_external && is_cpu) {
    external_package_for(spec$method_id)
  } else {
    ""
  }
  lines <- c(
    slurm_header(
      backend,
      sprintf("frJ_h_%s_%s", substr(spec$label, 1L, 7L), substr(metric, 1L, 4L)),
      sprintf("frJ_hold_%s_%s_%s", spec$label, suffix, metric)
    ),
    common_environment,
    sprintf('export METHOD_ID=%s', shell_quote(spec$method_id)),
    sprintf(
      'export METHOD_LABEL=%s',
      shell_quote(sprintf("%s_%s", spec$label, metric))
    ),
    sprintf('export BACKEND=%s', shell_quote(backend)),
    sprintf('export THREADS="${THREADS:-%d}"', if (is_cpu) 12L else 2L),
    sprintf('export METHOD_METRICS=%s', shell_quote(metric)),
    sprintf('export DATASETS=%s', shell_quote(real_datasets)),
    'export K_VALUES="${K_VALUES:-15,30,50,100}"',
    'export TARGET_RECALLS="${TARGET_RECALLS:-0.9,0.95,0.99}"',
    'export VALIDATION_SEEDS="${VALIDATION_SEEDS:-20260706,20260807}"',
    'export REPEATS="${REPEATS:-3}"',
    'export TIMEOUT="${TIMEOUT:-2000}"',
    sprintf('export INCLUDE_EXTERNAL=%s', shell_quote(if (is_external) "TRUE" else "FALSE")),
    sprintf(
      'export REQUIRED_EXTERNAL_PACKAGE=%s',
      shell_quote(required_external_package)
    ),
    sprintf(
      'export INCLUDE_GPU_RESIDENT=%s',
      shell_quote(if (is_cpu) "FALSE" else "TRUE")
    ),
    sprintf('export RUN_REAL=%s', shell_quote(if (is_spatial) "FALSE" else "TRUE")),
    sprintf('export RUN_MIPS=%s', shell_quote(if (run_mips) "TRUE" else "FALSE")),
    sprintf('export RUN_SPATIAL=%s', shell_quote(if (is_spatial) "TRUE" else "FALSE")),
    sprintf('export MIPS_DATASETS=%s', shell_quote(mips_datasets)),
    sprintf('export SPATIAL_DATASETS=%s', shell_quote(spatial_datasets)),
    sprintf(
      'export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out/%s/%s/${SLURM_JOB_ID:-manual}_$(date +%%Y%%m%%d_%%H%%M%%S)"',
      backend, spec$label
    ),
    sprintf('export SINGULARITY_GPU_FLAG=%s', shell_quote(if (is_cpu) "" else "--nv")),
    'export SINGULARITY_IMAGE',
    'exec bash "${SUITE_ROOT}/common/run_one_method.sh"'
  )
  write_executable(file.path(directory, filename), lines)
}

for (backend in c("cpu", "cuda")) {
  methods <- if (identical(backend, "cpu")) cpu_tuning_methods else cuda_tuning_methods
  for (method in methods) {
    for (metric in metrics) write_calibration(backend, method, metric, "real")
    write_calibration(backend, method, "inner_product", "mips")
  }
}

for (i in seq_len(nrow(cpu_specs))) {
  for (metric in cpu_specs$metrics[[i]]) {
    write_held_out("cpu", cpu_specs[i, , drop = FALSE], metric)
  }
}
for (i in seq_len(nrow(cuda_specs))) {
  for (metric in cuda_specs$metrics[[i]]) {
    write_held_out("cuda", cuda_specs[i, , drop = FALSE], metric)
  }
}

write_real_reference <- function(metric) {
  write_executable(
    file.path(
      campaign_dir, "references",
      sprintf("run_real_references_cuda_%s.sh", metric)
    ),
    c(
      slurm_header(
        "cuda",
        sprintf("frJ_ref_%s", substr(metric, 1L, 5L)),
        sprintf("frJ_reference_real_cuda_%s", metric)
      ),
      common_environment,
      'COMMON_DIR="${SUITE_ROOT}/common"',
      'DATA_ROOT="${BASE_DIR}/Data"',
      'REAL_MANIFEST="${DATA_ROOT}/float32_dataset_manifest_jmlr.csv"',
      sprintf('METRIC=%s', shell_quote(metric)),
      sprintf('DATASETS=%s', shell_quote(real_datasets)),
      'OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/references/real_${METRIC}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
      'SEEDS="${SEEDS:-4,20260706,20260807}"',
      'mkdir -p "${OUT_DIR}"',
      'run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }',
      'run_r -e \'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); library(faissR); stopifnot(faissR::cuda_available(), faissR::faiss_gpu_available()); cat("CUDA exact-reference preflight OK: ", installed, "\\n", sep = "")\'',
      'if [[ ! -f "${REAL_MANIFEST}" ]]; then',
      '  run_r "${COMMON_DIR}/make_hpc_float32_manifest.R" --data_root="${DATA_ROOT}" --out="${REAL_MANIFEST}"',
      'fi',
      'run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \\',
      '  --manifest="${REAL_MANIFEST}" --out_dir="${OUT_DIR}" \\',
      '  --datasets="${DATASETS}" --metrics="${METRIC}" --seeds="${SEEDS}" \\',
      '  --reference_k=100 --quality_n=1024 --audit_n=64 \\',
      '  --audit_max_ops=5e9 --audit_atol=1e-5 --audit_rtol=1e-4 \\',
      '  --threads=2 --timeout=2000 --resume=TRUE'
    )
  )
}
for (metric in metrics) write_real_reference(metric)

write_executable(
  file.path(campaign_dir, "references", "run_synthetic_references_cuda.sh"),
  c(
    slurm_header(
      "cuda", "frJ_ref_synth", "frJ_reference_synthetic_cuda"
    ),
    common_environment,
    'COMMON_DIR="${SUITE_ROOT}/common"',
    'SYNTH_DIR="${BASE_DIR}/Data/JMLR_synthetic_MIPS"',
    'SYNTH_MANIFEST="${SYNTH_DIR}/jmlr_synthetic_mips_manifest.csv"',
    'OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/references/synthetic_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
    'SEEDS="${SEEDS:-4,20260706,20260807}"',
    'mkdir -p "${OUT_DIR}" "${SYNTH_DIR}"',
    'run_r() { singularity exec --nv --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }',
    'run_r -e \'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); library(faissR); stopifnot(faissR::cuda_available()); cat("CUDA reference preflight OK: ", installed, "\\n", sep = "")\'',
    'if [[ ! -f "${SYNTH_MANIFEST}" ]]; then',
    '  run_r "${COMMON_DIR}/make_jmlr_synthetic_mips_manifest.R" --out_dir="${SYNTH_DIR}" --manifest="${SYNTH_MANIFEST}"',
    'fi',
    'run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \\',
    '  --manifest="${SYNTH_MANIFEST}" --out_dir="${OUT_DIR}/mips" \\',
    sprintf('  --datasets=%s \\', shell_quote(mips_datasets)),
    '  --metrics=inner_product --seeds="${SEEDS}" --reference_k=100 \\',
    '  --quality_n=1024 --audit_n=64 --audit_max_ops=5e9 \\',
    '  --audit_atol=1e-5 --audit_rtol=1e-4 --threads=2 --timeout=2000 --resume=TRUE',
    'run_r "${COMMON_DIR}/benchmark_precompute_exact_references_cuda.R" \\',
    '  --manifest="${SYNTH_MANIFEST}" --out_dir="${OUT_DIR}/spatial" \\',
    sprintf('  --datasets=%s \\', shell_quote(spatial_datasets)),
    '  --metrics=euclidean --seeds="${SEEDS}" --reference_k=100 \\',
    '  --quality_n=1024 --audit_n=64 --audit_max_ops=5e9 \\',
    '  --audit_atol=1e-5 --audit_rtol=1e-4 --threads=2 --timeout=2000 --resume=TRUE'
  )
)

reusable_specs <- data.frame(
  route = c(
    "RcppAnnoy_euclidean",
    rep(
      c(
        "BiocNeighbors_exhaustive",
        "BiocNeighbors_hnsw",
        "BiocNeighbors_annoy"
      ),
      each = 2L
    )
  ),
  metric = c("euclidean", rep(c("euclidean", "cosine"), 3L)),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(reusable_specs))) {
  route <- reusable_specs$route[[i]]
  metric <- reusable_specs$metric[[i]]
  write_executable(
    file.path(
      campaign_dir, "reusable_external",
      sprintf("run_%s_cpu12_%s.sh", route, metric)
    ),
    c(
      slurm_header(
        "cpu",
        sprintf("frJ_w_%s_%s", substr(route, 1L, 7L), substr(metric, 1L, 4L)),
        sprintf("frJ_reusable_%s_cpu12_%s", route, metric)
      ),
      common_environment,
      'MANIFEST="${BASE_DIR}/Data/float32_dataset_manifest_jmlr.csv"',
      sprintf('ROUTE=%s', shell_quote(route)),
      sprintf('METRIC=%s', shell_quote(metric)),
      sprintf('DATASETS=%s', shell_quote(real_datasets)),
      'OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/reusable_external/${ROUTE}_${METRIC}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
      'mkdir -p "${OUT_DIR}"',
      'singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript -e \'expected <- Sys.getenv("EXPECTED_FAISSR_VERSION"); installed <- as.character(utils::packageVersion("faissR")); if (!identical(installed, expected)) stop("Frozen campaign requires faissR ", expected, ", but the Singularity image contains ", installed); cat("faissR reusable-index preflight OK: ", installed, "\\n", sep = "")\'',
      'singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript \\',
      '  "${SUITE_ROOT}/common/benchmark_reusable_external_indexes.R" \\',
      '  --manifest="${MANIFEST}" --out_dir="${OUT_DIR}" \\',
      '  --route="${ROUTE}" --metric="${METRIC}" --datasets="${DATASETS}" \\',
      '  --k_values=15,30,50,100 --seeds=20260706,20260807 \\',
      '  --threads=12 --repeats=3 --timeout=2000 \\',
      '  --quality_n=1024 --reference_k=100'
    )
  )
}

write_lowdim_ablation <- function(backend) {
  is_cpu <- identical(backend, "cpu")
  suffix <- if (is_cpu) "cpu12" else "cuda"
  write_executable(
    file.path(
      campaign_dir, "ablations",
      sprintf("run_lowdim_systems_ablations_%s.sh", suffix)
    ),
    c(
      slurm_header(
        backend,
        sprintf("frJ_abl_low_%s", if (is_cpu) "cpu" else "gpu"),
        sprintf("frJ_ablation_lowdim_%s", suffix)
      ),
      common_environment,
      'export DATASETS="flow18,mass41"',
      sprintf(
        'export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/ablations/%s/${SLURM_JOB_ID:-manual}_$(date +%%Y%%m%%d_%%H%%M%%S)"',
        backend
      ),
      sprintf(
        'exec bash "${SUITE_ROOT}/ablations/run_systems_ablations_%s.sh"',
        suffix
      )
    )
  )
}
write_lowdim_ablation("cpu")
write_lowdim_ablation("cuda")

write_analysis <- function(filename, job_name, log_stem, commands) {
  write_executable(
    file.path(campaign_dir, "analysis", filename),
    c(
      slurm_header("cpu", job_name, log_stem),
      common_environment,
      'run_r() { singularity exec --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }',
      commands
    )
  )
}

write_analysis(
  "run_calibration_audit_cpu12.sh",
  "frJ_cal_audit",
  "frJ_calibration_audit_cpu12",
  c(
    'ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/calibration"',
    'OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/calibration_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
    'mkdir -p "${OUT}/real" "${OUT}/mips"',
    'run_r "${SUITE_ROOT}/analysis/aggregate_calibration_results.R" \\',
    '  --calibration_root="${ROOT}/real" --out_dir="${OUT}/real" \\',
    sprintf('  --datasets=%s \\', shell_quote(real_datasets)),
    '  --metrics=euclidean,cosine,correlation,inner_product \\',
    '  --k_values=15,30,50,100 --target_recalls=0.9,0.95,0.99',
    'run_r "${SUITE_ROOT}/analysis/aggregate_calibration_results.R" \\',
    '  --calibration_root="${ROOT}/mips" --out_dir="${OUT}/mips" \\',
    sprintf('  --datasets=%s \\', shell_quote(mips_datasets)),
    '  --metrics=inner_product --k_values=15,30,50,100 \\',
    '  --target_recalls=0.9,0.95,0.99'
  )
)

write_analysis(
  "run_ablation_audit_cpu12.sh",
  "frJ_abl_audit",
  "frJ_ablation_audit_cpu12",
  c(
    'ROOT="${BASE_DIR}/faissR_JMLR_MLOSS"',
    'OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/ablations_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
    'mkdir -p "${OUT}"',
    'run_r "${SUITE_ROOT}/analysis/aggregate_systems_ablations.R" \\',
    '  --ablations_root="${ROOT}" --out_dir="${OUT}" \\',
    '  --datasets=COIL20,MNIST,flow18,mass41'
  )
)

write_heldout_analysis <- function(backend) {
  write_executable(
    file.path(
      campaign_dir, "analysis",
      sprintf("run_held_out_analysis_%s.sh", if (backend == "cpu") "cpu12" else "cuda")
    ),
    c(
      slurm_header(
        backend,
        sprintf("frJ_final_%s", if (backend == "cpu") "cpu" else "gpu"),
        sprintf("frJ_final_analysis_%s", if (backend == "cpu") "cpu12" else "cuda")
      ),
      common_environment,
      sprintf('BACKEND=%s', shell_quote(backend)),
      'ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out/${BACKEND}"',
      'OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/held_out_${BACKEND}_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
      'AGG="${OUT}/real"',
      'MIPS="${OUT}/mips"',
      'mkdir -p "${AGG}" "${MIPS}"',
      sprintf(
        'run_r() { singularity exec %s --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript "$@"; }',
        if (backend == "cuda") "--nv" else ""
      ),
      'run_r "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \\',
      '  --results_root="${ROOT}" --out_dir="${AGG}" --backend="${BACKEND}" \\',
      sprintf('  --datasets=%s \\', shell_quote(real_datasets)),
      '  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3',
      'run_r "${SUITE_ROOT}/analysis/aggregate_publication_results.R" \\',
      '  --results_root="${ROOT}" --out_dir="${MIPS}" --backend="${BACKEND}" \\',
      sprintf('  --datasets=%s \\', shell_quote(mips_datasets)),
      '  --target_recalls=0.9,0.95,0.99 --expected_seeds=2 --expected_repeats=3',
      'run_r "${SUITE_ROOT}/analysis/analyze_leave_one_dataset_out.R" \\',
      '  --analysis_dir="${AGG}" --out_dir="${OUT}/leave_one_dataset_out"',
      'run_r "${SUITE_ROOT}/analysis/build_publication_figures.R" \\',
      '  --analysis_dir="${AGG}" --out_dir="${OUT}/figures" --backend="${BACKEND}"'
    )
  )
}
write_heldout_analysis("cpu")
write_heldout_analysis("cuda")

write_delegate <- function(backend, filename, job_name, log_stem, target, root_kind) {
  suffix <- if (backend == "cpu") "cpu12" else "cuda"
  write_executable(
    file.path(campaign_dir, "analysis", filename),
    c(
      slurm_header(backend, job_name, log_stem),
      common_environment,
      sprintf(
        'export OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/%s/%s_${SLURM_JOB_ID:-manual}_$(date +%%Y%%m%%d_%%H%%M%%S)"',
        root_kind, backend
      ),
      if (identical(root_kind, "freeze")) {
        sprintf(
          'export RESULTS_ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/held_out/%s"',
          backend
        )
      } else {
        character()
      },
      'export SINGULARITY_IMAGE',
      sprintf('exec bash "${SUITE_ROOT}/%s"', target)
    )
  )
}

write_delegate(
  "cpu", "run_metric_conformance_cpu12.sh", "frJ_metric_final_cpu",
  "frJ_metric_final_cpu12",
  "reviewer_response/run_metric_conformance_cpu12.sh", "metric_conformance"
)
write_delegate(
  "cuda", "run_metric_conformance_cuda.sh", "frJ_metric_final_gpu",
  "frJ_metric_final_cuda",
  "reviewer_response/run_metric_conformance_cuda.sh", "metric_conformance"
)
write_delegate(
  "cpu", "run_freeze_audit_cpu12.sh", "frJ_freeze_final_cpu",
  "frJ_freeze_final_cpu12",
  "reviewer_response/run_freeze_audit_cpu12.sh", "freeze"
)
write_delegate(
  "cuda", "run_freeze_audit_cuda.sh", "frJ_freeze_final_gpu",
  "frJ_freeze_final_cuda",
  "reviewer_response/run_freeze_audit_cuda.sh", "freeze"
)

write_package_qa <- function(backend) {
  is_cpu <- identical(backend, "cpu")
  suffix <- if (is_cpu) "cpu12" else "cuda"
  write_executable(
    file.path(campaign_dir, "qa", sprintf("run_package_route_qa_%s.sh", suffix)),
    c(
      slurm_header(
        backend,
        sprintf("frJ_qa_%s", if (is_cpu) "cpu" else "gpu"),
        sprintf("frJ_package_route_qa_%s", suffix)
      ),
      common_environment,
      sprintf(
        'OUT_DIR="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/qa/%s_${SLURM_JOB_ID:-manual}_$(date +%%Y%%m%%d_%%H%%M%%S)"',
        backend
      ),
      'mkdir -p "${OUT_DIR}"',
      sprintf(
        'singularity exec %s --bind "${BASE_DIR}:${BASE_DIR}" "${SINGULARITY_IMAGE}" Rscript \\',
        if (is_cpu) "" else "--nv"
      ),
      '  "${SUITE_ROOT}/common/benchmark_package_route_qa.R" \\',
      sprintf('  --backend=%s --out_dir="${OUT_DIR}"', backend)
    )
  )
}
write_package_qa("cpu")
write_package_qa("cuda")

write_analysis(
  "run_reusable_external_audit_cpu12.sh",
  "frJ_warm_audit",
  "frJ_reusable_external_audit_cpu12",
  c(
    'ROOT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/reusable_external"',
    'OUT="${BASE_DIR}/faissR_JMLR_MLOSS/final_campaign/analysis/reusable_external_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d_%H%M%S)"',
    'mkdir -p "${OUT}"',
    'run_r "${SUITE_ROOT}/analysis/aggregate_reusable_external_indexes.R" \\',
    '  --results_root="${ROOT}" --out_dir="${OUT}"'
  )
)

readme <- c(
  "# Final JSS HPC campaign",
  "",
  "This directory contains separate Slurm launchers. Do not submit the whole",
  "tree blindly. Each `.sh` file is an independent job with the established",
  "CPU or CUDA header.",
  "",
  "## Fixed campaign",
  "",
  paste0("- Real datasets: `", gsub(",", "`, `", real_datasets), "`."),
  "- TabulaMuris is excluded from the manuscript campaign.",
  "- Metrics: Euclidean, cosine, correlation, and inner product where supported.",
  "- k: 15, 30, 50, and 100.",
  "- Recall targets: 0.90, 0.95, and 0.99.",
  "- Calibration seed: 4. Held-out seeds: 20260706 and 20260807.",
  "- Three held-out timing repetitions; 2000-second timeout.",
  "- Input manifests point to float32 datasets.",
  "- Generated calibration, reference, held-out, and reusable-index computation",
  "  launchers require the exact faissR version read from `DESCRIPTION` and stop",
  "  before loading data if the Singularity image contains another version.",
  "- The frozen image must contain `Rnanoflann`, `RANN`, `RcppAnnoy`,",
  "  `rnndescent`, `BiocNeighbors`, `FNN`, `nabor`, and `uwot`; each external",
  "  CPU launcher fails during preflight when its required package is absent.",
  "- `cuda.ml` is an API-audit row, not a timed self-KNN comparator, because",
  "  its public interface returns supervised prediction models.",
  "",
  "## Required order",
  "",
  "1. Submit the four metric-separated real reference launchers and",
  "   `references/run_synthetic_references_cuda.sh`.",
  "2. Submit every required launcher under `calibration/real/` and",
  "   `calibration/mips/`.",
  "3. Submit `analysis/run_calibration_audit_cpu12.sh` and inspect missing",
  "   cells and negative evidence.",
  "4. Update and freeze the compiled C++ tuning policies from calibration only,",
  "   commit faissR, and rebuild the Singularity image.",
  "5. Submit each launcher under `held_out/cpu/` and `held_out/cuda/`.",
  "6. Submit the reusable external-index jobs, low-dimensional ablations,",
  "   metric-conformance jobs, and CPU/CUDA package route-QA jobs.",
  "7. Submit the held-out, reusable-index, and ablation analysis jobs.",
  "8. Run the strict freeze audits with `FAISSR_PACKAGE_COMMIT` set to the",
  "   immutable commit embedded in the rebuilt image.",
  "",
  "Held-out validation must never be reused to alter tuning policies.",
  "",
  "## Typical submission",
  "",
  "```bash",
  "cd /scratch/firenze/NN",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_euclidean.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_cosine.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_correlation.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_inner_product.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_synthetic_references_cuda.sh",
  "",
  "# Submit jobs one by one, for example:",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/calibration/real/cpu/run_tune_faissR_hnsw_cpu12_euclidean_real.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/calibration/real/cuda/run_tune_faissR_cagra_cuda_euclidean_real.sh",
  "```",
  "",
  "All evidence is written below",
  "`/scratch/firenze/NN/faissR_JMLR_MLOSS/final_campaign/`."
)
writeLines(readme, file.path(campaign_dir, "README.md"), useBytes = TRUE)

requirements <- c(
  "# JSS requirement-to-script matrix",
  "",
  "This matrix is the completion contract for the publication campaign.",
  "Every computational claim maps to an R program, independent Slurm jobs,",
  "and an expected archive location. TabulaMuris is intentionally excluded.",
  "",
  "| Evidence requirement | R implementation | Slurm launchers | Output |",
  "|---|---|---|---|",
  "| Metric-matched exact references with independent CPU audit | `common/benchmark_precompute_exact_references_cuda.R` | `references/run_real_references_cuda_*.sh`, `references/run_synthetic_references_cuda.sh` | `final_campaign/references/` plus reference objects beside datasets |",
  "| Real-data calibration for every faissR method, backend, metric, k, and recall target | `common/benchmark_method_tuning_from_reference.R` | `calibration/real/{cpu,cuda}/` | `final_campaign/calibration/real/` |",
  "| Norm-stress MIPS calibration | same calibration program | `calibration/mips/{cpu,cuda}/` | `final_campaign/calibration/mips/` |",
  "| Held-out explicit-method and automatic-selection validation | `common/benchmark_jmlr_tuned_methods.R` | `held_out/{cpu,cuda}/` | `final_campaign/held_out/` |",
  "| External-package cold comparison | `common/benchmark_jmlr_tuned_methods.R` | external launchers in `held_out/cpu/` and `held_out/cuda/` | `final_campaign/held_out/` |",
  "| Public reusable-index build/query comparison | `common/benchmark_reusable_external_indexes.R` | `reusable_external/` | `final_campaign/reusable_external/` |",
  "| Float32, fitted-index, compiled self-removal, batching, and GPU-copy ablations | `common/benchmark_jss_systems_ablations.R` | `ablations/` | `final_campaign/ablations/` |",
  "| Metric and degenerate-row conformance | `common/benchmark_metric_conformance.R` | `analysis/run_metric_conformance_*.sh` | `final_campaign/analysis/metric_conformance/` |",
  "| Low-dimensional grid evidence | held-out and ablation programs | grid launchers in `held_out/` plus `ablations/` | held-out and ablation archives |",
  "| Auto-versus-oracle, completion, target attainment, and figures | `analysis/aggregate_publication_results.R`, `analysis/build_publication_figures.R` | `analysis/run_held_out_analysis_*.sh` | `final_campaign/analysis/held_out_*/` |",
  "| Leave-one-dataset-out sensitivity | `analysis/analyze_leave_one_dataset_out.R` | `analysis/run_held_out_analysis_*.sh` | `leave_one_dataset_out/` within held-out analysis |",
  "| Calibration completeness and negative evidence | `analysis/aggregate_calibration_results.R` | `analysis/run_calibration_audit_cpu12.sh` | calibration analysis archive |",
  "| Reusable-index completeness and summaries | `analysis/aggregate_reusable_external_indexes.R` | `analysis/run_reusable_external_audit_cpu12.sh` | reusable-index analysis archive |",
  "| Package route contract on installed CPU/CUDA builds | `common/benchmark_package_route_qa.R` | `qa/` | `final_campaign/qa/` |",
  "| Immutable dataset, result, software, container, and provenance freeze | `analysis/audit_publication_freeze.R` | `analysis/run_freeze_audit_*.sh` | freeze audit archives |"
)
writeLines(
  requirements,
  file.path(campaign_dir, "REQUIREMENT_MATRIX.md"),
  useBytes = TRUE
)

sbatch_commands <- function(section) {
  paths <- sort(list.files(
    file.path(campaign_dir, section),
    pattern = "[.]sh$",
    recursive = TRUE
  ))
  paste(
    "sbatch",
    file.path(
      "benchmark_scripts/jmlr_mloss_publication/final_campaign",
      section,
      paths
    )
  )
}
commands <- c(
  "# Run from /scratch/firenze/NN.",
  "# Phase 1: metric-matched real and synthetic exact references.",
  sbatch_commands("references"),
  "",
  "# Phase 2: calibration. Submit each command independently.",
  sbatch_commands("calibration/real/cpu"),
  sbatch_commands("calibration/real/cuda"),
  sbatch_commands("calibration/mips/cpu"),
  sbatch_commands("calibration/mips/cuda"),
  "",
  "# Phase 3: audit calibration, then stop and update/freeze C++ policies.",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_calibration_audit_cpu12.sh",
  "",
  "# Rebuild the Singularity image from the frozen faissR commit before phase 4.",
  "# Phase 4: held-out evidence. These rows must not tune the package.",
  sbatch_commands("held_out/cpu"),
  sbatch_commands("held_out/cuda"),
  "",
  "# Phase 5: systems and metric-contract evidence.",
  sbatch_commands("reusable_external"),
  sbatch_commands("ablations"),
  sbatch_commands("qa"),
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_metric_conformance_cpu12.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_metric_conformance_cuda.sh",
  "",
  "# Phase 6: aggregate evidence.",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_held_out_analysis_cpu12.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_held_out_analysis_cuda.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_ablation_audit_cpu12.sh",
  "sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_reusable_external_audit_cpu12.sh",
  "",
  "# Phase 7: immutable freeze. Export the tested commit first.",
  "# export FAISSR_PACKAGE_COMMIT=<40-character-git-commit>",
  "sbatch --export=ALL,FAISSR_PACKAGE_COMMIT=\"${FAISSR_PACKAGE_COMMIT}\" benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_freeze_audit_cpu12.sh",
  "sbatch --export=ALL,FAISSR_PACKAGE_COMMIT=\"${FAISSR_PACKAGE_COMMIT}\" benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_freeze_audit_cuda.sh"
)
writeLines(
  commands,
  file.path(campaign_dir, "submission_commands.txt"),
  useBytes = TRUE
)

launchers <- list.files(campaign_dir, pattern = "[.]sh$", recursive = TRUE)
launcher_paths <- file.path(campaign_dir, launchers)
manifest <- data.frame(
  launcher = launchers,
  md5 = unname(tools::md5sum(launcher_paths)),
  sha256 = vapply(launcher_paths, sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
write.csv(manifest, file.path(campaign_dir, "launcher_manifest.csv"), row.names = FALSE)

suite_root <- dirname(campaign_dir)
source_paths <- list.files(
  suite_root,
  pattern = "[.](R|sh)$",
  recursive = TRUE,
  full.names = TRUE
)
source_manifest <- data.frame(
  source = substring(source_paths, nchar(suite_root) + 2L),
  md5 = unname(tools::md5sum(source_paths)),
  sha256 = vapply(source_paths, sha256_file, character(1L)),
  bytes = unname(file.info(source_paths)$size),
  stringsAsFactors = FALSE
)
write.csv(
  source_manifest,
  file.path(campaign_dir, "campaign_source_manifest.csv"),
  row.names = FALSE
)
cat("Generated ", nrow(manifest), " independent Slurm launchers in ",
    campaign_dir, "\n", sep = "")
