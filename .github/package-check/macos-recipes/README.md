# Candidate R-macos FAISS recipe

The `faiss` file is a candidate dependency recipe for the
[R-macos recipes](https://github.com/R-macos/recipes) build system. It builds a
generic, CPU-only static FAISS library and excludes Python, tests, examples,
Metal, CUDA, ROCm, cuVS, and SVS. The source archive is pinned by SHA256.

This directory is preparation material, not an installed dependency and not an
upstream recipe. Before proposing it upstream:

1. fork `R-macos/recipes` and copy `faiss` into its `recipes/` directory;
2. run `./build.sh faiss` locally for each available architecture;
3. run the repository's **Cook from Recipes** workflow for both arm64 and
   x86_64;
4. verify that the result contains `include/faiss/IndexFlat.h` and
   `lib/libfaiss.a` under `/opt/R/<architecture>`;
5. install and check the same faissR source archive against each result; and
6. submit the tested recipe to `R-macos/recipes` for review.

The recipe expects the R-macos toolchain prefix to provide `omp.h` and
`libomp.dylib`. It uses Apple's Accelerate framework for BLAS and LAPACK.
faissR's `configure` detects `/opt/R/arm64` and `/opt/R/x86_64` automatically.
It never downloads or installs this recipe during package installation.
