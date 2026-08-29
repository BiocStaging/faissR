normalize_public_nn_options <- function(
    exclude_self, backend, method, metric, tuning, target_recall, output,
    distances
) {
    exclude_self <- normalize_scalar_logical_arg(
        exclude_self,
        "exclude_self",
        default = FALSE
    )
    backend <- normalize_nn_backend_arg(backend)
    method <- normalize_nn_method(method)
    tuning <- normalize_nn_tuning(tuning)
    target_recall <- normalize_hnsw_target_recall(target_recall)
    metric <- normalize_nn_metric(metric)
    output <- resolve_nn_output(output, distances)
    list(
        exclude_self = exclude_self, backend = backend, method = method,
        metric = metric, tuning = tuning, target_recall = target_recall,
        output = output
    )
}

prepare_public_nn_request <- function(
    data, points, k, exclude_self, backend, method, metric, tuning,
    target_recall, output, distances, n_threads, points_missing,
    requested_method_input
) {
    options <- normalize_public_nn_options(
        exclude_self, backend, method, metric, tuning, target_recall, output,
        distances
    )
    validate_public_nn_method_shape(data, options$method)
    self_query <- points_missing || identical(data, points)
    data_dim <- if (is_float32_matrix_input(data)) {
        float32_matrix_dims(data, "data")
    } else {
        dim(data)
    }
    resolved_backend <- resolve_public_nn_backend(
        options$backend,
        options$method,
        options$metric,
        n = data_dim[[1L]],
        p = data_dim[[2L]],
        k = k,
        self_query = self_query
    )
    c(list(
        data = data, points = points, k = k, n_threads = n_threads,
        points_missing = points_missing, self_query = self_query,
        resolved_backend = resolved_backend,
        requested_method_input = requested_method_input
    ), options)
}

public_nn_auto_selection <- function(request) {
    nn_auto_selection_metadata(
        data = request$data,
        points = request$points,
        points_missing = request$points_missing,
        k = request$k,
        requested_backend = request$backend,
        requested_method = request$method,
        resolved_backend = request$resolved_backend,
        metric = request$metric,
        tuning = request$tuning,
        exclude_self = request$exclude_self,
        target_recall = request$target_recall
    )
}

decorate_public_nn_result <- function(result, request, auto_selection) {
    attr(result, "requested_backend") <- request$backend
    attr(result, "requested_method") <- public_nn_method_label(request$method)
    result$requested_method_input <- request$requested_method_input
    attr(result, "requested_method_input") <- request$requested_method_input
    attr(result, "tuning") <- request$tuning
    attr(result, "target_recall") <- request$target_recall
    result$exclude_self <- request$exclude_self
    attr(result, "exclude_self") <- request$exclude_self
    result <- attach_nn_method_implementation_contract(
        result,
        requested_method = request$method,
        backend_used = result$backend_used %||%
            attr(result, "backend_used") %||%
            attr(result, "resolved_backend")
    )
    if (!is.null(auto_selection)) {
        attr(result, "auto_selection") <- auto_selection
    }
    finalize_nn_output(result, request$output)
}

execute_public_nn_request <- function(request) {
    auto_selection <- public_nn_auto_selection(request)
    result <- nn_compute(
        request$data,
        request$points,
        request$k,
        request$resolved_backend,
        request$points_missing,
        exclude_self = request$exclude_self,
        n_threads = request$n_threads,
        metric = request$metric,
        tuning = request$tuning,
        target_recall = request$target_recall,
        output = request$output,
        auto_selection = auto_selection,
        requested_method = request$method
    )
    decorate_public_nn_result(result, request, auto_selection)
}
