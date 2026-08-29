nn_gpu_input_dims <- function(x, arg) {
    if (is_float32_matrix_input(x)) {
        return(float32_matrix_dims(x, arg))
    }
    dim(as.matrix(x))
}

nn_gpu_normalize_k <- function(k, n, self_query, exclude_self) {
    if (is.null(k)) {
        k <- if (n == 1L) {
            1L
        } else {
            min(n, auto_k(n, include_self = self_query && !exclude_self))
        }
    }
    k <- normalize_nn_positive_integer(
        k,
        "k",
        "`k` must be NULL or a positive integer."
    )
    max_k <- if (exclude_self) n - 1L else n
    if (k > max_k) {
        stop(
            "`k` cannot be larger than the available neighbor count.",
            call. = FALSE
        )
    }
    k
}

normalize_nn_gpu_options <- function(
    method,
    metric,
    tuning,
    target_recall,
    exclude_self
) {
    method <- normalize_nn_method(normalize_scalar_choice_arg(
        method,
        arg = "method",
        default = "auto",
        formal_choices = c("auto", "exact", "flat", "bruteforce")
    ))
    if (!method %in% c("auto", "exact", "flat", "bruteforce")) {
        stop(
            "`nn_gpu()` currently supports GPU-resident output only for ",
            "`method = \"auto\"`, `\"exact\"`, `\"flat\"`, ",
            "or `\"bruteforce\"`.",
            call. = FALSE
        )
    }
    metric <- normalize_nn_metric(metric)
    tuning <- normalize_nn_tuning(tuning)
    target_recall <- normalize_hnsw_target_recall(target_recall)
    exclude_self <- normalize_scalar_logical_arg(
        exclude_self,
        "exclude_self",
        default = FALSE
    )
    list(
        method = method,
        metric = metric,
        tuning = tuning,
        target_recall = target_recall,
        exclude_self = exclude_self
    )
}

validate_nn_gpu_shape <- function(data, points, points_missing, exclude_self) {
    data_dim <- nn_gpu_input_dims(data, "data")
    points_dim <- if (points_missing) {
        data_dim
    } else {
        nn_gpu_input_dims(points, "points")
    }
    if (!identical(data_dim[[2L]], points_dim[[2L]])) {
        stop(
            "`data` and `points` must have the same number of columns.",
            call. = FALSE
        )
    }
    self_query <- points_missing || identical(data, points)
    if (exclude_self && !self_query) {
        stop(
            "Self-neighbor exclusion is only valid when `points` is `data`.",
            call. = FALSE
        )
    }
    list(data_dim = data_dim, points_dim = points_dim, self_query = self_query)
}

prepare_nn_gpu_request <- function(
    data,
    points,
    k,
    exclude_self,
    method,
    metric,
    tuning,
    target_recall,
    points_missing
) {
    options <- normalize_nn_gpu_options(
        method,
        metric,
        tuning,
        target_recall,
        exclude_self
    )
    shape <- validate_nn_gpu_shape(
        data,
        points,
        points_missing,
        options$exclude_self
    )
    k <- nn_gpu_normalize_k(
        k,
        shape$data_dim[[1L]],
        shape$self_query,
        options$exclude_self
    )
    if (!isTRUE(cuda_available())) {
        stop(
            "`nn_gpu()` requires faissR to be built with ",
            "CUDA support and a CUDA device.",
            call. = FALSE
        )
    }
    c(
        list(
            data = data,
            points = points,
            data_dim = shape$data_dim,
            points_dim = shape$points_dim,
            k = k,
            self_query = shape$self_query
        ),
        options
    )
}

nn_gpu_auto_plan <- function(request) {
    selection <- nn_auto_select_shape_cpp(
        resolved_backend = "cuda_auto",
        requested_backend = "cuda",
        requested_method = "auto",
        shape = list(
            n = as.integer(request$data_dim[[1L]]),
            p = as.integer(request$data_dim[[2L]]),
            n_points = as.integer(request$points_dim[[1L]]),
            k = as.integer(request$k),
            metric = request$metric,
            self_query = request$self_query,
            exclude_self = request$exclude_self,
            work_size = prod(as.double(c(
                request$data_dim[[1L]],
                request$points_dim[[1L]],
                request$data_dim[[2L]]
            )))
        ),
        tuning = request$tuning,
        target_recall = request$target_recall
    )
    preferred_backend <- nn_auto_selected_backend(
        selection,
        "faiss_gpu_flat_l2"
    )
    preferred_method <- nn_resolved_backend_public_method(
        preferred_backend
    ) %||%
        "exact"
    if (
        length(preferred_method) != 1L ||
            is.na(preferred_method) ||
            !nzchar(preferred_method)
    ) {
        preferred_method <- "exact"
    }
    resident <- preferred_method %in% c("exact", "flat", "bruteforce")
    list(
        selection = selection,
        preferred_backend = preferred_backend,
        preferred_method = preferred_method,
        resolved_method = if (resident) preferred_method else "exact",
        residency_constraint = if (resident) {
            NA_character_
        } else {
            .gpu_exact_residency_constraint
        }
    )
}

resolve_nn_gpu_plan <- function(request) {
    plan <- if (identical(request$method, "auto")) {
        nn_gpu_auto_plan(request)
    } else {
        list(
            selection = NULL,
            preferred_backend = NA_character_,
            preferred_method = NA_character_,
            resolved_method = request$method,
            residency_constraint = NA_character_
        )
    }
    plan$preferred_tuning <- if (is.null(plan$selection)) {
        NULL
    } else {
        nn_gpu_tuning_params_for_method(
            request$data_dim[[1L]],
            request$data_dim[[2L]],
            request$k,
            plan$preferred_method,
            metric = request$metric,
            target_recall = request$target_recall
        )
    }
    plan$execution_tuning <- nn_gpu_tuning_params_for_method(
        request$data_dim[[1L]],
        request$data_dim[[2L]],
        request$k,
        plan$resolved_method,
        metric = request$metric,
        target_recall = request$target_recall
    )
    plan
}

execute_nn_gpu_plan <- function(request, plan) {
    use_faiss <- identical(
        nn_gpu_exact_provider(
            request$metric,
            request$data_dim[[2L]],
            faiss_gpu = faiss_gpu_available()
        ),
        "faiss_gpu_bfknn"
    )
    if (!use_faiss) {
        return(nn_cuda_float32_gpu_cpp(
            request$data,
            request$points,
            as.integer(request$k),
            request$exclude_self,
            request$metric,
            "cuda_native_exact_gpu",
            plan$resolved_method
        ))
    }
    backend <- if (identical(request$metric, "inner_product")) {
        plan$execution_tuning$result_backend %||%
            plan$execution_tuning$resolved_backend %||%
            "faiss_gpu_flat_ip"
    } else {
        "faiss_gpu_bfknn_l2"
    }
    with_faiss_gpu_runtime(plan$execution_tuning, {
        nn_faiss_gpu_bfknn_float32_gpu_cpp(
            request$data,
            request$points,
            as.integer(request$k),
            request$exclude_self,
            request$metric,
            backend,
            plan$resolved_method
        )
    })
}

validate_nn_gpu_result <- function(out) {
    if (inherits(out, "faissR_gpu_knn")) {
        return(out)
    }
    fields <- c(
        "handle",
        "indices_ptr",
        "distances_ptr",
        "n_query",
        "k",
        "result_residency"
    )
    valid <- is.list(out) &&
        all(fields %in% names(out)) &&
        identical(out$result_residency, "cuda") &&
        all(
            vapply(
                out[c("handle", "indices_ptr", "distances_ptr")],
                typeof,
                character(1L)
            ) ==
                "externalptr"
        )
    if (!valid) {
        stop(
            "The CUDA NN route did not return a valid `faissR_gpu_knn` object.",
            call. = FALSE
        )
    }
    class(out) <- unique(c("faissR_gpu_knn", class(out)))
    out
}

nn_gpu_core_metadata <- function(request, plan, out) {
    list(
        requested_backend = "cuda",
        requested_method = public_nn_method_label(request$method),
        tuning = request$tuning,
        target_recall = request$target_recall,
        self_query = request$self_query,
        exclude_self = request$exclude_self,
        gpu_resident_execution_method = plan$resolved_method,
        gpu_resident_execution_backend = out$backend_used %||% NA_character_
    )
}

nn_gpu_auto_metadata <- function(request, plan) {
    if (is.null(plan$selection)) {
        return(list())
    }
    metadata <- list(
        auto_selection = plan$selection,
        auto_preferred_backend = plan$preferred_backend,
        auto_preferred_method = plan$preferred_method,
        auto_residency_constraint = plan$residency_constraint
    )
    if (!is.list(plan$preferred_tuning)) {
        return(metadata)
    }
    c(
        metadata,
        list(
            auto_preferred_tuning = plan$preferred_tuning,
            auto_preferred_tuning_method = plan$preferred_method,
            auto_preferred_tuning_backend = plan$preferred_backend,
            auto_preferred_tuning_metric = request$metric,
        auto_preferred_tuning_source =
            plan$preferred_tuning$tuning_benchmark_source %||% NA_character_,
            auto_preferred_tuning_benchmark_target_met = isTRUE(
                plan$preferred_tuning$tuning_benchmark_target_met
            )
        )
    )
}

set_nn_gpu_metadata <- function(out, metadata) {
    for (name in names(metadata)) {
        out[[name]] <- metadata[[name]]
        attr(out, name) <- metadata[[name]]
    }
    out
}

finish_nn_gpu_result <- function(out, request, plan) {
    out <- validate_nn_gpu_result(out)
    metadata <- c(
        nn_gpu_core_metadata(request, plan, out),
        nn_gpu_auto_metadata(request, plan)
    )
    if (is.list(plan$execution_tuning)) {
        metadata$execution_tuning <- plan$execution_tuning
        out <- attach_cuda_exact_tuning(
            out,
            plan$execution_tuning,
            output = "gpu",
            n_threads = NA_integer_,
            extra = list(
                result_residency = "cuda",
                device_to_host_result_copies = 0L,
                gpu_resident_output = TRUE
            )
        )
    }
    out <- set_nn_gpu_metadata(out, metadata)
    attach_nn_distance_contract(out, request$metric)
}
