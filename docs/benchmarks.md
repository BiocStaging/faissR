# Benchmarks

[Home](../README.md) |
[Installation](installation.md) |
[Implementation](implementation.md) |
[Examples](examples.md) |
**Benchmarks** |
[Autotuning](autotuning.md) |
[API](usage-api.md) |
[NN Methods](nn-methods.md) |
[Backends](backend-capabilities.md) |
[References](references.md)

`faissR` benchmarks should separate vector-search quality from downstream
embedding or clustering quality.

## Recommended Measurements

For every KNN method record:

- dataset name, `n`, `p`, metric, and `k`;
- backend requested and backend used;
- build time, query time, and total time;
- host out-of-memory outcomes and GPU memory where measurable; quantitative
  host peak-memory summaries require a fresh process dedicated to one measured
  cell;
- recall@k against an exact reference on a reproducible subset;
- mean distance error and neighbour-rank agreement;
- downstream sanity checks such as openTSNE/UMAP plots when KNN is used for
  embeddings.

For target attainment, approximate routes use a one-sided 95% lower confidence
bound for mean tie-aware query recall@k, based on 1,000 deterministic
query-bootstrap resamples. Strictly closer neighbors must match by identifier;
exact rescoring can credit an equivalent candidate at a tied kth-distance
boundary. A cell reaches `target_recall = tau` only when the lower bound is at
least `tau` for every independent validation query seed and all required seeds
complete successfully. Timing repeats reuse the seed's queries and measure
runtime only; they are collapsed within seed for recall inference. Raw
identifier overlap, point tie-aware recall, minimum query recall, and boundary
substitution frequency are reported separately as diagnostics. Shape-group
calibration additionally requires the condition for every represented dataset.

Exact-family routes are not classified by the ANN target-attainment rule.
They are `exact-audited` when the exhaustive route and reference audit pass.
The tie-aware audit accepts either the same neighbor identifiers or the same
sorted distance multiset within `atol = 1e-5` and `rtol = 1e-4`; this permits
different valid identifiers at a tied kth-neighbor boundary. Raw set overlap
remains a diagnostic. Selection and empirical-oracle eligibility therefore
means `exact_audited || approximate_target_met`, never set-overlap attainment
alone.

The benchmark scripts default to the real datasets `COIL20`, `USPS`,
`FashionMNIST`, `FlowRepository_FR-FCM-ZYRM_files`, `flow18`, `MNIST`,
`imagenet`, `MetRef`, and `mass41` from the configured `Data` directory.
NN metric benchmarks also include simulated uniform 2D and 3D datasets by
default. Graph-clustering benchmarks include those uniform datasets plus a
small labelled simulated three-cluster dataset for ARI sanity checks; the
k-means benchmark also includes that labelled three-cluster dataset.

## Fair CPU And CUDA Runs

Use fixed CPU thread counts when comparing CPU algorithms:

```r
Sys.setenv(
  OMP_NUM_THREADS = "4",
  OPENBLAS_NUM_THREADS = "4",
  MKL_NUM_THREADS = "4"
)
```

For CUDA benchmarks, report the GPU model, driver, CUDA version, FAISS build,
and cuVS version [1-3,13-15]. Explicit CUDA failures should be recorded as
failures, not silently replaced with CPU timings.

## Reuse KNN

Large benchmarks should save KNN output once:

```r
knn <- nn(x, k = 100, backend = "auto", metric = "euclidean", n_threads = 4)
saveRDS(knn, "knn_k100.rds")
```

The same object can then feed classifier tests, embedding
pipelines, and recall diagnostics without paying the KNN cost repeatedly.

## Dedicated Method Tuning Sweeps

The HPC tuning scripts are separate from Benchmark #1. They are used to choose
method-specific `tuning = "auto"` defaults rather than to produce a single
leaderboard. Each tuning run uses one explicit method and one explicit backend,
float32 dataset files, Euclidean distance, `k = 15, 30, 50, 100`, target recall
tiers `0.90`, `0.95`, and `0.99`, and a 2000-second timeout per candidate.
CPU and CUDA are run separately; `backend = "auto"` is intentionally avoided so
the resulting tables can define CPU and CUDA policies independently.

Run the exact-reference job once before the method sweeps:

```bash
benchmark_scripts/run_hpc_precompute_exact_references_cpu12.sh
```

Then run the method-specific CPU or CUDA launcher, for example:

```bash
benchmark_scripts/run_hpc_hnsw_tuning_cpu12.sh
benchmark_scripts/run_hpc_hnsw_tuning_cuda.sh
benchmark_scripts/run_hpc_cagra_tuning_cuda.sh
benchmark_scripts/run_hpc_ivfpq_fastscan_tuning_cpu12.sh
```

Metric-specific CAGRA wrappers submit one metric at a time. For example,
`benchmark_scripts/run_hpc_cagra_tuning_cuda_correlation.sh` runs
`backend = "cuda"`, `method = "cagra"`, `metric = "correlation"` on the
float32 datasets and writes rows that can replace the current validation-pending
seed table
`benchmark_scripts/cuda_cagra_correlation_shape_tuning_defaults_from_seeded_euclidean_results.csv`.

Each method writes candidate grids, raw results, target-recall recommendations,
shape summaries, and a Markdown report. The recommendation table selects the
fastest successful parameter setting that reaches the requested recall target;
when no candidate reaches the target, it keeps the best-recall row and marks
the recommendation as below target. The shape summaries are the evidence used
to update C++ rules such as HNSW `M`/`efSearch`, IVF `nprobe`, CAGRA graph
degree/search width, NN-descent candidate breadth, and NSG/Vamana pruning
settings. See [Autotuning](autotuning.md) for the full explanation of how these
tables are converted into deterministic package defaults.

Uploaded Euclidean tuning results are consolidated into two review artifacts:
`benchmark_scripts/euclidean_tuning_settings_from_uploaded_results.csv` keeps
dataset-level fastest settings, while
`benchmark_scripts/euclidean_shape_tuning_defaults_from_uploaded_results.csv`
aggregates those settings by method, backend, dataset shape, `k`, and target
recall. The package embeds the shape-level approximate-method defaults in
`src/nn_hpc_tuning_tables.hpp` so `tuning = "auto"` can choose deterministic
C++ parameters without running a pilot benchmark during ordinary `nn()` calls.
Exact, Flat, and brute-force rows remain in the tuning artifacts for provider,
thread, batch, float32, and reuse decisions, but they do not need approximate
recall-target parameters.
Metric-specific artifacts extend the same process when enough data are
available. For example,
`benchmark_scripts/correlation_hnsw_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 correlation HNSW sweep and feeds the compiled correlation
HNSW `tuning = "auto"` table. Correlation HNSW uses centered and normalized
vectors before FAISS HNSW search, so its best `M`, `efConstruction`, and
`efSearch` values are stored separately from Euclidean and cosine. The
small-n/k=15/0.99 row is marked below target because the best concrete manual
candidate did not reach 0.99 minimum recall across all small-n datasets.
summarizes the CPU12 FAISS HNSW IP sweep from
`M`, `efConstruction`, and `efSearch` by shape group, `k` bucket, and target
targets, are marked `best_recall_below_target`; those rows are still exposed
as the best tested defaults, but result metadata reports
`tuning_benchmark_target_met = FALSE`.
For IVF correlation search,
`benchmark_scripts/correlation_ivf_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 correlation IVF sweep and feeds the compiled correlation
IVF `tuning = "auto"` table. The table stores `nlist` and `nprobe` by shape
group, `k` bucket, and target recall. Rows with ImageNet missing successful
CPU IVF correlation candidates or with small-n shape-scaled candidates are
kept as `best_available_partial_shape_datasets`, so result metadata reports
`tuning_benchmark_target_met = FALSE` for those partial rows.
summarizes the CPU12 FAISS IVF IP sweep from
`nlist` and `nprobe` by shape group, `k` bucket, and target recall. Rows with
ImageNet missing successful CPU IVF IP candidates, small-n partial coverage, or
large low-dimensional candidates below the requested recall are still exposed as
the best tested defaults, but result metadata reports
`tuning_benchmark_target_met = FALSE`.
currently seeds FAISS GPU IVF IP `nlist`/`nprobe` settings from the measured
CUDA IVF Euclidean sweep. These rows are validation-pending and report
`tuning_benchmark_target_met = FALSE` until
measured metric-specific summary replaces the seed table.
summarizes the CPU12 FAISS IVFPQ IP sweep from
`nlist`, `nprobe`, `pq_m`, and `pq_nbits` by shape group, `k` bucket, and target
recall. Because product quantization frequently did not reach the requested
marked `target_not_reached_best_available` or
`best_available_partial_shape_datasets`; result metadata reports
`tuning_benchmark_target_met = FALSE` for those rows.
currently stores seeded CPU defaults from the validated Euclidean FastScan
shape/k/target table. The uploaded
before backend execution because the old package rejected CPU FastScan raw
FAISS, the seeded rows deliberately report `tuning_benchmark_target_met = FALSE`
transform before direct cuVS 4-bit IVF-PQ search. Its validation-pending seed
defaults are stored in
and should be replaced by running
`benchmark_scripts/cosine_nndescent_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 cosine NN-descent sweep and feeds the compiled cosine
NN-descent `tuning = "auto"` table. This matters because cosine search is
implemented through normalized Euclidean NN-descent, but the best candidate
pool and iteration settings can differ from raw Euclidean search.
`benchmark_scripts/correlation_nndescent_shape_tuning_defaults_from_uploaded_results.csv`
does the same for the CPU12 correlation NN-descent sweep, where rows are
centered and normalized before Euclidean graph search but keep a
correlation-specific tuning table.
auto selector uses these rows for `backend = "cpu"`, `method = "nndescent"`,
candidate breadth, and random-projection count by shape, `k`, and target
recall. Rows that did not reach the requested target across every dataset in a
shape are preserved as best-available rows and report
`tuning_benchmark_target_met = FALSE`.
Likewise, `benchmark_scripts/cosine_nsg_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 cosine NSG sweep and feeds the compiled cosine NSG
`tuning = "auto"` table; large-low-dimensional rows are marked as partial
coverage when FlowRepository did not complete trusted rows.
`benchmark_scripts/correlation_nsg_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 correlation NSG sweep in the same way; correlation rows
are centered and normalized before Euclidean NSG refinement and keep their own
shape/k/target table.
`benchmark_scripts/cuda_nsg_correlation_shape_tuning_defaults_from_seeded_cosine_results.csv`
records the current CUDA correlation NSG defaults, seeded from the measured CUDA
cosine NSG sweep until the dedicated CUDA correlation run replaces them; these
rows report `tuning_benchmark_target_met = FALSE`.
recommendations.
Rows marked `best_available_all_shape_datasets` or
`best_available_partial_shape_datasets` are exposed as best-available settings
and report `tuning_benchmark_target_met = FALSE` rather than claiming that the
target recall was verified.
The same pattern is used for
`benchmark_scripts/cosine_vamana_shape_tuning_defaults_from_uploaded_results.csv`,
which summarizes CPU12 cosine Vamana `r`, `search_l`, and `alpha` settings for
the compiled Vamana `tuning = "auto"` table.
`benchmark_scripts/correlation_vamana_shape_tuning_defaults_from_uploaded_results.csv`
summarizes the CPU12 correlation Vamana sweep in the same way; correlation rows
are centered and normalized before Euclidean Vamana refinement and keep their
own shape/k/target table.
`benchmark_scripts/cuda_vamana_correlation_shape_tuning_defaults_from_seeded_cosine_results.csv`
records the current CUDA correlation Vamana defaults, seeded from the measured
CUDA cosine Vamana sweep until the dedicated CUDA correlation run replaces
them; these rows report `tuning_benchmark_target_met = FALSE`.
recommendations.
the compiled CPU Vamana `tuning = "auto"` table for
or `best_available_partial_shape_datasets` report
`tuning_benchmark_target_met = FALSE`, because they are exposed as
best-available settings rather than verified target-recall hits.
For exact correlation search,
`benchmark_scripts/correlation_exact_shape_tuning_defaults_from_uploaded_results.csv`
summarizes CPU12 FAISS Flat correlation query-batch and fitted-index reuse
settings from `faissR_EXACT_TUNING_CPU12_correlation_20260701_090337`. Exact
correlation is an exhaustive route, so these rows tune memory/layout and
batching rather than approximation parameters. Publication analyses use
identifier equality or tie-aware distance-multiset equivalence for exactness;
raw set-overlap recall remains diagnostic. Partial shape coverage and the
small-n/k=15/0.99 below-target validation row are preserved in metadata.
For CUDA exact correlation search,
`benchmark_scripts/cuda_exact_correlation_shape_tuning_defaults_from_uploaded_results.csv`
summarizes FAISS GPU Flat correlation query-batch/resource settings from
`faissR_EXACT_TUNING_CUDA_correlation_20260703_023519`. These rows feed the
compiled CUDA exact `tuning = "auto"` table for `metric = "correlation"`.
Exact CUDA correlation is searched after centering and L2-normalizing float32
rows. It is classified as `exact_audited` rather than as an approximate target
hit; below-target raw-overlap validation rows are still preserved with
`tuning_benchmark_target_met = FALSE`.
currently seeds FAISS GPU Flat IP query-batch/resource settings from the
measured CUDA exact Euclidean sweep. Exact IP is an exhaustive, audited route,
but these rows are marked validation-pending with
`tuning_benchmark_target_met = FALSE` until
measured metric-specific summary replaces the seed table.
For CUDA Flat correlation search,
`benchmark_scripts/cuda_flat_correlation_shape_tuning_defaults_from_uploaded_results.csv`
summarizes FAISS GPU Flat correlation query-batch/resource settings from
`faissR_FLAT_TUNING_CUDA_correlation_20260703_062359`. These rows feed the
compiled CUDA Flat `tuning = "auto"` table for `metric = "correlation"` and
are stored in `attr(result, "flat_tuning")`; below-target validation rows are
preserved with `tuning_benchmark_target_met = FALSE`.
currently seeds FAISS GPU Flat IP query-batch/resource settings from the
measured CUDA Flat Euclidean sweep. Flat IP is an exhaustive, audited route,
but these rows are marked validation-pending with
`tuning_benchmark_target_met = FALSE` until
measured metric-specific summary replaces the seed table.
summarizes CPU12 FAISS Flat IP query-batch and fitted-index reuse settings from
is an exhaustive, audited route, so the compiled rows tune execution metadata
only; large high-dimensional and large low-dimensional rows preserve partial
shape coverage where one dataset did not complete trusted rows.
For Flat correlation search,
`benchmark_scripts/correlation_flat_shape_tuning_defaults_from_uploaded_results.csv`
summarizes CPU12 FAISS Flat correlation query-batch and fitted-index reuse
settings from `faissR_FLAT_TUNING_CPU12_correlation_20260701_090337`. The
shape-level rows are selected from successful raw candidates across the covered
datasets in each shape group; partial coverage and the small-n/k=15/0.99
below-target validation row are preserved in metadata.
summarizes CPU12 FAISS Flat IP query-batch and fitted-index reuse settings from
exact by construction, so these rows tune execution metadata only; large
high-dimensional and large low-dimensional rows preserve partial shape coverage
where one dataset did not complete trusted rows.
For bruteforce correlation search,
`benchmark_scripts/correlation_bruteforce_shape_tuning_defaults_from_uploaded_results.csv`
summarizes CPU12 FAISS Flat correlation query-batch and fitted-index reuse
settings from `faissR_BRUTEFORCE_TUNING_CPU12_correlation_20260701_090337`.
As with exact and Flat correlation, the search is exact by construction and
the tuning rows control batch/cache behavior; partial shape coverage and the
small-n/k=15/0.99 below-target validation row are preserved in metadata.
For CUDA bruteforce correlation search,
`benchmark_scripts/cuda_bruteforce_correlation_shape_tuning_defaults_from_proxy_results.csv`
summarizes the cuVS brute-force query-batch and GPU resource reuse policy for
the centered/normalized correlation transform. The first table is seeded from
the measured CUDA Euclidean cuVS brute-force sweep because the earlier uploaded
correlation run failed before reaching the backend; the metric-specific wrapper
`run_hpc_bruteforce_tuning_cuda_correlation.sh` reruns the corrected path and
can replace those proxy rows with measured correlation timings.
currently seeds cuVS brute-force query-batch and GPU resource reuse settings
from the measured CUDA Euclidean cuVS brute-force sweep. The search remains
rows are marked validation-pending with `tuning_benchmark_target_met = FALSE`
reruns the metric-specific path and replaces the seed table.
currently seeds cuVS HNSW-from-CAGRA graph-degree and `ef` settings from the
measured CUDA HNSW Euclidean sweep. The search route applies the
shape/k/target rows are marked validation-pending with
`tuning_benchmark_target_met = FALSE` until
metric-specific path and replaces the seed table.
summarizes CPU12 FAISS Flat IP query-batch and fitted-index reuse settings from
also exact by construction; large high-dimensional and large low-dimensional
rows keep their partial-coverage labels because not every large dataset
completed trusted rows in the uploaded run.

The base method-tuning launchers can rerun the refined grids across all public
metrics. Set `METRICS` if you want a subset; otherwise the default is
`euclidean,cosine,correlation`. For HPC submission, prefer the
metric-specific wrapper files when you want independent jobs and log/output
directories for each metric. The wrapper naming pattern is:

```bash
benchmark_scripts/run_hpc_<method>_tuning_<cpu12-or-cuda>_<metric>.sh
```

For example:

```bash
benchmark_scripts/run_hpc_bruteforce_tuning_cpu12_euclidean.sh
benchmark_scripts/run_hpc_bruteforce_tuning_cpu12_cosine.sh
benchmark_scripts/run_hpc_bruteforce_tuning_cpu12_correlation.sh
benchmark_scripts/run_hpc_bruteforce_tuning_cuda_euclidean.sh
benchmark_scripts/run_hpc_bruteforce_tuning_cuda_cosine.sh
benchmark_scripts/run_hpc_bruteforce_tuning_cuda_correlation.sh
```

Each wrapper has its own Slurm header, exports exactly one `METRICS` value, and
sets a metric-specific default `OUT_DIR` before executing the tested base
launcher. Because Slurm runs submitted scripts from a spool copy, the wrappers
resolve the base launcher from `SCRIPT_DIR`, then
`SLURM_SUBMIT_DIR/benchmark_scripts`, then `BASE_DIR/benchmark_scripts`, before
falling back to their own directory. When submitting from `/scratch/firenze/NN`,
this makes a wrapper such as
`/scratch/firenze/NN/benchmark_scripts/run_hpc_bruteforce_tuning_cpu12.sh`.
NN-descent has CPU metric wrappers only in this tuning cycle; CAGRA has CUDA
metric wrappers only. The exact-reference job also has one wrapper per metric,
for example
`run_hpc_precompute_exact_references_cpu12_euclidean.sh`.

Exact references are metric specific and are saved in each dataset folder as
`faissR_exact_reference_<metric>_k<K>_q<QUALITY_N>_seed<SEED>.RData`.
The command-line parser accepts only `euclidean`, `cosine`, `correlation`, and
In particular, legacy aliases are rejected before benchmark execution.
The file `benchmark_scripts/euclidean_tuning_settings_from_uploaded_results.csv`
collects the fastest Euclidean settings from the uploaded tuning results, and
`benchmark_scripts/previous_tuning_timeouts.csv` prevents the all-metric rerun
from repeating candidate/dataset/k combinations that already timed out in the
Euclidean sweeps. To disable that guard for a diagnostic rerun, submit with
`SKIP_PREVIOUS_TIMEOUTS=FALSE`.
CUDA NN-descent tuning is available through explicit metric-specific wrappers
such as `run_hpc_nndescent_tuning_cuda_correlation.sh`. The CUDA launcher still
requires `ALLOW_CUDA_NNDESCENT_TUNING=TRUE` so accidental all-metric submissions
do not start a large cuVS grid unintentionally.

## Benchmark #1

`benchmark_scripts/benchmark1_nn_speed.R` is the broad nearest-neighbour speed
benchmark that includes faissR implementation labels, external R KNN packages,
and selected KNN consumers. It defaults to `k = 5, 10, 15, 50, 100` and the
three public metrics Euclidean, cosine, and correlation.
product, so benchmark rows for these metrics are not interchangeable. Flat
rather than duplicate Flat-IP rows. Implementation-specific faissR rows,
such as FAISS GPU IVF and direct cuVS rows, are timed through faissR's internal
benchmark route so the table can distinguish FAISS GPU indexes that use NVIDIA
cuVS internally from direct RAPIDS cuVS API calls.

For Euclidean speed comparisons against external R packages, run CPU and CUDA
separately. The CPU launcher selects CPU faissR methods plus CPU external KNN
packages, including `RcppHNSW` HNSW, `FNN`
kd-tree/cover-tree/brute-force, `nabor` automatic/brute-force, and
`rnndescent` routes. The CUDA launcher selects CUDA
faissR/FAISS-GPU/cuVS methods. `cuda.ml` is retained as an explicit
non-standalone audit row because its current public KNN interface fits
supervised prediction models and does not return self-KNN index and distance
matrices. Both launchers exclude graph consumers by default so the leaderboard
compares KNN-search outputs, not downstream embedding or graph-construction
functions:

```bash
benchmark_scripts/run_benchmark1_compare_cpu_euclidean.sh
benchmark_scripts/run_benchmark1_compare_cuda_euclidean.sh
```

These external packages belong to the benchmark environment only. They are not
faissR package dependencies and are never used as hidden runtime fallbacks.
The final publication image is checked before timing: route QA records the
installed version of `faissR` and every comparator package (`float`,
`Rnanoflann`, `RANN`, `RcppAnnoy`, `RcppHNSW`, `rnndescent`,
`BiocNeighbors`, `FNN`, `nabor`, and `uwot`). The CUDA check requires all
three publication providers, CUDA, FAISS-GPU, and cuVS. It also calls
`nn_gpu()` with a `float::fl()` matrix and rejects the image unless the result
owns CUDA device pointers, reports `result_residency = "cuda"`, reports zero
device-to-host result copies, and confirms that no compatibility
double-to-float conversion occurred. Route QA uses self-query fixtures for
grid, NN-descent, NSG, and
Vamana, separate-query fixtures for methods that support them, exercises every
supported metric contract with `float::fl()` reference/query matrices, and
records capability-declared unsupported combinations explicitly rather than
treating them as execution failures. The route-QA output retains the container
SHA-256 digest. CPU route QA also executes each eligible external comparator
through its exported public API on a small deterministic fixture and verifies
output dimensions, finite sorted distances, and self-neighbor exclusion.
Packages that do not export a standalone KNN result API are recorded as
`not_public_api`; unexported namespace internals are not benchmarked.

On SLURM/HPC systems, submit the separated Euclidean comparison jobs with:

```bash
sbatch benchmark_scripts/run_hpc_benchmark1_compare_cpu12_euclidean.sh
sbatch benchmark_scripts/run_hpc_benchmark1_compare_cuda_euclidean.sh
```

Both launchers accept the same overrides as `benchmark1_nn_speed.R`; for
example:

```bash
K_VALUES=30 THREADS=12 DATA_ROOT=/scratch/firenze/NN/Data \
  benchmark_scripts/run_benchmark1_compare_cpu_euclidean.sh

K_VALUES=30 THREADS=2 DATA_ROOT=/scratch/firenze/NN/Data \
  benchmark_scripts/run_benchmark1_compare_cuda_euclidean.sh
```

The selected rows are saved in `benchmark1_methods.csv`, and the run choices
are saved in `benchmark1_config.csv`. Direct Rscript users can reproduce the
same split with `--method_group=cpu` or `--method_group=cuda`,
`--metrics=euclidean`, and `--include_non_knn=FALSE`.
The speed-only files are `benchmark1_ranked_speed_only.csv` and
`benchmark1_faissr_vs_external_speed.csv`; the latter reports the fastest
faissR method versus the fastest non-faissR package method for each
dataset/k/backend block and includes recall columns so speed can be interpreted
beside quality.
CUDA NN-descent has one Benchmark #1 row:
`faissR_cuda_cuvs_nndescent`, covering the direct RAPIDS cuVS
method because the cuVS NN-descent graph-construction API accepts one symmetric
reference and query transforms. faissR reports this combination as unsupported
rather than returning a low-recall result from an invalid symmetric transform.
Direct cuVS brute force and direct cuVS IVF/PQ rows are also benchmarked for
transform before calling the cuVS L2 kernel or index.
The file `benchmark1_runtime_capabilities.csv` records the faissR Benchmark #1
method/metric preflight table, including legacy Benchmark #1 method labels,
equivalent public `nn()` routes where available, execution backends, metric
support, `public_runtime_reason`, `runtime_available`, `runtime_reason`, and
current runtime availability notes. Runtime-unavailable faissR rows are
recorded as skipped before loading dataset matrices.
Successful faissR rows in `benchmark1_nn_speed_results.csv` also record the
result-facing backend, requested public backend/method/tuning, resolved
implementation backend, auto-selected method/device, compact
`route_parameters`, and `tuning_status`. The compact route metadata includes
deterministic no-pilot tuning flags for approximate FAISS/cuVS routes, including
HNSW, IVF, PQ/IVFPQ, CAGRA, NSG, and NN-descent, plus explicit backend/method
flags and backend/method decision reasons when those fields are attached to the
`nn()` result.

If a non-standard runtime library directory is needed, set `FAISSR_ENV_DIR`
explicitly before launch. The scripts also honor `FAISSR_CUDA_LIB_DIR` and
`CUDA_HOME` when constructing Linux `LD_LIBRARY_PATH` entries for CUDA/cuVS
benchmarks. The benchmark launchers no longer treat an unrelated active
`CONDA_PREFIX` as a FAISS runtime, which avoids accidental library-path
pollution on local machines. On Linux systems where another `libstdc++` is
loaded before RAPIDS cuVS, also set `FAISSR_LD_PRELOAD` to the FAISS runtime
`libstdc++.so.6`, or let Benchmark #1 derive that path from `FAISSR_ENV_DIR`
for its child workers. `LD_PRELOAD` must be present before each worker R process
starts; setting it after `library(faissR)` is too late for this class of dynamic
linker failure. CPU worker threads are controlled with environment variables
such as `OMP_NUM_THREADS`; the benchmark worker avoids loading optional
thread-control helper packages before FAISS/cuVS.
Benchmark #1 accepts only the canonical metric labels `euclidean`, `cosine`,
and `correlation`; aliases stop the launcher before workers are submitted.
Numeric controls that define the timing and quality
envelope, including `--threads`, `--timeout`, `--quality_n`, and
`--quality_max_ops`, are validated before workers are submitted.

The same explicit-runtime convention is used by the NN metrics, k-means, and
graph-clustering benchmark scripts. For direct single-process scripts, export
`LD_PRELOAD` in the shell before starting `Rscript` when the runtime requires a
newer C++ standard library than the system default.

The legacy Benchmark #1 summary file `benchmark1_best_by_dataset.csv` is
quality-aware: within each dataset/metric/k group it ranks successful KNN rows
by recall@k, neighbour-rank correlation, mean relative distance error, elapsed
time, and peak memory. The companion
`benchmark1_ranked_speed_quality_memory.csv` preserves the same ordering for
all successful rows. This means the "best" row is not simply the fastest row
when a slower method has better measured nearest-neighbour quality. Invalid or
non-finite distance/rank quality summaries are recorded as `NA` and therefore
do not masquerade as successful quality measurements. Its `--k_values` grid
follows the same positive-integer validation as the newer NN metric benchmark.

## NN Metric Cycles

`benchmark_scripts/benchmark_nn_metrics.R` focuses on faissR's public `nn()`
method matrix. It benchmarks `backend = "auto"`, `"cpu"`, and `"cuda"` across
the public methods, the three public metrics (`"euclidean"`, `"cosine"`,
centered cosine similarity versus raw dot product. Only the canonical metric
labels are accepted before preflight and reporting. Unknown or legacy metric
names now stop the script instead of silently falling back to
the default metric set, so command-line typos cannot contaminate timing tables.
`--k_values` must contain one or more positive integers; malformed entries stop
the script before datasets are loaded.
The public `method = "grid"` route is also recorded as an expected skip for
datasets that are not two- or three-dimensional, because that method is a
native low-dimensional spatial search route.
The public `method = "nsg"` route uses faissR's distinct NSG/MRNG-derived candidate
graph for all CPU metrics, so small datasets are tested through the same public
route instead of being skipped for linked-FAISS NSG graph-construction limits.
Large high-dimensional CPU NSG and Vamana rows use deterministic HNSW seed
neighbours before their method-specific pruning/refinement steps, which avoids
starting those explicit methods with an all-pairs exact seed on
MNIST/FashionMNIST-scale matrices while keeping the requested public method.
CPU `method = "ivfpq"` rows with fewer than 624 training rows are expected
skips, because FAISS' smallest supported 4-bit product quantizer would otherwise
train underpopulated codebooks and emit repeated warnings.
For 624-9,983 rows, CPU IVFPQ auto tuning uses 4-bit PQ instead of 8-bit PQ for
the same reason. Direct cuVS IVF-PQ follows the same small-training 4-bit rule
below 9,984 rows when the direct cuVS route is benchmarked. FAISS GPU IVFPQ is
kept as the explicit FAISS GPU implementation and may still train 8-bit
codebooks on compact datasets because that FAISS GPU index requires 8-bit PQ.
CPU IVFPQ correlation rows are promoted from
`faissR_IVFPQ_TUNING_CPU12_correlation_20260701_090337` into
`benchmark_scripts/correlation_ivfpq_shape_tuning_defaults_from_uploaded_results.csv`.
CUDA IVFPQ correlation rows are promoted from
`faissR_IVFPQ_TUNING_CUDA_correlation_20260703_095008` into
`benchmark_scripts/cuda_ivfpq_correlation_shape_tuning_defaults_from_uploaded_results.csv`.
seeded from measured CUDA Euclidean IVFPQ settings until
Those rows tune `nlist`, `nprobe`, `pq_m`, and `pq_nbits` by shape, `k`, and
target recall. Because product quantization can reduce recall substantially,
rows that did not reach the requested target are labelled
`target_not_reached_best_available_*` and return
`tuning_benchmark_target_met = FALSE`.
Unsupported method/backend/metric combinations are preflighted with
`nn_capabilities()` and the public backend resolver, then written as expected
skips. Runtime expected skips also record when a resolved route requires
unavailable FAISS, FAISS GPU, CUDA, or RAPIDS cuVS support.

The NN metric benchmark defaults to 10 repeated cycles for speed/recall
stability; `--cycles` can override this for smoke tests or longer stability
runs. The raw result table contains one row per
dataset/backend/method/metric/k/cycle combination.
`--recall_threshold` must be a numeric value between 0 and 1; invalid values
stop before the benchmark starts instead of silently changing recommendation
rules. `--threads`, `--timeout`, `--quality_n`, and `--quality_max_ops` are
also validated before datasets are loaded. `--cycles` must be positive when
supplied and otherwise defaults to 10.
`nn_metric_benchmark_config.csv` records the loaded faissR version, package
path, namespace path, and R library paths in addition to the benchmark
arguments, so reruns can verify that timings came from the intended source
install rather than an older user-library copy.
`nn_metric_cycle_summary.csv` aggregates successful rows across cycles by
dataset/backend/method/metric/k and reports success counts, median/min/max
elapsed time, recall stability, mean relative distance error, neighbour-rank
correlation, CPU thread count, preflight route, and the dominant implementation
backend. New runs also preserve the public request
stored on `nn()` results (`result_requested_backend`,
`result_requested_method`, and `result_tuning`), compact `route_parameters`
metadata from FAISS/cuVS/native result attributes, explicit
`auto_predicted_method`, `auto_predicted_device`, `auto_explicit_backend`,
`auto_explicit_method`, `auto_backend_decision`, and `auto_method_decision`
fields from no-pilot auto selection, and `tuning_status` when a backend reports
tuning. For cosine and correlation routes that search in normalized Euclidean
space, compact `route_parameters` also records the `metric_transform` and
`distance_transform` used to convert the public metric into the searched
distance.
For deterministic no-pilot routes such as FAISS CPU HNSW, the compact
parameters include `tuning_rule` and shape flags such as high-dimensional,
large-`n`, small-`k`, large-`k`, and non-Euclidean indicators, and
`tuning_status` records that rule so speed/recall summaries remain
interpretable across dataset shape, metric, and `k`.
`nn_metric_recommendations_from_cycles.csv` emits one row per
dataset/backend/metric/k. When recall is available, it selects the fastest
method whose median recall is at least the configured `recall_threshold`; if no
method reaches that threshold it selects the highest-recall row and marks
`recommendation_basis = "best_recall_below_threshold"`. Above-threshold speed
ties are broken by higher median recall, minimum recall, median minimum recall,
neighbour-rank correlation, and lower mean relative distance error;
below-threshold median-recall ties are broken by minimum recall, median minimum
recall, rank correlation, distance error, and then speed. When recall is
unavailable for the group, it selects the fastest successful row and marks
`recommendation_basis = "speed_only_no_recall"`.
`nn_metric_auto_vs_cycle_recommendation.csv` compares aggregate
`method = "auto"` rows with those recommendations and reports median speed
ratio, median recall gap, CPU thread count, preflight route,
route-parameter/tuning metadata, backend/implementation agreement, and the
recommendation basis used for the recommended row. Speed ratios and recall gaps
are `NA` when the required timing or recall values are unavailable or invalid.
`nn_metric_global_recommendations_from_cycles.csv` pools requested CPU, CUDA,
and auto backends before selecting the fastest row at the recall threshold for
each dataset/metric/k combination. `nn_metric_auto_vs_global_recommendation.csv`
compares aggregate auto rows with those global recommendations, making it the
main audit for whether no-pilot `method = "auto"` selected the fastest observed
CPU/CUDA implementation rather than only the best row in the same requested
backend group.
`nn_metric_best_by_dataset_backend_metric_k_cycle.csv` keeps the best row within
each cycle using the same recall-threshold rule: fastest above threshold,
best recall below threshold, and fastest when recall is unavailable.
`nn_metric_best_by_dataset_backend_metric_k.csv` keeps the overall best row
across cycles with the same rule for backward-compatible summaries.
`MATERIALS_AND_METHODS_nn_metrics.md` records the corresponding paper-ready
methods text, including the metric grid, k grid, recall rules, expected-skip
policy, and output-file definitions.

Example CPU-focused metric run:

```sh
Rscript benchmark_scripts/benchmark_nn_metrics.R \
  --data_root=/path/to/Data \
  --out_dir=/path/to/faissR_NN_METRICS_CPU \
  --datasets=COIL20,USPS,FashionMNIST,MNIST \
  --backends=cpu \
  --methods=auto,exact,flat,hnsw,ivf,ivfpq,nsg,nndescent \
  --metrics=euclidean,cosine,correlation \
  --k_values=5,10,15,50,100 \
  --threads=12 \
  --cycles=10
```

Example CUDA-focused metric run:

```sh
Rscript benchmark_scripts/benchmark_nn_metrics.R \
  --data_root=/path/to/Data \
  --out_dir=/path/to/faissR_NN_METRICS_CUDA \
  --datasets=COIL20,USPS,FashionMNIST,MNIST \
  --backends=cuda \
  --methods=auto,exact,flat,grid,ivf,ivfpq,nndescent,cagra \
  --cagra_implementations=faiss_gpu,cuvs \
  --metrics=euclidean,cosine,correlation \
  --k_values=5,10,15,50,100 \
  --threads=2 \
  --cycles=10
```

## NN Metrics File Layout

`benchmark_scripts/benchmark_nn_metrics.R` is a faissR-only nearest-neighbour
metric matrix. It runs public `nn()` combinations over:

- backends: `"auto"`, `"cpu"`, `"cuda"`, or any subset passed with
  `--backends`;
- methods: `"auto"`, `"exact"`, `"flat"`, `"bruteforce"`, `"grid"`,
`"hnsw"`, `"ivf"`, `"ivfpq"`, `"vamana"`, `"nsg"`,
  `"nndescent"`, and `"cagra"`; these must be canonical lowercase public
  method labels, not resolved backend labels such as `faiss_hnsw`;
- CAGRA implementations: `--cagra_implementations=auto` by default, or
  `--cagra_implementations=faiss_gpu,cuvs` to split public `method = "cagra"`
  rows into FAISS GPU CAGRA and direct RAPIDS cuVS CAGRA provider requests;
- Direct cuVS CAGRA build algorithms: `--cagra_build_algos=auto` by default,
  or `--cagra_build_algos=auto,ivf_pq,nn_descent,iterative_cagra_search` to
  audit direct cuVS CAGRA graph construction modes separately;
- metrics: `"euclidean"`, `"cosine"`, `"correlation"`, and
  reports shifted smaller-is-better distances;
- k values: `5`, `10`, `15`, `50`, and `100` by default.

Unsupported combinations are preflighted with `faissR::nn_capabilities(runtime = TRUE)` and
the public backend resolver, then saved as `status = "expected_skip"` rows with
`expected_skip = TRUE`; the raw result table also records
`expected_skip_reason` so runtime, shape, and input-type skips can be grouped
without parsing the prose error message. The run configuration is saved as
`nn_metric_benchmark_config.csv`, the raw row-level result table is saved as
`nn_metric_benchmark_results.csv`, and the runtime-aware capability table used
for the run is saved as `nn_metric_capabilities.csv`, including public
`backend = "auto"`, `"cpu"`, and `"cuda"` rows plus `resolved_backend`,
`runtime_available`, `runtime_reason`, and `runtime_notes`. Provider-specific
CAGRA preflight tables are also saved as `nn_metric_cagra_capabilities.csv`
with a `cagra_implementation` column, so FAISS GPU CAGRA and direct RAPIDS
cuVS CAGRA expected skips can be audited separately when
`--cagra_implementations=faiss_gpu,cuvs` is used. For
`backend = "auto"`, the
preflight first checks the explicit auto capability row, then checks the
resolved CPU/CUDA route and records expected skips when that route requires
unavailable FAISS, FAISS GPU, CUDA, or RAPIDS cuVS support.
The config includes `available_datasets`, the validated real plus simulated
dataset names accepted by the `--datasets` selector, which makes partial or
subset reruns traceable to the full benchmark universe. Unexpected runtime
errors remain ordinary failed rows. Recall is computed against exact
references when feasible. Small datasets use a full exact CPU self-KNN
reference; larger datasets use a deterministic CPU sample of query rows when
`quality_n * nrow(data) * ncol(data)` fits `--quality_max_ops`. When that CPU
operation cap would otherwise suppress recall but an exact CUDA route is
available, compact very high-dimensional datasets can use
`recall_reference = "full_cuda_exact"`, and sampled datasets up to the guarded
benchmark size limit can use `recall_reference = "sample_cuda_exact"`. The
`recall_reference` and `recall_query_n` columns record which exact reference
mode was used. The same exact-reference subset is also used to report
`mean_relative_distance_error` and `rank_correlation`, so recall, distance
quality, and rank agreement are evaluated on identical query rows.
The script also writes
`nn_metric_fastest_at_recall_threshold.csv`, which records the fastest
successful method per dataset/backend/metric/k whose recall is at least
`--recall_threshold` when recall is available. When `method = "auto"` is part
of the run, `nn_metric_auto_vs_fastest.csv` compares auto against that fastest
high-recall row and reports speed ratio, recall gap, whether auto itself was
the fastest high-recall method, whether the result-facing backend matches, and
whether the concrete implementation backend matches. Speed ratios and recall
gaps are `NA` when the required timing or recall values are missing or invalid.
The result table separates `result_requested_backend`,
`result_requested_method`, `result_tuning`, `result_backend`,
`resolved_backend`, and `implementation_backend` so public device labels such as
`"cuda"` can be distinguished from concrete FAISS/cuVS implementation labels
such as `"faiss_gpu_cagra"` or `"cuda_cuvs_cagra"`. The
`cagra_implementation` column records the requested provider selector for
public `method = "cagra"` rows. Public `method = "auto"` is benchmarked once
per backend/metric/k combination and records the provider selected by the
package in `resolved_backend`, `implementation_backend`, and route metadata.
This keeps auto-selection audits focused on the public auto policy while
explicit `method = "cagra"` rows compare FAISS GPU CAGRA against direct cuVS
CAGRA. Row execution uses the per-call `cagra_implementation` argument so
provider selection remains isolated across cycles, datasets, metrics, and `k`.
For stress runs that compare FAISS GPU CAGRA and direct RAPIDS cuVS CAGRA in
one benchmark matrix, `--isolate_cuda_cagra=true` runs CUDA CAGRA provider rows
inside child R processes. The parent process still builds the exact reference
and computes recall, while the raw table records `isolated_process` and
`child_status`. The elapsed method time is measured inside the child around
`faissR::nn()`, so process launch and result serialization are auditable but
not counted as NN search time. The NN metric benchmark also enables
`--isolate_native_timeout=true` by default on Unix-like systems. High-work CPU
rows for exhaustive methods (`exact`, `flat`, and `bruteforce`) and approximate
graph/index methods (`auto`, `hnsw`, `ivf`, `ivfpq`, `vamana`, `nsg`, and
`nndescent`) run inside forked workers so the benchmark can enforce an OS-level
timeout even when the underlying C++/FAISS loop does not return control to R's
`setTimeLimit()` handler. High-work CUDA/auto rows, including exhaustive
`exact`/`flat`/`bruteforce` rows and graph/index rows, run inside Rscript child
processes for the same reason. Timed-out workers are written as
`status = "timeout"` with `child_status = "timeout"` and the benchmark
continues to the next row. For very large all-method sweeps,
`--preflight_cuda_exhaustive_timeout=true` can record high-work CUDA
`exact`/`flat`/`bruteforce` rows as `status = "timeout"` with
`child_status = "preflight_timeout"` before launching native code, matching the
CPU exhaustive preflight behavior for all-pairs routes known to exceed the cap.
CUDA preflight applies a conservative minimum operation threshold of `1e14`
even when a lower command-line threshold is supplied. This keeps GPU-feasible
medium datasets such as MNIST70k in the measured rows while still avoiding
known-impractical exhaustive rows on multi-million-row datasets.
The aggregate file `nn_metric_recommendations_from_cycles.csv` emits one row
per dataset/backend/metric/k: it chooses the fastest median row above the recall
threshold when possible, the best-recall row when all measured methods are below
threshold, and the fastest successful row when recall is unavailable. Ties are
resolved deterministically with minimum-recall stability, rank agreement, and
distance error before falling back to speed for below-threshold groups. The
`recommendation_basis` column records which rule was used.
`nn_metric_auto_vs_cycle_recommendation.csv` carries this value as
`recommended_recommendation_basis` so auto comparisons can be interpreted as
recall-qualified, below-threshold, or speed-only comparisons. Cycle summaries
and auto comparisons also preserve `n_threads` and `preflight_route`, so CPU
threading and public route decisions remain auditable after aggregation.
`nn_metric_global_recommendations_from_cycles.csv` and
`nn_metric_auto_vs_global_recommendation.csv` repeat the recommendation and auto
comparison after pooling requested backends. These files expose cases where
auto is locally reasonable inside its requested backend group but a different
CPU/CUDA route is globally faster at the same recall target.

Example CPU run:

```sh
Rscript benchmark_scripts/benchmark_nn_metrics.R \
  --data_root=/path/to/Data \
  --out_dir=/path/to/faissR_NN_METRICS_CPU \
  --backends=cpu \
  --metrics=euclidean,cosine,correlation \
  --k_values=5,10,15,50,100 \
  --recall_threshold=0.98 \
  --threads=12
```

## Held-out publication evidence

`benchmark_scripts/jss_reproduction/` separates calibration, exact
reference construction, held-out CPU methods, held-out CUDA methods, systems
ablations, and cross-method analysis. Each Slurm launcher tests one method and
backend. Held-out runs use two validation seeds, three repetitions, metric-
matched exact references, and a 2,000-second per-combination timeout.
Campaign generation freezes the faissR version from `DESCRIPTION` into the
launchers. Calibration, reference, held-out, and reusable-index routes stop
before loading benchmark data when the Singularity image contains another
version, preventing a stale image from producing evidence for the wrong
package snapshot.
Stochastic external routes initialize R's RNG with the prespecified run seed,
pass explicit package seed arguments where the public API provides them, and
record `algorithm_seed` in every applicable raw row. Repeated runs are still
required because multithreaded graph construction may not be bitwise
deterministic. `uwot` and `cuda.ml` remain API-audit entries but receive no
held-out timing launcher when their public interfaces do not return standalone
self-KNN indices and distances.
RcppAnnoy is evaluated with `AnnoyEuclidean` for Euclidean search and
search. Angular distance is converted inside the timed adapter to the public
`1 - cosine` scale as `angular^2 / 2`; dot-product scores are shifted after
self removal to `row_max(score) - score`. RcppHNSW is tested with its public
Euclidean, cosine, and `ip` routes; `1 - score` from `ip` is likewise shifted
after self removal. The four rnndescent calls are tested with their public
Euclidean, cosine, and correlation metrics.

After all one-method jobs finish,
`analysis/aggregate_publication_results.R` selects the newest run for each
method/suite using the immediate timestamped output directory as the run
identity. Older reruns are not pooled with the selected run. Complete evidence
requires exactly one successful row for every expected validation-seed/repeat
pair. A method enters a speed ranking only when every prespecified replicate's
mean query-level recall@k reaches the
requested recall. The output includes fastest and second-fastest methods, an exact baseline,
cross-package winners, and `method = "auto"` versus the fastest qualifying
explicitly requested faissR method that the selector could have chosen. It also
records recall differences and resolved-provider agreement, recall-compliance counts,
failure evidence, and successful route mismatches. CPU and CUDA have separate
Slurm aggregation files and are never pooled into one ranking.
Publication timing effects are not estimated from elapsed seconds pooled over
heterogeneous datasets or parameter cells. The frozen aggregator pairs arms
within dataset, metric, `k`, target recall, backend, and validation design,
then reduces valid ratios to one median per dataset before summarizing across
datasets. It reports the median, IQR, range, expected and paired datasets and
cells, unpaired cells, timeouts, and out-of-memory events. Absolute elapsed
times remain supplementary diagnostics.
The strict freeze audit rejects dataset-fingerprint mismatches, result rows
produced by another package version, incomplete provenance, and missing or
noncanonical package/image commits. Both 40-character commits must equal the
campaign commit. Referenced exact-neighbor objects are loaded and checked under
the same rule; the container must also have a valid 64-character SHA-256 digest.

For the frozen JSS campaign,
`final_campaign/submit_campaign.R` provides a guarded, phase-aware submission
entry point. It verifies the installed package version and embedded commit,
submits each existing CPU/CUDA launcher separately, and records Slurm job IDs
in a CSV ledger. The ledger is persisted after every job, including a failed
submission row when `sbatch` stops partway through a phase, so a partial phase
can be reconciled without blindly resubmitting successful jobs. It deliberately
requires the user to advance between phases after inspecting the preceding
reports.

Before HPC submission, `jss_reproduction/sync_publication_suite.sh`
copies the complete suite to a user-supplied mirror without deleting target
files. It accepts success only when the mirror contains exactly 277 launchers,
the submitter checksum matches, and every copied shell program parses. This
prevents an older partially synchronized launcher tree from being mistaken for
the frozen campaign.

The CPU and CUDA systems-ablation jobs compare double and float32 input,
disabled and warm fitted-index/transformation caches, compiled and R-side
self-neighbour removal, and GPU-resident exact output with explicit host-copy
is not substituted with another algorithm.

Example CUDA run:

```sh
Rscript benchmark_scripts/benchmark_nn_metrics.R \
  --data_root=/path/to/Data \
  --out_dir=/path/to/faissR_NN_METRICS_CUDA \
  --backends=cuda \
  --metrics=euclidean,cosine,correlation \
  --k_values=5,10,15,50,100 \
  --recall_threshold=0.98 \
  --threads=2
```

## K-Means

`benchmark_scripts/benchmark_kmeans.R` compares `fast_kmeans()` with
`backend = "auto"`, `"cpu"`, and `"cuda"` against base `stats::kmeans` by
default. It records elapsed time, peak resident memory when available, backend
used, total within-cluster sum of squares, iterations, `converged`,
`hit_max_iter`, selected k-means
parameters, tuning policy, benchmark cycle, and ARI against `dataset$labels` when labels are
available. The result table separates `requested_backend`, `resolved_backend`,
and `backend_used`, so `"auto"` device policy and the actual implementation
(`"faiss"`, `"cpu"`, `"cuda_faiss"`, `"cuda_cuvs"`, or `"stats"`) can be
audited directly. The run configuration is saved as
`kmeans_benchmark_config.csv`, and the raw row-level result table is saved as
`kmeans_benchmark_results.csv`. The runtime preflight table is saved as
`kmeans_runtime_capabilities.csv`, including CUDA, FAISS GPU, and cuVS
availability, `runtime_reason`, human-readable `runtime_notes`, and whether
explicit CUDA k-means requests are runnable in the current build. The
`runtime_reason` field distinguishes available routes from
`missing_cuda_runtime` and `missing_gpu_kmeans_backend` preflight skips.
`--centers` must be a positive integer; when
dataset labels are available, the benchmark uses the label-derived cluster
count for that dataset and otherwise uses the validated `--centers` fallback.
The config includes `available_datasets`, the validated real plus simulated
dataset names accepted by the `--datasets` selector.
Method and backend selectors are validated before loading datasets, so typos in
`--methods` or `--backends` stop the run instead of becoming failed benchmark
rows. `--threads`, `--timeout`, and `--cycles` must be positive integers and
are also validated before data loading.
When `stats` is part of the run,
`kmeans_fast_vs_stats.csv` compares
each successful `fast_kmeans()` row against `stats::kmeans` for the same
dataset, cycle, and number of centers, reporting speedup, ARI delta, and
withinss ratio. Speedups, ARI deltas, and withinss ratios are `NA` when the
required timing or quality values are missing or invalid. The k-means benchmark
defaults to 10 repeated cycles for speed/ARI stability; `--cycles` can override
this for smoke tests or longer stability runs. `kmeans_cycle_summary.csv`
aggregates successful rows across cycles by dataset/method/backend/centers and
reports success counts, median/min/max elapsed time, ARI stability, withinss
stability, iteration counts, whether any cycle hit `max_iter`, whether all
cycles converged before the iteration cap, selected parameter medians,
deterministic tuning rule/shape metadata, resolved backend metadata, and CUDA
provider-selection metadata when CUDA k-means is used.
`kmeans_best_by_dataset.csv` keeps a compact best successful row per dataset
after ranking by ARI, elapsed time, and total within-cluster sum of squares for
backward-compatible summaries. `kmeans_best_by_dataset_centers.csv` keeps the
same best-row ranking per dataset/centers combination, which is the safer table
for comparing different requested cluster counts.
`kmeans_recommendations_from_cycles.csv` selects the fastest row within
`ari_tolerance` of the best median ARI for each dataset/centers combination;
`--ari_tolerance` must be a non-negative number and is validated before
datasets are loaded. `--cycles` must be positive when supplied and otherwise
defaults to 10.
When ARI is available and median times tie, higher median ARI, higher minimum
ARI across cycles, and then lower median total within-cluster sum of squares
break the tie. When ARI is unavailable it selects the fastest median-time row. The
`recommendation_basis` column records whether the row was selected as
`"fastest_within_ari_tolerance"` or `"speed_only_no_ari"`.
`kmeans_backend_recommendations_from_cycles.csv` applies the same rule within
each dataset/centers/backend group, so CPU, CUDA, auto, and stats results can
be tuned or reported separately without losing the overall recommendation.
`kmeans_fast_vs_cycle_recommendation.csv` compares aggregate `fast_kmeans()`
rows with those recommendations and reports median speed ratio, median ARI gap,
withinss ratio, selected tuning metadata, requested/resolved backend metadata,
CPU thread count, static no-pilot selection metadata, CUDA provider-selection
metadata, backend/implementation agreement, and the recommendation basis used
for the recommended row. Speed
ratios, ARI gaps, and withinss ratios are `NA` when the required timing or
quality values are missing or invalid.
`kmeans_auto_vs_global_recommendation.csv` compares aggregate
`fast_kmeans(backend = "auto")` rows with the pooled global recommendation for
the same dataset/centers combination and records requested-backend,
resolved-backend, implementation, timing, ARI, withinss, deterministic tuning,
and static no-pilot backend-selection agreement.
`MATERIALS_AND_METHODS_kmeans.md` records the corresponding paper-ready
methods text, including centers selection, ARI/withinss reporting, tuning
policy, expected-skip policy, and output-file definitions.
Explicit CUDA/library combinations that are known unavailable before execution
are recorded as `status = "expected_skip"` with `expected_skip = TRUE`, while
`resolved_backend` remains `"cuda"` so the skipped public device request is
auditable. The skip decision is derived from `kmeans_runtime_capabilities.csv`.
`backend = "auto"` resolves to CPU instead of becoming an expected
skip when no k-means-capable CUDA route is available, and it can also resolve
to CPU for small k-means jobs or many-cluster jobs with too few observations
per center where the deterministic shape gate estimates that GPU launch/copy
overhead would dominate. `centers = 1` is resolved to the exact CPU column-mean
solution, and `centers = nrow(data)` is resolved to the exact singleton
assignment, because no iterative CPU or CUDA k-means backend can improve either
objective. Unexpected runtime errors remain failed rows and are not replaced
with CPU timings.
The package records the same decision in
`parameters$tuning$backend_policy`, including a reason string such as
`small_cpu_preferred`, `few_points_per_center_cpu_preferred`,
`work_at_least_1e8`, `input_at_least_256MiB`, or
`large_high_dimensional_input`, plus `single_cluster_exact_mean` and
`singleton_exact_identity` for exact paths, the estimated work, ordinary R input
bytes, and float32 GPU transfer bytes. The size gate uses
`gpu_transfer_nbytes`, while `nbytes` stays available as the R double input
footprint for compatibility, plus the
deterministic threshold values (`work_threshold`, `nbytes_threshold`,
`large_n_threshold`, `large_p_threshold`, and `min_n_per_center`) used for the
CPU/CUDA decision.
Benchmark rows also record `selection_*` columns from
`parameters$tuning$selection`, including the predicted backend, backend-policy
reason, explicit-backend flag, backend decision label, runtime capability
flags, work/input-size estimates, and `selection_slow_tuning = FALSE`.
Benchmark summaries can therefore separate explicit CPU/CUDA requests from
automatic CPU/CUDA selection without running extra pilot jobs.
For CUDA k-means rows, the benchmark also records `cuda_provider_selection`,
`faiss_gpu_error`, and `backend_resolution_note` from `fast_kmeans()`. These
columns distinguish FAISS GPU k-means from direct cuVS k-means and preserve the
reason when an unavailable or failed FAISS GPU route is followed by direct cuVS
inside the CUDA backend.
For k-means parameter tuning, `tuning_rule` is a categorical no-pilot label
such as `small_low_work_multistart`, `medium_single_start`, or
`large_fast_convergence`, while `tuning_rule_detail` stores the exact
`n`/`p`/`centers`/work trace for auditing. Many-center k-means summaries also
record `tuning_small_many_centers` and `tuning_few_points_many_centers`, so
benchmark tables can distinguish stable multistart rules for well-populated
and many-center cluster requests.

Example CPU run:

```sh
Rscript benchmark_scripts/benchmark_kmeans.R \
  --data_root=/path/to/Data \
  --out_dir=/path/to/faissR_KMEANS_CPU \
  --datasets=COIL20,USPS,FashionMNIST,MNIST \
  --methods=fast_kmeans,stats \
  --backends=cpu \
  --centers=10 \
  --threads=12 \
  --cycles=10 \
  --ari_tolerance=0.01
```
