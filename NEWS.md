# faissR 0.99.21

* Adds a session-wide backend selector through `faissR_backend()`,
  `options(faissR.backend = ...)`, and `FAISSR_BACKEND`. Explicit function
  arguments retain precedence and CPU remains the default. Metal requests
  fail explicitly because faissR currently provides CPU and CUDA backends.
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
* Provides FAISS-backed nearest-neighbour search, graph construction,
  graph clustering, k-nearest-neighbour prediction, and k-means helpers.
* Adds optional CUDA, FAISS GPU, RAPIDS cuVS, and RAPIDS libcugraph routes
  where the corresponding system libraries are available.
* Supports shape-aware automatic tuning policies for Euclidean, cosine,
  correlation, and inner-product nearest-neighbour searches.
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
