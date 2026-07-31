#' faissR: FAISS-backed nearest neighbours and kNN utilities
#'
#' `faissR` contains FAISS-backed neighbour search, k-means,
#' and kNN classifier/regressor helpers. The main public entry points are
#' `nn()`, `nn_gpu()`, `gpu_knn_to_host()`, `candidate_knn()`, `fast_kmeans()`,
#' `knn()`, `predict()`, `backend_info()`, and `nn_capabilities()`.
#' Classification probabilities
#' are returned with `predict(type = "prob")`.
#'
#' FAISS is a required system dependency for every functional native build.
#' Diagnostic-only builds on explicitly unsupported WebAssembly or Bioconductor
#' staging platforms cannot execute nearest-neighbour methods. RAPIDS cuVS/CUDA is
#' optional for CPU-only builds, so CPU-only machines can compile and use FAISS
#' CPU indexes without NVIDIA libraries. For NVIDIA GPU builds, users should
#' request the GPU features explicitly so missing CUDA/cuVS libraries
#' are fatal at configure time. FAISS GPU indexes can use NVIDIA cuVS
#' integration when linked against a cuVS-enabled FAISS build; direct RAPIDS
#' cuVS backends are also available when requested at build time. Explicit
#' CUDA/cuVS requests fail clearly when those optional libraries are
#' unavailable. No
#' Python bridge is used.
#'
#' CUDA-enabled downstream R packages can consume tuned GPU-resident KNN
#' results without copying them through ordinary R matrices. Add `faissR` to
#' `LinkingTo`, include the installed `<faissR_api.h>` header, verify
#' `faissR_c_api_version()`, and obtain the typed callable with
#' `faissR_get_nn_cuda_tuned_gpu()`. The returned external pointer owns the
#' device buffers and must remain protected for as long as a consumer uses the
#' non-owning index or distance pointers. Host materialization is explicit via
#' `gpu_knn_to_host()`.
#'
#' @keywords internal
"_PACKAGE"
