#' Call faissR's registered GPU KNN ABI
#' @keywords internal
gpu_knn_via_c_api <- function(x, k, method = "auto", metric = "euclidean",
                              include_self = TRUE, target_recall = 0.99) {
    .Call(
        "faissr_consumer_make_gpu_knn",
        x, as.integer(k), as.character(method), as.character(metric),
        as.logical(include_self), as.numeric(target_recall),
        PACKAGE = "faissRGpuConsumer"
    )
}

#' Consume faissR GPU buffers without copying the full result to host
#' @keywords internal
gpu_result_device_checksum <- function(x) {
    .Call(
        "faissr_consumer_gpu_checksum",
        x,
        PACKAGE = "faissRGpuConsumer"
    )
}
