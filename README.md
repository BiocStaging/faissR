# faissR

**Home** |
[Installation](docs/installation.md) |
[Implementation](docs/implementation.md) |
[Examples](docs/examples.md) |
[Benchmarks](docs/benchmarks.md) |
[Autotuning](docs/autotuning.md) |
[API](docs/usage-api.md) |
[NN Methods](docs/nn-methods.md) |
[Backends](docs/backend-capabilities.md) |
[References](docs/references.md) |
[JSS Manuscript](manuscript/jss/README.md)

Numbered citations in this README refer to the bibliography in
[References](docs/references.md).

The reproducible source bundle for the draft Journal of Statistical Software
article is tracked under [`manuscript/jss`](manuscript/jss/README.md).
Performance rankings remain deliberately absent from the draft until the
independent held-out CPU/CUDA and external-package campaign is frozen.

`faissR` provides native nearest-neighbour search, kNN models, and k-means for
R workflows that need mandatory
[FAISS](https://faiss.ai/index.html) support and optional NVIDIA CUDA/RAPIDS
acceleration [1-3,13-16]. The package is intended for CRAN-style source
installation: FAISS is required for all builds, while CUDA and RAPIDS cuVS are
optional for CPU-only builds. A machine without CUDA can
still install the package from source and use the CPU/FAISS functionality. For
NVIDIA GPU users, the GPU stack should be requested explicitly so missing CUDA
or RAPIDS libraries are fatal rather than silently producing a CPU-only build.

`target_recall` has a precise publication-benchmark meaning. Approximate recall
is tie-aware at the kth-neighbor boundary: strictly closer reference neighbors
must match by identifier, while exactly rescored candidates can receive credit
for an equivalent boundary tie. For each independently sampled query seed, a
one-sided 95% lower confidence bound is computed from 1,000 deterministic
query-bootstrap resamples. A calibrated cell passes only when this bound is at
least `tau` for every query seed. Timing repeats reuse the same queries and
measure runtime dispersion; they are not independent recall evidence. Minimum
query recall remains a diagnostic. The argument selects a calibrated operating
point and is not a guarantee for an unseen dataset. Tuning metadata records the
statistic, confidence level, bootstrap count, and independent-seed rule.

Exact-family routes use a separate `exact-audited` classification. Their audit
accepts identical neighbor identifiers or an equivalent sorted distance
multiset within the frozen numerical tolerance, so a tied kth-neighbor boundary
does not create a false failure. Raw set overlap remains diagnostic. Benchmark
selection and the empirical oracle use `exact_audited ||
approximate_target_met` as their eligibility rule.

Post hoc candidate-set sensitivity is evaluated with cross-fitted
leave-one-dataset-out (LOODO) analysis. Every row from one named dataset is
removed before a method
family is selected from the remaining shape evidence; the choice is then
evaluated on the omitted dataset without revision. Outputs report
operating-point attainment, selected/oracle time ratio, route-family agreement,
abstention, and exact-selection frequency per held-out dataset. The installed
full-calibration `method = "auto"` result is kept in separate diagnostic
columns and is not presented as LOODO, installed-policy validation, or
out-of-collection evidence. The explicit routes used for cross-fitting do not
share the installed Flat/IVF candidate universe.

The compiled CUDA automatic policy is an optional experimental policy
calibrated on NVIDIA L40S jobs for cold full-self-search. It checks runtime
capabilities but does not retune from a
CPU/GPU model string. `attr(result, "auto_selection")$hardware_evidence` is
`"calibration_hardware_matched"` for a confirmed L40S match and
`"hardware_extrapolated_unvalidated"` for a different or unidentified
machine. In the latter case the static policy remains active and no silent
method/device fallback occurs. CUDA `method = "auto"` also emits one visible
warning per runtime GPU model when that match is not confirmed; suppress it
only after review with
`options(faissR.warn_hardware_extrapolation = FALSE)`. Request
`method = "exact"` explicitly when exhaustive search is required. The opt-in
`tuning = "pilot"` and `"cache"` modes tune parameters within an explicit or
resolved method on local data; they do not learn a new cross-method routing
policy. Full local route-policy construction is not currently a public package
feature, so the bundled CUDA selector is an L40S-informed experimental
heuristic outside the evaluated environment or workload. It is not the
package's principal contribution.

The package code does not depend on Python or conda. Conda/mamba environments
can be useful for development or benchmarking because they provide compatible
FAISS/RAPIDS libraries, but CRAN and source builds should use normal system
headers and libraries discovered by `configure`.

## Main Features

- `nn()` for native CPU references, FAISS CPU indexes, FAISS GPU indexes, and
  optional direct RAPIDS cuVS/CUDA indexes, including an IVFPQ FastScan
  `method = "ivfpq_fastscan"` route through FAISS FastScan on CPU and cuVS
  4-bit IVF-PQ on CUDA. Repeated raw CUDA FastScan calls reuse a fitted cuVS
  IVF-PQ index and cuVS resources in a bounded session cache [1-6,13-16,22-23,34].
- Optional float32 KNN data flow: `nn()` accepts
  `float::fl()` matrices. FAISS CPU/GPU and RAPIDS cuVS NN routes consume
  float32 input through direct C++ adapters, and unsupported native routes now
  fail clearly instead of silently converting benchmark input back to R double.
  `output = "float"` returns float32 distance matrices when the optional
  `float` package is installed. The float32 FAISS routes construct returned
  float distances directly instead of materializing an intermediate R double
  matrix for CPU FAISS Flat/IVF/IVFPQ/FastScan, cached CPU FAISS fitted
  indexes, FAISS GPU Flat/IVF/IVFPQ, and direct Euclidean RAPIDS cuVS routes.
  Cosine and correlation transforms are cached as row-major float32 buffers
  inside the R session, so repeated FAISS/cuVS normalized searches can
  reuse the transformed data instead of normalizing on every call. A versioned
  C-callable entry point is also registered so downstream C++ packages can
  request the same float32 KNN result format without routing through the R
  wrappers.
- GPU-resident exact KNN output for downstream CUDA consumers:
  `nn_gpu()` returns a `faissR_gpu_knn` object whose `indices_ptr` and
  `distances_ptr` remain on the CUDA device as int32 and float32 buffers.
  This is separate from `nn(..., output = "float")`, which still returns an R
  object on the host. `gpu_knn_to_host()` is the explicit diagnostic helper for
  copying a GPU-resident result back to ordinary R matrices. The registered
  C-callable `faissR_nn_cuda_tuned_gpu_call` exposes the same self-KNN route to
  downstream C/C++ packages. The GPU-resident route supports
  `method = "auto"`, `"exact"`, `"flat"`, or `"bruteforce"` with Euclidean,
  cosine, and correlation metrics. Approximate FAISS GPU/cuVS provider routes
  still return host objects until their provider result buffers are persistent.
- CUDA exact metric tuning:
  `method = "exact", backend = "cuda"` uses FAISS GPU Flat query-batch/resource
  policies for Euclidean, cosine, and correlation when
  `tuning = "auto"`. The correlation table is measured in
  `benchmark_scripts/cuda_exact_correlation_shape_tuning_defaults_from_uploaded_results.csv`.
  Exhaustive routes are classified as
  `exact_audited` after identifier or tie-aware distance-multiset validation;
  raw set-overlap recall remains diagnostic because boundary ties can select
  different but equally valid neighbours. Benchmark provenance remains visible
  through `tuning_benchmark_target_met`.
- CUDA Flat metric tuning:
  `method = "flat", backend = "cuda"` uses FAISS GPU Flat query-batch/resource
  policies for Euclidean, cosine, and correlation when
  `tuning = "auto"`. The correlation table is measured in
  `benchmark_scripts/cuda_flat_correlation_shape_tuning_defaults_from_uploaded_results.csv`.
  The selected row is stored in
  `attr(result, "flat_tuning")`.
- CUDA bruteforce metric tuning:
  `method = "bruteforce", backend = "cuda"` uses direct cuVS brute-force search
  for Euclidean and transformed exact routes for cosine and correlation. Its
  `tuning = "auto"` tables store cuVS query-batch/resource defaults by shape,
  `k`, and target recall.
- CUDA HNSW metric tuning:
  `method = "hnsw", backend = "cuda"` uses RAPIDS cuVS HNSW from a CAGRA seed
  graph. Cosine uses row-normalized float32 data and correlation uses centered,
  row-normalized float32 data. `tuning = "auto"` uses the corresponding
  Euclidean/cosine/correlation shape/k/target tables.
- CUDA IVF metric tuning:
  `method = "ivf", backend = "cuda"` resolves to FAISS GPU IVF-Flat.
  Euclidean, cosine, and correlation use measured CUDA IVF shape/k/target
  `nlist`/`nprobe` tables.
- Raw `nn()` calls reuse a bounded session-local CPU
  FAISS fitted-index cache for matching Flat, HNSW, IVF, IVFPQ, and IVFPQ
  FastScan requests.
  This avoids rebuilding FAISS indexes across repeated calls; result metadata
  reports `persistent_index_cache` and `index_cache_hit`. Use
  `options(faissR.cache_fitted_nn_indexes = FALSE)` to disable the cache or
  `faissR.cache_fitted_nn_indexes_max_entries` to bound memory.
- `candidate_knn()` for exact top-k ranking inside supplied candidate rows.
- Native exact 2D/3D grid KNN on CPU and CUDA.
- `fast_kmeans()` for CPU, FAISS CPU/GPU, and optional cuVS k-means [7-8],
  with deterministic shape-aware defaults for `max_iter`, `n_init`, and `tol`
  when `tuning = "auto"`, including no-pilot multistart tiers for cheap
  many-cluster jobs.
- `knn()` and `predict()` for kNN classification/regression, including
  immediate prediction with `knn(Xtrain, Ytrain, Xtest)`, class probabilities
  with `predict(type = "prob")`, and preserved `float::fl()`/`float32`
  training/query matrices for NN methods with direct float32 adapters. Explicit
  CPU FAISS Flat, HNSW, IVF, and IVFPQ models cache a session-local fitted
  index for matching `predict()` calls, so repeated predictions can reuse the
  indexed float32 vectors instead of rebuilding the FAISS index. IVF and IVFPQ
  predictions reuse trained centroids and inverted lists; IVFPQ additionally
  reuses trained product-quantizer codebooks and compressed codes. Prediction
  can adjust search-time `nprobe` for a requested `k` without retraining and
  sends the full `Xtest`/`newdata` matrix to the resolved NN backend in one
  batched search call, recording `batch_query`, `query_n`, and
  `query_call_count` in
  prediction metadata.
- CUDA FAISS/cuVS NN results record `attr(result, "gpu_residency")`, including
  the GPU provider, transient versus persistent index residency, host/device
  transfer strategy, whether a self-query reused the dataset device buffer, and
  whether any CPU fallback or CPU-side result repair occurred.
- CUDA nearest-neighbour routes return backend-shaped KNN matrices: self-neighbour
  removal, row ordering, and final output layout are handled in C++/CUDA rather
  than by R-side cleanup. CUDA graph routes that do not yet expose compiled
  include-self shaping fail clearly instead of repairing the output in R.
- `backend_info()`, `faiss_available()`, `faiss_gpu_available()`,
  `cuda_available()`, and `cuvs_available()` to report
  compiled/runtime backend support.
- `nn_capabilities()` to report supported nearest-neighbour
  method/backend/metric combinations for benchmark preflight checks.
- `nn_metric_preflight()` to identify non-finite rows, zero vectors for cosine,
  and constant rows for correlation before search. It reports one-based row
  indices and whether the requested CPU or CUDA backend will proceed.
- Set the faissR session default with
  `options(faissR.backend = "cuda")`, or use
  `Sys.setenv(FAISSR_BACKEND = "cuda")`. An explicit function argument always
  takes precedence. faissR supports CPU and CUDA; a `"metal"` setting is
  rejected clearly.
- Benchmark #1 comparison launchers for Euclidean speed tests are split into
  CPU and CUDA runs:
  `benchmark_scripts/run_benchmark1_compare_cpu_euclidean.sh` compares faissR
  CPU methods with CPU external R KNN packages, including `RcppHNSW`, `FNN`,
  `nabor`, and `rnndescent`,
  while
  `benchmark_scripts/run_benchmark1_compare_cuda_euclidean.sh` compares faissR
  CUDA/FAISS-GPU/cuVS methods. `cuda.ml` is recorded as non-standalone because
  its public KNN API fits supervised models rather than returning self-KNN
  index and distance matrices. HPC/SLURM equivalents are
  `benchmark_scripts/run_hpc_benchmark1_compare_cpu12_euclidean.sh` and
  `benchmark_scripts/run_hpc_benchmark1_compare_cuda_euclidean.sh`; both force
  Euclidean distance and write `benchmark1_faissr_vs_external_speed.csv`.
  External comparator packages are required by the benchmark image only; they
  are not faissR runtime dependencies or fallback providers.

## Available Functions

The table below summarizes the public R functions shown on GitHub. Full
argument-level details are in the [API reference](docs/usage-api.md), and the
method/backend/metric matrix is in the
[backend-capabilities page](docs/backend-capabilities.md).

| Function | Main use | Backends | Return |
| --- | --- | --- | --- |
| `nn()` | General nearest-neighbour search over reference/query matrices with Euclidean, cosine, or correlation distance. | CPU, FAISS CPU/GPU, native CUDA, and direct RAPIDS cuVS where compiled. | A `faissR_nn` list with 1-based indices, distances, and route/tuning metadata. |
| `nn_gpu()` | GPU-resident exact-family KNN for downstream CUDA packages. | CUDA exact-family routes for `method = "auto"`, `"exact"`, `"flat"`, or `"bruteforce"` with the three public metrics. | A `faissR_gpu_knn` object with owning device buffers and zero device-to-host result copies. |
| `gpu_knn_to_host()` | Explicit diagnostic conversion of a GPU-resident KNN result to ordinary R matrices. It is never called automatically by `nn_gpu()`. | Uses the CUDA result handle returned by `nn_gpu()` or the C-callable GPU API. | A host-side `faissR_nn` list with copied integer indices and numeric distances. |
| `candidate_knn()` | Exact top-k reranking inside a user-supplied candidate-neighbour matrix. This is useful when another algorithm proposes candidates and faissR should compute the final ordered neighbours. | CPU compiled scoring or the native CUDA row-candidate kernel for its documented self-query contract. | A `faissR_nn` list restricted to the supplied candidates. |
| `fast_kmeans()` | Fast k-means-style clustering with CPU, FAISS, FAISS GPU, or cuVS routes. `tuning = "auto"` selects deterministic shape-aware defaults for iteration count, starts, and tolerances. | CPU/statistics, FAISS CPU/GPU, direct cuVS where compiled. | A `faissR_kmeans` object with cluster assignments, centers, within-cluster summaries, backend/tuning metadata, and convergence diagnostics. |
| `knn()` | Fit a reusable kNN classifier/regressor, or fit and predict immediately with `knn(Xtrain, Ytrain, Xtest)`. It reuses `nn()` for neighbour search and can preserve float32 training/query data for supported routes. | Same device and method family as `nn()` for the selected training/prediction route. | Without `Xtest`, a `faissR_knn_model`; with `Xtest`, predictions or probabilities depending on `type`. |
| `predict()` | S3 method for `faissR_knn_model` objects. It predicts labels, numeric responses, or class probabilities with `type = "response"` or `"prob"`. Prediction sends the full query matrix in one batched NN call. | Same fitted route where compatible; otherwise rebuilds the same requested route rather than silently switching algorithms. | A vector/data frame of predictions or a probability matrix, with the underlying `nn()` metadata attached. |
| `backend_info()` | Inspect compiled/runtime backend support and implementation notes. | All compiled backend families. | A data frame of public backend names, implementation labels, runtime availability, and notes. |
| `nn_capabilities()` | Preflight check for supported public `method`/`backend`/`metric` combinations. `runtime = TRUE` adds current-machine availability information. | CPU, CUDA, FAISS, and cuVS capability checks. | A data frame suitable for benchmark filtering before a large run. |
| `nn_metric_preflight()` | Inspect metric inputs without running a search. | CPU/CUDA contract check. | A list of affected one-based row indices and a stable backend action label. |
| `faiss_available()` | Check whether faissR was compiled and linked against FAISS. | FAISS CPU. | A single logical value. |
| `faiss_gpu_available()` | Check whether the linked FAISS build reports GPU support. | FAISS GPU. | A single logical value. |
| `cuda_available()` | Check whether native CUDA support was compiled and a CUDA device/runtime is available. | Native CUDA. | A single logical value. |
| `cuvs_available()` | Check whether direct RAPIDS cuVS support was compiled and can be loaded. | RAPIDS cuVS. | A single logical value. |

### C/C++ Callable Entry Points

faissR also registers stable C-callable entry points with
`R_RegisterCCallable()`. These are for downstream R packages with C/C++ code and
are retrieved through the installed `<faissR_api.h>` header. Downstream
packages should add `faissR` to `LinkingTo`, include that header, and use its
typed getter functions rather than repeating function-pointer signatures.

| C-callable name | ABI | Purpose |
| --- | --- | --- |
| `faissR_c_api_version` | `int(void)` | Returns `1` for the current callable ABI. The header helper `faissR_c_api_version()` lets downstream packages reject an incompatible future ABI before dispatch. |
| `faissR_nn_float32_call` | `(x, k, backend, metric, include_self, n_threads)` | CPU FAISS Flat float32 KNN route. It accepts ordinary R double matrices or optional `float::fl()`/float32 matrices and returns the stable host `faissR_nn` list with double distances. |
| `faissR_nn_float32_call_output` | `(x, k, backend, metric, include_self, n_threads, distances)` | Same CPU FAISS Flat float32 route, with `distances = "double"` or `"float"` to request host distance storage type. |
| `faissR_nn_cuda_tuned_gpu_call` | `(x, k, method, metric, include_self, target_recall)` | CUDA self-KNN route that keeps result buffers on the GPU for `method = "auto"`, `"exact"`, `"flat"`, or `"bruteforce"`. It returns the same `faissR_gpu_knn` object shape as `nn_gpu()`, including CUDA device pointers and `device_to_host_result_copies = 0`. |

The returned GPU handle owns its device buffers. It must remain protected from
R garbage collection while downstream code uses `indices_ptr` or
`distances_ptr`; releasing the handle invalidates those pointers.
Host and GPU C-callable results include the same machine-readable distance
contract as the R API.

Explicit GPU requests are honest: if a CUDA/cuVS backend is requested
and was not compiled or is not available at runtime, faissR reports an error
instead of silently running CPU code and labelling it as GPU.

For public nearest-neighbour APIs, `backend` selects the device family:
`"auto"`, `"cpu"`, or `"cuda"`. The `method` argument selects the algorithm,
for example `method = "grid"`, `method = "ivfpq_fastscan"`, or `method = "cagra"`. Thus
`nn(x, backend = "cuda", method = "grid")` uses the CUDA grid route, while
`nn(x, backend = "cpu", method = "cagra")` stops because CAGRA is CUDA-only.
`method = "ivfpq_fastscan"` resolves to FAISS FastScan on CPU and direct cuVS
4-bit IVF-PQ on CUDA. CPU and CUDA support Euclidean, cosine, and correlation;
cosine is handled by row-normalized float32 L2 search and correlation by row-centering
plus row-normalized float32 L2 search before distance conversion. Explicit CUDA
requests never silently fall back to CPU.
With the default `method = "auto"`, faissR chooses the most appropriate method
for the selected backend. With `tuning = "auto"`, approximate methods use
deterministic defaults identified for the resolved method; pilot/cache tuning is
opt-in with `tuning = "cache"` or `tuning = "pilot"`. The route selector and
deterministic approximate-method tuning rules live in C++; R reads user options
and passes them to the compiled policy layer, and results report
`tuning_source = "cpp"` when those rules set method parameters.
For CUDA Euclidean self-KNN, the current benchmark-derived auto policy uses IVF
for large low-dimensional data, exact FAISS GPU Flat/brute force for the
measured small, medium, and high-dimensional accuracy-first shapes, and IVF for
very large high-dimensional data only at lower target-recall tiers. CPU
Euclidean auto uses exact search for tiny data, FAISS HNSW for most medium and
high-dimensional self-KNN, and FAISS IVF for selected large low-dimensional
datasets where the tuning sweep showed better speed at the requested recall.
The public nearest-neighbour metrics are `"euclidean"`, `"cosine"`, and
`"correlation"`; distance choices belong in `metric`, not in separate method
names. Euclidean results are ordinary L2 distances, not squared L2 values.
Correlation is centered cosine distance. For normalized cosine and
correlation routes, all-zero cosine rows and constant correlation rows are
handled explicitly: two zero-normalized rows have distance `0`, while a
zero-normalized row versus a nonzero row has distance `1`. CPU FAISS Flat uses
the exact CPU scorer for this degenerate case to preserve deterministic
small-`k` tie handling; explicit CUDA routes do not perform CPU repair and
therefore error clearly for these degenerate normalized rows. The finite CPU
values are software conventions for otherwise undefined cosine or correlation
cases, not mathematical cosine similarities or Pearson correlations. All
backends reject rows containing `NA`, `NaN`, `Inf`, or `-Inf`.
Unsupported method/backend/metric combinations fail without changing the
requested metric, method, or device; use `nn_capabilities(runtime = TRUE)` to
preflight both design support and locally available providers. Use
`nn_metric_preflight()` to inspect the data-dependent contract and obtain the
affected row indices before selecting a backend.

Every KNN result makes the value contract machine-readable through
`distance_is_metric`, `distance_semantics`,
`distance_comparable_across_queries`, and `distance_order`. GPU-resident
`nn_gpu()` results expose the same contract metadata without copying result
buffers to the host.
The [NN methods guide](docs/nn-methods.md) describes each nearest-neighbour
method and cites the relevant algorithm/software references.

The preferred public spellings for faissR-owned candidate-graph refinements
are `method = "nsg_style"`, `"vamana_style"`, and `"nndescent_style"`.
The historical `"nsg"`, `"vamana"`, and `"nndescent"` spellings remain
compatibility aliases. Here `_style` is a scope marker, not an algorithm name:
the package-owned CPU routes are distinct graph-refinement algorithms derived
from selected ideas in the named canonical algorithms, not feature-complete
reimplementations. These package-owned routes are experimental and are
excluded from the publication's principal comparative performance claims.
Returned objects set `implementation_status = "experimental"` and
`experimental = TRUE`. CUDA `nndescent_style` may resolve to direct external cuVS
NN-descent. Native results report
`preferred_public_method`,
`implementation_scope = "package_owned_style_implementation"`, a qualified
`implementation_label`, and `canonical_reimplementation = FALSE`; `print()`
also states that the route is experimental and package-owned. Direct cuVS
NN-descent is labeled separately as an external-provider implementation.
The [Autotuning guide](docs/autotuning.md) explains how the HPC target-recall
sweeps convert speed, recall, failure, and shape-summary tables into
deterministic C++ defaults for each method and backend.

## Installation

```r
install.packages("remotes")
remotes::install_github("tkcaccia/faissR")
```

FAISS is required and is not vendored. `faissR` compiles with C++20 because
recent FAISS headers use C++20 syntax. On systems where FAISS is not visible
through `pkg-config` or standard compiler paths, set `FAISS_HOME`:

```sh
FAISS_HOME=/path/to/faiss R CMD INSTALL .
```

Linux, macOS, and Windows are eligible package platforms. Native Windows CPU
builds require an Rtools-compatible FAISS library supplied through
`FAISS_HOME`; WSL2 remains the practical route for CUDA/cuVS. Automated
Windows builders that do not provide FAISS compile a diagnostic build that
loads and reports the missing system capability. Set
`FAISSR_REQUIRE_FAISS=1` when installation must fail unless a functional FAISS
backend is linked. Automated macOS builders without FAISS produce a
diagnostic-only build that reports the missing system capability. User macOS
source installs remain supported with Homebrew or an active conda/mamba
environment.

On macOS with Homebrew, install FAISS and the OpenMP runtime first:

```sh
brew install faiss libomp
```

or explicitly allow the GitHub install to call Homebrew for you:

```r
Sys.setenv(FAISSR_AUTO_INSTALL_FAISS = "1")
remotes::install_github("tkcaccia/faissR")
```

The Homebrew step runs only after the user explicitly sets
`FAISSR_AUTO_INSTALL_FAISS=1`; generic CI variables do not trigger package
manager changes. Bioconductor/r-universe macOS binary workers may not provide
FAISS, so those workers use the documented diagnostic build rather than a
hidden dependency manager.

If Homebrew is not available on a user macOS machine, an already-active
conda/mamba environment is also supported:

```sh
conda install -c conda-forge faiss-cpu libomp
export FAISS_HOME="$CONDA_PREFIX"
export LIBOMP_HOME="$CONDA_PREFIX"
R CMD INSTALL .
```

`configure` detects `CONDA_PREFIX` passively when FAISS and libomp are already
installed there. It does not install conda automatically, which keeps
Bioconductor and shared-machine builds explicit.

Optional CUDA/cuVS builds are enabled only when requested or auto-detected:

```sh
CUDA_HOME=/path/to/cuda CUVS_HOME=/path/to/cuvs \
FAISSR_REQUIRE_CUDA=1 FAISSR_REQUIRE_CUVS=1 R CMD INSTALL .
```

See [Installation](docs/installation.md) for CRAN/source-build details.

## Bioconductor Readiness

`faissR` includes the `GPU` `biocViews` term, a `BiocStyle` vignette, `NEWS.md`,
a standard `License: MIT + file LICENSE` declaration, and a top-level
`.BBSoptions` file with `GPU_reliance: optional`. This opts the package into
Bioconductor GPU builders without making NVIDIA libraries mandatory for the
regular CPU/FAISS build. Local submission checks should be run from a source
tarball:

```sh
R CMD build .
R CMD check --as-cran faissR_0.99.27.tar.gz
```

and then:

```r
BiocCheck::BiocCheckGitClone(".")
BiocCheck::BiocCheck("faissR_0.99.27.tar.gz", `new-package` = TRUE)
```

FAISS is a required external system dependency. CUDA and cuVS are
optional for CPU-only Bioconductor builds and must not be required there.
NVIDIA GPU builds should use `FAISSR_REQUIRE_CUDA=1` and, as needed,
`FAISSR_REQUIRE_CUVS=1` so missing GPU libraries
fail during configuration. Maintainer Support Site registration and bioc-devel
subscription are external submission steps.

On Debian/Ubuntu CPU builders, FAISS should be supplied by the FAISS
development package, typically `libfaiss-dev`. If a BiocStaging/r-universe log
installs NVIDIA CUDA packages but not `libfaiss-dev`, the failing step is the
automated system-requirements resolution: FAISS is mandatory for faissR, while
CUDA/RAPIDS libraries are optional unless a GPU build is explicitly requested.
Until the upstream r-universe resolver includes FAISS, the repository-level
`.prepare` hook installs `libfaiss-dev` for r-universe source builds and is
excluded from the package tarball.

For macOS r-universe/BiocStaging binary builds, FAISS is not currently available
in the worker system-library bundle and Homebrew is deliberately removed before
package installation. Those automated macOS binary builds therefore provide
diagnostics rather than real FAISS execution until FAISS is provided by the
builder.
Because the r-universe workflow may still launch the macOS binary job, the
configure script builds diagnostic stubs only for that worker when FAISS is
absent. `backend_info()` then reports FAISS as unavailable with reason
`runiverse_macos_diagnostic_stub_no_faiss`. Linux builds and ordinary user
macOS source installs still require real FAISS.

For r-universe/WebAssembly, `configure` detects the
`wasm32-unknown-emscripten` target and builds diagnostic stubs rather than
using host `/usr/include` FAISS headers inside the Emscripten sysroot. The WASM
artifact can report backend availability, but FAISS/CUDA/cuVS methods are not
available because those native libraries are not webR system libraries.
Supported Linux and macOS builds still require real FAISS.

## FAISS GPU With cuVS

`faissR` distinguishes two GPU/cuVS routes [13-15]:

- FAISS GPU indexes with NVIDIA cuVS integration, exposed through FAISS-backed
  backends such as `faiss_gpu_ivf_flat`, `faiss_gpu_ivfpq`, and
  `faiss_gpu_cagra`. When the linked FAISS library was built with cuVS support,
  these paths report backend labels such as `GpuIndexIVFFlat_cuVS`,
  `GpuIndexIVFPQ_cuVS`, and `GpuIndexCagra_cuVS`.
  CUDA IVF-Flat and IVFPQ auto tuning select their search parameters from
  compiled shape/k/target-recall policies for Euclidean, cosine, and
  correlation searches. Rows without complete metric-specific validation are
  labelled through `tuning_benchmark_target_met`.
- Direct RAPIDS cuVS calls selected through the public
  `backend = "cuda"` plus `method = ...` API. Concrete labels such as
  `cuda_cuvs_cagra`, `cuda_cuvs_hnsw`, `cuda_cuvs_nndescent`,
  `cuda_cuvs_bruteforce`, `cuda_cuvs_ivf_flat`, `cuda_cuvs_ivfpq`, and
  `cuda_cuvs_ivfpq_fastscan` are recorded as resolved backend metadata for
  diagnostics and benchmarks; they are not hidden public backend or method
  options.
  CUDA CAGRA supports cosine by row-normalizing float32 input and correlation
  by centering and row-normalizing float32 input before graph search. Euclidean
  CAGRA `tuning = "auto"` uses measured shape/k/target rows from
  `benchmark_scripts/cuda_cagra_euclidean_shape_tuning_defaults_from_uploaded_results.csv`;
  cosine/correlation tables seeded from those Euclidean rows record
  `tuning_benchmark_target_met = FALSE` until the corrected metric-specific
  tuning sweeps are rerun.
  `cuda_cuvs_ivfpq_fastscan` keeps the trained cuVS IVF-PQ index, compressed
  codes, dataset device buffer, and cuVS resources in a bounded session-local
  cache for compatible repeated `nn()` calls. Self-query searches reuse the
  fitted dataset device buffer directly, and repeated searches with the same
  separate query matrix can reuse one cached query device buffer via
  `options(faissR.cache_cuda_ivfpq_query_buffers = TRUE)`.
  The CUDA HPC FastScan wrapper tunes `nlist`, `nprobe`, and byte-aligned 4-bit
  `pq_dim` through `IVFPQ_FASTSCAN_NLIST_MULTS`,
  `IVFPQ_FASTSCAN_NPROBE_MULTS`, and `IVFPQ_FASTSCAN_PQ_DIMS`.
  CUDA cosine and correlation `tuning = "auto"` currently use policies seeded
  from the CUDA Euclidean FastScan sweep and mark
  `tuning_benchmark_target_met = FALSE` until the corrected metric-specific
  sweeps are rerun. The seeded correlation table is
  `benchmark_scripts/cuda_ivfpq_fastscan_correlation_shape_tuning_defaults_from_seeded_euclidean_results.csv`
  The uploaded correlation sweep
  `faissR_IVFPQ_FASTSCAN_TUNING_CUDA_correlation_20260703_083505` failed
  before reaching cuVS under the old Euclidean-only guard.
  `cuda_cuvs_nndescent` supports Euclidean/L2 and normalized cosine/correlation
  graph construction. CUDA NN-descent Euclidean auto tuning uses the measured
  CUDA sweep; CUDA cosine and correlation auto tuning currently use policies
  seeded from that Euclidean table and mark
  `tuning_benchmark_target_met = FALSE` until the metric-specific HPC wrappers
  are rerun. The CUDA correlation seed is
  `benchmark_scripts/cuda_nndescent_correlation_shape_tuning_defaults_from_seeded_euclidean_results.csv`.
  The HNSW route builds a CUDA CAGRA seed graph and converts it with
  `cuvsHnswFromCagraWithDataset`, supports `target_recall = 0.9`, `0.95`, or `0.99`
  speed/recall tiers for Euclidean/cosine/correlation requests,
  and records `cuda_hnsw_design =
  "cuvs_hnsw_from_cagra_cpu_hierarchy"` because this is a cuVS wrapper route,
  not vendored CUDA code or a pure all-GPU HNSW implementation [3,22-23].
- Native CUDA graph routes such as `method = "nsg"` and `method = "vamana"`
  use faissR-owned candidate pruning plus CUDA row-candidate refinement. CUDA
  Euclidean/cosine/correlation NSG and Vamana
  `tuning = "auto"` now select graph parameters from compiled
  shape/k/target-recall tables; cosine is searched as
  row-normalized float32 Euclidean graph refinement and converted back to
  cosine distance. CUDA NSG and Vamana correlation currently seed their graph parameters
  from the corresponding measured CUDA cosine tables, reporting
  `tuning_benchmark_target_met = FALSE` until the dedicated metric sweeps are
  rerun [16,21,24,29].

Use `backend_info()` and the attributes returned by `nn()` to confirm which
route and parameters a result used.
Use `nn_capabilities()` to inspect which public `method`, `backend`, and
`metric` combinations are supported before launching a large benchmark.

## GPU-Resident Output For Downstream Packages

Most R users should call `nn()`, which returns ordinary R matrices. Packages
that already run CUDA code can instead call `nn_gpu()` when the KNN output must
stay on the GPU:

```r
res <- nn_gpu(
  x,
  k = 15,
  exclude_self = TRUE,
  method = "auto",
  metric = "euclidean",
  target_recall = 0.99
)
```

The returned `faissR_gpu_knn` object owns CUDA device buffers through an
external pointer and reports:

- `indices_ptr`: CUDA device pointer to a column-major `n_query x k` int32
  neighbour matrix using 1-based R indices.
- `distances_ptr`: CUDA device pointer to a column-major `n_query x k` float32
  distance matrix.
- `result_residency = "cuda"`, `index_base = 1L`,
  `indices_type = "int32"`, `distance_type = "float32"`, `metric`, and
  `backend_used` metadata.

The object is intentionally not converted to host memory by default. Use
`gpu_knn_to_host(res)` only when explicitly inspecting or testing the result in
R.

Other packages can also bypass the R wrapper and retrieve the C-callable entry
point registered by faissR:

```cpp
typedef SEXP (*faissR_nn_cuda_tuned_gpu_fun)(
  SEXP x,
  SEXP k,
  SEXP method,
  SEXP metric,
  SEXP include_self,
  SEXP target_recall
);

auto fn = reinterpret_cast<faissR_nn_cuda_tuned_gpu_fun>(
  R_GetCCallable("faissR", "faissR_nn_cuda_tuned_gpu_call")
);
```

The current GPU-resident route supports exact KNN for
`method = "auto"`, `"exact"`, `"flat"`, or `"bruteforce"`. Euclidean inputs
`bfKnn` when available and request
similarities are converted on the CUDA device to faissR's shifted
smaller-is-better distance. For 2D/3D Euclidean data, a direct-difference CUDA
kernel avoids cancellation in the dot-product L2 identity. Cosine and
correlation use native CUDA exact transforms with the same output contract.
With `method = "auto"`, `nn_gpu()` records the same compiled auto-selection
metadata as `nn()`. If that policy would prefer an approximate method such as
IVF for ordinary `nn()` but that provider cannot yet expose persistent
GPU-resident result buffers, `nn_gpu()` keeps the exact-family GPU-resident
route and records `auto_preferred_backend`, `auto_preferred_method`, and
`auto_residency_constraint`. It also records the exact-family
`execution_tuning` used by the GPU-resident route and the
`auto_preferred_tuning` row for the preferred approximate CUDA method,
available.
Approximate FAISS GPU/cuVS methods still use `nn()` and return host objects
until those provider result buffers are exposed as persistent GPU-resident
objects.

### cuVS NN-Descent Shared-Memory Note

On some RAPIDS cuVS builds, direct CUDA NN-descent can fail on
high-dimensional FP32 L2 inputs with `cudaErrorInvalidValue` during
`cuvsNNDescentBuild`. We traced this to the cuVS L2-norm kernel requesting more
than CUDA's default dynamic shared memory per block without opting into the
larger device-supported limit. A local cuVS patch that calls
`cudaFuncSetAttribute(cudaFuncAttributeMaxDynamicSharedMemorySize)` before the
kernel launch fixed the full COIL20 `1440 x 16384` case and MNIST70k on the
test machine. faissR does not vendor this cuVS patch or silently fall back to
CPU; affected users should update to a cuVS release containing the fix or build
cuVS with the patch. See the copy-ready upstream report in
[docs/cuvs-nndescent-shared-memory-issue.md](docs/cuvs-nndescent-shared-memory-issue.md).

## Quick Example

```r
library(faissR)

x <- scale(as.matrix(iris[, 1:4]))
nn_res <- nn(x, k = 15, backend = "auto", metric = "euclidean", n_threads = 4)
nn_res$indices[1:3, 1:5]
```

## License

`faissR` is released under the MIT license. External libraries such as FAISS
and RAPIDS cuVS are linked as system dependencies and are not vendored into
the R package [1-3,13-16].
