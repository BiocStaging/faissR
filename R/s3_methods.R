#' Summaries of faissR result objects
#'
#' These methods return compact one-row data frames describing nearest-neighbor
#' results, GPU-resident results, k-means fits, and fitted kNN models.
#'
#' @param object A faissR result or model object.
#' @param ... Reserved for compatibility with the S3 generics.
#' @return A one-row data frame containing the principal dimensions, backend,
#'   metric, and fit or residency metadata for `object`.
#' @name summary.faissR
NULL

#' @rdname summary.faissR
#' @export
summary.faissR_nn <- function(object, ...) {
    finite <- finite_nn_distances(object$distances)
    contract <- summary_nn_contract(object)
    implementation <- summary_nn_implementation(object)
    data.frame(
        queries = nrow(object$indices),
        neighbors = ncol(object$indices),
        backend = nn_summary_value(object, "backend_used", "backend"),
        metric = nn_summary_value(object, "metric", "metric"),
        distance_is_metric = contract$distance_is_metric,
        distance_semantics = contract$distance_semantics,
        distance_comparable_across_queries =
            contract$distance_comparable_across_queries,
        implementation_label = implementation$implementation_label,
        implementation_scope = implementation$implementation_scope,
        preferred_public_method = implementation$preferred_public_method,
        canonical_reimplementation = implementation$canonical_reimplementation,
        exact = isTRUE(attr(object, "exact") %||% object$exact),
        self_query = isTRUE(attr(object, "self_query")),
        exclude_self = isTRUE(
            object$exclude_self %||% attr(object, "exclude_self")
        ),
        min_distance = if (length(finite)) min(finite) else NA_real_,
        median_distance = if (length(finite)) {
            stats::median(finite)
        } else {
            NA_real_
        },
        max_distance = if (length(finite)) max(finite) else NA_real_,
        stringsAsFactors = FALSE
    )
}

finite_nn_distances <- function(distances) {
    if (is.matrix(distances) && is.numeric(distances)) {
        distances[is.finite(distances)]
    } else {
        numeric()
    }
}

nn_summary_value <- function(object, field, attribute = field) {
    as.character(
        object[[field]] %||% attr(object, attribute) %||% NA_character_
    )[1L]
}

summary_nn_contract <- function(object) {
    list(
        distance_is_metric = isTRUE(
            object$distance_is_metric %||% attr(object, "distance_is_metric")
        ),
        distance_semantics = nn_summary_value(
            object,
            "distance_semantics",
            "distance_semantics"
        ),
        distance_comparable_across_queries = isTRUE(
            object$distance_comparable_across_queries %||%
                attr(object, "distance_comparable_across_queries")
        )
    )
}

summary_nn_implementation <- function(object) {
    fields <- c(
        "implementation_label",
        "implementation_scope",
        "preferred_public_method"
    )
    values <- lapply(fields, function(field) nn_summary_value(object, field))
    names(values) <- fields
    values$canonical_reimplementation <- as.logical(
        object$canonical_reimplementation %||%
            attr(object, "canonical_reimplementation") %||%
            NA
    )[1L]
    values
}

#' @rdname summary.faissR
#' @export
summary.faissR_gpu_knn <- function(object, ...) {
    data.frame(
        queries = as.integer(object$n_query %||% NA_integer_),
        neighbors = as.integer(object$k %||% NA_integer_),
        backend = as.character(object$backend_used %||% NA_character_)[1L],
        metric = as.character(object$metric %||% NA_character_)[1L],
        result_residency = as.character(
            object$result_residency %||% "cuda"
        )[1L],
        indices_type = as.character(object$indices_type %||% "int32")[1L],
        distance_type = as.character(object$distance_type %||% "float32")[1L],
        distance_is_metric = isTRUE(object$distance_is_metric),
        distance_semantics = as.character(
            object$distance_semantics %||% NA_character_
        )[1L],
        distance_comparable_across_queries = isTRUE(
            object$distance_comparable_across_queries
        ),
        device_to_host_result_copies = as.integer(
            object$device_to_host_result_copies %||% 0L
        ),
        stringsAsFactors = FALSE
    )
}

#' @rdname summary.faissR
#' @export
summary.faissR_kmeans <- function(object, ...) {
    data.frame(
        observations = length(object$cluster),
        clusters = length(object$size),
        backend = as.character(object$backend %||% NA_character_)[1L],
        iterations = as.integer(object$iter %||% NA_integer_),
        converged = as.logical(object$converged %||% NA),
        total_withinss = as.numeric(object$tot.withinss %||% NA_real_),
        stringsAsFactors = FALSE
    )
}

#' @rdname summary.faissR
#' @export
summary.faissR_knn_model <- function(object, ...) {
    dimensions <- dim(object$Xtrain)
    data.frame(
        observations = as.integer(dimensions[[1L]]),
        features = as.integer(dimensions[[2L]]),
        task = as.character(object$task %||% NA_character_)[1L],
        k = as.integer(object$k %||% NA_integer_),
        backend = as.character(object$backend %||% NA_character_)[1L],
        method = as.character(object$method %||% NA_character_)[1L],
        metric = as.character(object$metric %||% NA_character_)[1L],
        fitted_index = !is.null(object$nn_index),
        fitted_index_backend = as.character(
            object$nn_index_backend %||% NA_character_
        )[1L],
        stringsAsFactors = FALSE
    )
}

#' Print a fitted faissR kNN model
#'
#' @param x A model returned by \code{\link{knn}()}.
#' @param ... Reserved for compatibility with \code{print()}.
#' @return `x`, invisibly.
#' @export
print.faissR_knn_model <- function(x, ...) {
    info <- summary.faissR_knn_model(x)
    cat("faissR kNN model\n")
    cat("  task: ", info$task, "\n", sep = "")
    cat(
        "  training data: ",
        info$observations,
        " x ",
        info$features,
        "\n",
        sep = ""
    )
    cat("  neighbors: ", info$k, "\n", sep = "")
    cat("  backend: ", info$backend, "\n", sep = "")
    cat("  method: ", info$method, "\n", sep = "")
    cat("  metric: ", info$metric, "\n", sep = "")
    cat(
        "  fitted index: ",
        if (info$fitted_index) "yes" else "no",
        "\n",
        sep = ""
    )
    invisible(x)
}
