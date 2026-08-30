#' Preflight nearest-neighbor metric inputs
#'
#' Inspect reference and query rows for values that affect the public distance
#' contract before calling [nn()]. This function performs no neighbor search.
#'
#' @param data Numeric reference matrix, data frame, or optional
#'   `float::fl()`/`float32` matrix.
#' @param points Optional query object with the same number of columns as
#'   `data`. `NULL` represents self-query and reuses the `data` inspection.
#' @param metric One of `"euclidean"`, `"cosine"`, or `"correlation"`.
#' @param backend Requested backend (`"auto"`, `"cpu"`, or `"cuda"`). `NULL`
#'   follows the package backend option and environment-variable policy.
#'
#' @return A list containing one-based `data_rows` and `points_rows` for the
#'   metric-specific degenerate condition, corresponding non-finite row
#'   indices, `would_succeed`, and a stable `action` label. CPU cosine and
#'   correlation use the documented zero-normalized convention; CUDA rejects
#'   affected rows. An automatic backend is reported as backend-dependent.
#'
#' @details
#' For cosine, a degenerate row is exactly all zero after conversion to the
#' inspected representation. For correlation, it is a row whose entries are
#' all equal. `NA`, `NaN`, `Inf`, and `-Inf` are non-finite and are rejected by
#' every backend. Row indices are one-based. The scan is `O((n + m) p)` and is
#' intentionally explicit so it need not add another full pass to every
#' nearest-neighbor call.
#'
#' @examples
#' x <- rbind(c(0, 0), c(1, 0), c(1, 1))
#' nn_metric_preflight(x, metric = "cosine", backend = "cuda")
#' @export
nn_metric_preflight <- function(
    data,
    points = NULL,
    metric = c("euclidean", "cosine", "correlation"),
    backend = NULL
) {
    if (missing(metric)) {
        metric <- "euclidean"
    }
    metric <- normalize_nn_metric(metric)
    backend <- normalize_nn_backend_arg(backend)
    data <- metric_preflight_matrix(data, "data")
    self_query <- is.null(points)
    points <- if (self_query) {
        data
    } else {
        metric_preflight_matrix(points, "points")
    }
    if (ncol(data) != ncol(points)) {
        stop("`data` and `points` must have the same number of columns.",
             call. = FALSE)
    }

    data_scan <- metric_preflight_rows(data, metric)
    points_scan <- if (self_query) data_scan else metric_preflight_rows(
        points,
        metric
    )
    has_non_finite <- length(data_scan$non_finite) > 0L ||
        length(points_scan$non_finite) > 0L
    has_degenerate <- length(data_scan$degenerate) > 0L ||
        length(points_scan$degenerate) > 0L
    decision <- metric_preflight_decision(
        backend,
        metric,
        has_non_finite,
        has_degenerate
    )

    list(
        metric = metric,
        requested_backend = backend,
        self_query = self_query,
        degenerate_kind = switch(
            metric,
            cosine = "zero_vector",
            correlation = "constant_row",
            euclidean = "none"
        ),
        data_rows = data_scan$degenerate,
        points_rows = points_scan$degenerate,
        data_non_finite_rows = data_scan$non_finite,
        points_non_finite_rows = points_scan$non_finite,
        has_degenerate_rows = has_degenerate,
        has_non_finite_rows = has_non_finite,
        would_succeed = decision$would_succeed,
        action = decision$action,
        cpu_convention = if (
            metric %in% c("cosine", "correlation") && has_degenerate
        ) {
            "two_degenerate_rows_distance_0;mixed_rows_distance_1"
        } else {
            "not_applicable"
        },
        row_index_base = 1L
    )
}

metric_preflight_matrix <- function(x, name) {
    if (is_float32_matrix_input(x)) {
        x <- float32_to_numeric_matrix(x, name)
    } else {
        if (is.data.frame(x)) {
            x <- as.matrix(x)
        }
        if (!is.matrix(x) || !is.numeric(x)) {
            stop("`", name, "` must be a numeric matrix or data frame.",
                 call. = FALSE)
        }
        storage.mode(x) <- "double"
    }
    if (nrow(x) < 1L || ncol(x) < 1L) {
        stop("`", name, "` must have at least one row and one column.",
             call. = FALSE)
    }
    x
}

metric_preflight_rows <- function(x, metric) {
    non_finite <- which(rowSums(!is.finite(x)) > 0L)
    finite <- rep(TRUE, nrow(x))
    finite[non_finite] <- FALSE
    degenerate <- switch(
        metric,
        euclidean = integer(),
        cosine = which(finite & rowSums(x != 0) == 0L),
        correlation = which(finite & apply(
            x,
            1L,
            function(row) all(row == row[[1L]])
        ))
    )
    list(
        degenerate = as.integer(degenerate),
        non_finite = as.integer(non_finite)
    )
}

metric_preflight_decision <- function(
    backend,
    metric,
    has_non_finite,
    has_degenerate
) {
    if (has_non_finite) {
        return(list(
            would_succeed = FALSE,
            action = "error_non_finite_all_backends"
        ))
    }
    if (!has_degenerate || identical(metric, "euclidean")) {
        return(list(would_succeed = TRUE, action = "proceed"))
    }
    switch(
        backend,
        cpu = list(
            would_succeed = TRUE,
            action = "cpu_zero_normalized_convention"
        ),
        cuda = list(
            would_succeed = FALSE,
            action = "error_degenerate_cuda"
        ),
        auto = list(
            would_succeed = NA,
            action = "backend_dependent_resolve_backend_before_search"
        )
    )
}
