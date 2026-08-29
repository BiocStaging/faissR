#' Configure the default faissR execution backend
#'
#' Explicit function arguments take precedence over `options(faissR.backend)`,
#' then `FAISSR_BACKEND`; CPU is the final default. The current faissR source
#' supports CPU and CUDA. `"metal"` is rejected explicitly.
#'
#' @param backend Optional backend: `"cpu"` or `"cuda"`.
#' @return The active backend. Setting returns the previous option invisibly.
#' @examples
#' old <- getOption("faissR.backend")
#' faissR_backend("cpu")
#' faissR_backend()
#' options(faissR.backend = old)
#' @export
faissR_backend <- function(backend = NULL) {
    if (is.null(backend)) {
        return(resolve_faissr_environment_backend(NULL))
    }
    backend <- validate_faissr_environment_backend(backend, "backend")
    old <- getOption("faissR.backend", NULL)
    options(faissR.backend = backend)
    invisible(old)
}

validate_faissr_environment_backend <- function(backend, label = "backend") {
    backend <- tolower(as.character(backend))
    if (length(backend) != 1L || is.na(backend) || !nzchar(backend)) {
        stop("`", label, "` must be one of \"cpu\" or \"cuda\".", call. = FALSE)
    }
    if (identical(backend, "metal")) {
        stop(
            "faissR does not currently provide a Metal ",
            "backend; use \"cpu\" or \"cuda\".",
            call. = FALSE
        )
    }
    if (!backend %in% c("cpu", "cuda")) {
        stop("`", label, "` must be one of \"cpu\" or \"cuda\".", call. = FALSE)
    }
    backend
}

resolve_faissr_environment_backend <- function(
    backend = NULL,
    allow_auto = TRUE
) {
    if (!is.null(backend)) {
        if (length(backend) != 1L || is.na(backend)) {
            stop("`backend` must be a single value.", call. = FALSE)
        }
        value <- tolower(as.character(backend))
        if (allow_auto && identical(value, "auto")) {
            return("auto")
        }
        return(validate_faissr_environment_backend(value))
    }
    option <- getOption("faissR.backend", NULL)
    if (!is.null(option)) {
        return(validate_faissr_environment_backend(
            option,
            "option faissR.backend"
        ))
    }
    environment <- Sys.getenv("FAISSR_BACKEND", unset = "")
    if (nzchar(environment)) {
        return(validate_faissr_environment_backend(
            environment,
            "FAISSR_BACKEND"
        ))
    }
    "cpu"
}
