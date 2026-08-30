# faissR 0.99.31

* Resolves BiocCheck coding-practice notes by normalizing four-space
  indentation, splitting long public and internal routines into focused
  helpers, and removing redundant signal words from warning text.
* Refactors nearest-neighbour backend dispatch into explicit route,
  preflight, execution, tuning, and metadata helpers without changing the
  public API.

# faissR 0.99.30

* Fixes Windows ARM64 compilation with LLVM flang by removing an unsupported
  package-specific warning-control option from generated `Makevars.win` files.
  The diagnostic-stub and functional Windows FAISS configurations now inherit
  the Rtools Fortran flags unchanged.
* Adds a source-tree regression test for the Windows diagnostic configuration.

# faissR 0.99.29

* Restricts the public nearest-neighbour metric contract to Euclidean, cosine,
  and correlation distance and adds `nn_metric_preflight()` diagnostics for
  non-finite, zero-norm, and constant rows.
* Labels CUDA automatic routing as an experimental, L40S-calibrated policy for
  cold full-self-search and separates installed-policy evidence from post hoc
  candidate-set sensitivity analyses.
* Expands and organizes the JSS replication suite, including selector-regret,
  grouped holdout, recall-inference, workload, memory, interoperability, and
  comprehensive R-package comparison protocols.
* Revises the manuscript, supplement, vignette, reference documentation, and
  tests to match the audited public API and evidence scope.

# faissR 0.99.28

* Prevents spurious Windows ARM64 installation warnings by suppressing only
  LLVM flang's unused driver-argument diagnostic. GCC/gfortran builds and
  substantive Fortran compiler warnings remain unchanged.

# faissR 0.99.27

* Replaces the vignette's `mlbench` example with the Bioconductor `ALL`
  leukemia expression dataset and `Biobase` assay access.
* Decomposes the public nearest-neighbour wrappers, capability construction,
  and CPU/CUDA backend resolution into namespace-private helpers without
  changing the public API or result metadata contracts.
* Audits the installation and method guides, removes stale inner-product text,
  and corrects the Windows build contract and package-check examples.

# faissR 0.99.25

* Restores native Windows eligibility by removing the unnecessary Unix-only
  package restriction. Windows source builds use a compatible CPU FAISS
  installation supplied through `FAISS_HOME` (or `CONDA_PREFIX`); automated
  builders without FAISS compile explicit diagnostic stubs rather than using
  invalid `/include` and `/lib` paths. Set `FAISSR_REQUIRE_FAISS=1` to require
  a functional FAISS build and fail configuration when it is unavailable.

# faissR 0.99.24

* Adds the `FunctionalPrediction` Bioconductor view for the supervised kNN
  interfaces.
* Centralizes suppression of expected conversion and optional-runtime warnings
  in one internal helper so warning handling is explicit and auditable.

# faissR 0.99.23

* Restricts the public nearest-neighbour metric contract to Euclidean, cosine,
  and correlation and removes obsolete inner-product benchmark and publication
  routes.
* Makes session-resolved backend validation reject non-scalar values and keeps
  the public `backend = NULL` contract consistent across nearest-neighbour,
  supervised kNN, prediction, and k-means interfaces.
* Preserves the documented route and distance metadata on results returned by
  the versioned float32 C-callable interface.
* Renames the reproducible publication campaign to `jss_reproduction` and
  refreshes package documentation, references, tests, and release checks.

# faissR 0.99.22

* Adds a session-wide backend selector through `faissR_backend()`,
  `options(backend = ...)`, and `BACKEND`. Explicit function
  arguments retain precedence and CPU remains the default. Metal requests
  fail explicitly because faissR currently provides CPU and CUDA backends.
  Legacy faissR-specific selectors remain compatibility fallbacks.

# faissR 0.99.21

* Adds direct float32 adapters for exact CPU and CUDA grid search in two and
  three dimensions. Euclidean, cosine, and correlation self-KNN searches now
  consume `float::fl()` inputs without a compatibility conversion to R double,
  while preserving the requested grid method and device.
* Extends route-contract tests to cover float32 grid searches in two and three
  dimensions across all supported grid metrics.

# faissR 0.99.20

* Uses the direct-difference CUDA exact kernel for 2D/3D Euclidean
  GPU-resident searches. This avoids float32 cancellation observed with the
  norm/dot-product L2 identity for nearly coincident vectors while preserving
  CUDA residency and the exact-family API contract.
* Adds CPU/CUDA publication launchers for held-out comparisons against public
  KNN interfaces from Rnanoflann, RANN, RcppAnnoy, RcppHNSW, rnndescent,
  BiocNeighbors, FNN, and nabor.
* Expands the JSS replication protocol, independent exact-reference audits,
  metric conformance checks, and systems ablations.

# faissR 0.99.15

* Initial Bioconductor development release.
* Provides FAISS-backed nearest-neighbour search, k-nearest-neighbour
  prediction, and k-means helpers.
* Adds optional CUDA, FAISS GPU, RAPIDS cuVS, and RAPIDS libcugraph routes
  where the corresponding system libraries are available.
* Supports shape-aware automatic tuning policies for Euclidean, cosine, and
  correlation nearest-neighbour searches.
* Clarifies Bioconductor/r-universe system requirements: FAISS is the
  mandatory compiled dependency for all builds, while CUDA/RAPIDS libraries
  are optional and requested only for explicit GPU builds.
* Adds a repository-only r-universe `.prepare` hook to install the mandatory
  Debian/Ubuntu FAISS development package while the upstream sysreq database
  learns the FAISS rule, and detects `/usr` multiarch FAISS installs during
  configuration.
* Allows ordinary macOS GitHub Actions builders to install the mandatory
  Homebrew `faiss` and `libomp` dependencies during `configure`, while keeping
  ordinary interactive installs explicit or opt-in.
* Handles r-universe/WebAssembly cross-builds without leaking host Linux
  headers into the Emscripten sysroot. WebAssembly builds install diagnostic
  stubs because native FAISS/CUDA/cuVS libraries are not available in webR;
  supported native Linux/macOS builds still require FAISS.
* Detects already-active conda/mamba environments through `CONDA_PREFIX` as a
  passive macOS FAISS/libomp fallback without installing conda from
  `configure`.
* Marks automated Bioconductor macOS binary builds as unsupported for real
  FAISS execution until the Bioconductor/r-universe macOS system-library bundle
  provides FAISS. Because r-universe currently still launches the macOS binary
  job, that exact worker receives diagnostic stubs when FAISS is absent; user
  macOS source installs remain supported with Homebrew or an active conda/mamba
  environment and still require real FAISS.
* Keeps FAISS k-means compilation compatible with distro FAISS headers that do
  not expose newer clustering fields, and links macOS OpenMP through the exact
  detected `libomp` library path to avoid duplicate OpenMP runtimes when
  Homebrew FAISS is loaded.
