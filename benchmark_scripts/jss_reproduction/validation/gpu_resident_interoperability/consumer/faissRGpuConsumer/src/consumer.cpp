#include <Rcpp.h>
#include <cuda_runtime_api.h>
#include <faissR_api.h>

#include <cstddef>

extern "C" int faissr_consumer_checksum_cuda(
    const int*, const float*, std::size_t,
    unsigned long long*, double*);

namespace {

SEXP named_element(const Rcpp::List& x, const char* name) {
    if (!x.containsElementNamed(name)) {
        Rcpp::stop("GPU result is missing `%s`.", name);
    }
    return x[name];
}

}  // namespace

extern "C" SEXP faissr_consumer_make_gpu_knn(
    SEXP x, SEXP k, SEXP method, SEXP metric,
    SEXP include_self, SEXP target_recall) {
    if (faissR_c_api_version() != 1) {
        Rcpp::stop("Unsupported faissR C ABI version.");
    }
    faissR_nn_cuda_tuned_gpu_fun fun = faissR_get_nn_cuda_tuned_gpu();
    return fun(x, k, method, metric, include_self, target_recall);
}

extern "C" SEXP faissr_consumer_gpu_checksum(SEXP result_sexp) {
    Rcpp::List result(result_sexp);
    SEXP owner = named_element(result, "handle");
    SEXP indices_ptr = named_element(result, "indices_ptr");
    SEXP distances_ptr = named_element(result, "distances_ptr");
    if (TYPEOF(owner) != EXTPTRSXP || R_ExternalPtrAddr(owner) == nullptr) {
        Rcpp::stop("The owning GPU handle is invalid.");
    }
    if (TYPEOF(indices_ptr) != EXTPTRSXP ||
        TYPEOF(distances_ptr) != EXTPTRSXP) {
        Rcpp::stop("GPU buffer fields are not external pointers.");
    }
    const int n_query = Rcpp::as<int>(named_element(result, "n_query"));
    const int k = Rcpp::as<int>(named_element(result, "k"));
    const int device = Rcpp::as<int>(named_element(result, "device"));
    if (n_query < 1 || k < 1) Rcpp::stop("Invalid GPU result dimensions.");
    cudaError_t status = cudaSetDevice(device);
    if (status != cudaSuccess) {
        Rcpp::stop("cudaSetDevice failed: %s", cudaGetErrorString(status));
    }
    const int* indices = static_cast<const int*>(R_ExternalPtrAddr(indices_ptr));
    const float* distances =
        static_cast<const float*>(R_ExternalPtrAddr(distances_ptr));
    if (indices == nullptr || distances == nullptr) {
        Rcpp::stop("GPU result pointers are null.");
    }
    unsigned long long index_sum = 0;
    double distance_sum = 0.0;
    const std::size_t values = static_cast<std::size_t>(n_query) * k;
    const int code = faissr_consumer_checksum_cuda(
        indices, distances, values, &index_sum, &distance_sum);
    if (code != static_cast<int>(cudaSuccess)) {
        Rcpp::stop("CUDA checksum failed: %s",
                   cudaGetErrorString(static_cast<cudaError_t>(code)));
    }
    return Rcpp::List::create(
        Rcpp::Named("n_values") = static_cast<double>(values),
        Rcpp::Named("index_checksum") = static_cast<double>(index_sum),
        Rcpp::Named("distance_checksum") = distance_sum,
        Rcpp::Named("device") = device,
        Rcpp::Named("full_result_host_bytes") =
            static_cast<double>(values * (sizeof(int) + sizeof(float))),
        Rcpp::Named("consumer_host_bytes") =
            static_cast<double>(sizeof(index_sum) + sizeof(distance_sum))
    );
}
