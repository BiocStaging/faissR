#' Summarize native neighbour-search backend availability
#'
#' `backend_info()` reports which `faissR` nearest-neighbour backends can
#' currently run. It never silently falls back from an explicit GPU request to
#' CPU; this table is informational only.
#'
#' @return A data frame with one row per compiled/runtime backend family and
#'   columns describing availability, public call hints, public backend names,
#'   supported public method/metric summaries, non-public implementation route
#'   labels, device/runtime hints, and a short note. Use
#'   \code{\link{nn_capabilities}()} for the full method/backend/metric matrix.
#' @examples
#' info <- backend_info()
#' info[, c("backend", "available", "public_backends")]
#' @export
backend_info <- function() {
    summaries <- backend_info_summaries()
    flags <- backend_info_flags(summaries)
    data.frame(
        backend = c("cpu", "faiss", "faiss_gpu_cuvs", "cuvs", "cuda"),
        available = flags$available,
        knn_available = flags$available,
        public_call = backend_info_public_calls(),
        public_backends = c("cpu", "cpu, cuda", "cuda", "cuda", "cuda"),
        supported_methods = backend_info_supported_methods(),
        supported_metrics = backend_info_supported_metrics(),
        resolved_route = backend_info_resolved_routes(),
        device = backend_info_devices(summaries),
        runtime = backend_info_runtimes(summaries),
        note = backend_info_notes(flags, summaries),
        stringsAsFactors = FALSE
    )
}

backend_info_flags <- function(summaries) {
    cuda <- backend_flag(cuda_available)
    faiss <- backend_flag(faiss_available)
    cuvs <- backend_flag(cuvs_available)
    list(
        cuda = cuda,
        faiss = faiss,
        cuvs = cuvs,
        available = c(
            TRUE,
            faiss,
            isTRUE(summaries$faiss$gpu) && cuda,
            cuvs,
            cuda
        )
    )
}

backend_info_summaries <- function() {
    list(cuda = cuda_summary(), faiss = faiss_summary(), cuvs = cuvs_summary())
}

backend_info_public_calls <- function() {
    c(
        "backend = \"cpu\"",
        paste0(
            "backend = \"cpu\" or \"cuda\", method = ",
            "\"flat\"/\"ivf\"/\"ivfpq\"/\"hnsw\"/",
            "\"ivfpq_fastscan\"/\"cagra\" as supported"
        ),
        "backend = \"cuda\", method = \"ivf\"/\"ivfpq\"/\"cagra\"",
        paste0(
            "backend = \"cuda\", method = \"bruteforce\"/\"hnsw\"/",
            "\"nndescent\"/\"ivfpq_fastscan\"/\"cagra\""
        ),
        "backend = \"cuda\""
    )
}

backend_info_supported_methods <- function() {
    c(
        paste(
            "auto, exact, flat, bruteforce, grid, hnsw, ivf, ivfpq,",
            "ivfpq_fastscan, vamana, nsg, nndescent"
        ),
        paste(
            "flat, ivf, ivfpq, hnsw, ivfpq_fastscan, nsg; GPU",
            "flat/ivf/ivfpq/cagra when FAISS GPU is available"
        ),
        "ivf, ivfpq, cagra",
        "bruteforce, hnsw, nndescent, ivfpq_fastscan, cagra",
        paste(
            "grid, flat, bruteforce, hnsw, ivf, ivfpq, ivfpq_fastscan,",
            "vamana, nsg, nndescent, cagra where compiled"
        )
    )
}

backend_info_supported_metrics <- function() {
    c(
        paste(
            "euclidean, cosine, correlation; method-specific exclusions",
            "in nn_capabilities()"
        ),
        paste(
            "euclidean, cosine, correlation for Flat/IVF/IVFPQ/HNSW and",
            "CPU IVFPQ FastScan where available; public NSG uses the native",
            "CPU route, with deterministic FAISS HNSW seeding on large",
            "high-dimensional CPU inputs; explicit FAISS NSG is Euclidean-only"
        ),
        "euclidean, cosine, correlation for IVF/IVFPQ and CAGRA",
        paste(
            "euclidean, cosine, correlation for direct brute force, direct",
            "IVF/PQ, HNSW from CAGRA, direct CAGRA, and direct cuVS",
            "NN-descent using metric transforms where needed"
        ),
        paste(
            "euclidean, cosine, correlation where the selected CUDA method",
            "supports the metric"
        )
    )
}

backend_info_resolved_routes <- function() {
    c(
        "implementation label: cpu",
        paste(
            "implementation labels include faiss_flat_l2, faiss_ivf,",
            "faiss_hnsw, faiss_ivfpq_fastscan, and faiss_gpu_*"
        ),
        paste(
            "implementation labels include faiss_gpu_ivf_flat,",
            "faiss_gpu_ivfpq, and faiss_gpu_cagra"
        ),
        paste(
            "implementation labels include cuda_cuvs_bruteforce,",
            "cuda_cuvs_hnsw, cuda_cuvs_nndescent,",
            "cuda_cuvs_ivfpq_fastscan, and cuda_cuvs_cagra"
        ),
        paste(
            "implementation labels include cuda_grid, cuda_vamana, and",
            "cuda_nsg; exact CUDA may report cuda"
        )
    )
}

backend_info_devices <- function(summaries) {
    with(summaries, {
        c(cpu_summary(), faiss$device, cuda$device, cuvs$device, cuda$device)
    })
}

backend_info_runtimes <- function(summaries) {
    faiss_gpu_runtime <- summaries$faiss$runtime
    if (isTRUE(summaries$faiss$gpu)) {
        faiss_gpu_runtime <- combine_nonempty(
            faiss_gpu_runtime,
            paste(
                "FAISS GPU IVF and CAGRA indexes backed by NVIDIA cuVS",
                "when FAISS is built with cuVS"
            )
        )
    }
    c(
        R.version$platform,
        summaries$faiss$runtime,
        faiss_gpu_runtime,
        summaries$cuvs$runtime,
        summaries$cuda$runtime
    )
}

backend_info_notes <- function(flags, summaries) {
    faiss_note <- if (flags$faiss) {
        paste(
            "Real FAISS C++ KNN is available behind public CPU/CUDA method",
            "requests; IVFPQ FastScan CPU search requires linked FAISS",
            "FastScan support."
        )
    } else {
        "Real FAISS C++ KNN is unavailable; FAISS method requests will fail."
    }
    c(
        "Native CPU path is always available.",
        faiss_note,
        backend_info_faiss_gpu_note(flags, summaries),
        backend_info_cuvs_note(flags$cuvs),
        backend_info_cuda_note(flags$cuda)
    )
}

backend_info_faiss_gpu_note <- function(flags, summaries) {
    if (isTRUE(summaries$faiss$gpu) && flags$cuda) {
        return(paste(
            "FAISS GPU IVF-Flat, IVF-PQ, and CAGRA use FAISS GPU indexes",
            "with NVIDIA cuVS integration when linked FAISS provides it;",
            "result backends identify the corresponding cuVS GPU index."
        ))
    }
    paste(
        "FAISS GPU cuVS-integrated IVF/CAGRA requests are unavailable;",
        "CUDA requests fail unless another validated route is available."
    )
}

backend_info_cuvs_note <- function(available) {
    if (available) {
        "RAPIDS cuVS CUDA KNN is available behind public CUDA requests."
    } else {
        paste(
            "RAPIDS cuVS CUDA KNN is unavailable; cuVS-backed public CUDA",
            "method requests will fail."
        )
    }
}

backend_info_cuda_note <- function(available) {
    if (available) {
        "Native CUDA KNN path is available for explicit CUDA requests."
    } else {
        "Native CUDA KNN is unavailable; explicit CUDA requests will fail."
    }
}

backend_flag <- function(fn) {
    tryCatch(isTRUE(fn()), error = function(e) FALSE)
}

cpu_summary <- function() {
    cores <- faissr_quiet_warning(parallel::detectCores(logical = TRUE))
    if (length(cores) != 1L || is.na(cores) || !is.finite(cores)) {
        "CPU"
    } else {
        paste0("CPU (", cores, " logical cores)")
    }
}

parse_nvidia_smi_summary <- function(out) {
    valid <- !is.na(out) & nzchar(trimws(out))
    if (!length(out) || !any(valid)) {
        return(list(device = NA_character_, runtime = NA_character_))
    }
    first <- out[which(valid)[1L]]
    parts <- trimws(strsplit(first, ",", fixed = TRUE)[[1L]])
    device <- if (length(parts) >= 1L && nzchar(parts[1L])) {
        parts[1L]
    } else {
        NA_character_
    }
    driver <- if (length(parts) >= 2L) parts[2L] else NA_character_
    memory <- if (length(parts) >= 3L) parts[3L] else NA_character_
    runtime <- paste(
        c(
            if (!is.na(driver) && nzchar(driver)) {
                paste0("driver ", driver)
            } else {
                NULL
            },
            if (!is.na(memory) && nzchar(memory)) {
                paste0(memory, " MiB")
            } else {
                NULL
            }
        ),
        collapse = ", "
    )
    if (!nzchar(runtime)) {
        runtime <- NA_character_
    }
    list(device = device, runtime = runtime)
}

nvidia_smi_summary <- function() {
    smi <- Sys.which("nvidia-smi")
    if (!nzchar(smi)) {
        return(list(device = NA_character_, runtime = NA_character_))
    }
    out <- tryCatch(
        system2(
            smi,
            c(
                "--query-gpu=name,driver_version,memory.total",
                "--format=csv,noheader,nounits"
            ),
            stdout = TRUE,
            stderr = FALSE
        ),
        error = function(e) character()
    )
    parse_nvidia_smi_summary(out)
}

cuda_summary <- function() {
    native <- cuda_native_summary()
    smi <- nvidia_smi_summary()

    device <- first_nonempty(native$device, smi$device)
    runtime <- combine_nonempty(native$runtime, smi$runtime)
    list(device = device, runtime = runtime)
}

cuda_native_summary <- function() {
    text <- tryCatch(
        cuda_device_info_json_cpp(),
        error = function(e) NA_character_
    )
    if (length(text) != 1L || is.na(text) || !nzchar(text)) {
        return(list(device = NA_character_, runtime = NA_character_))
    }

    available <- json_get_bool(text, "available")
    if (isTRUE(available)) {
        device <- json_get_string(text, "name")
        compute <- json_get_string(text, "compute_capability")
        total_memory <- json_get_number(text, "total_memory")
        free_memory <- json_get_number(text, "free_memory")
        memory <- cuda_memory_summary(free_memory, total_memory)
        runtime <- combine_nonempty(
            if (!is.na(compute)) {
                paste0("compute capability ", compute)
            } else {
                NA_character_
            },
            memory
        )
        return(list(device = device, runtime = runtime))
    }

    reason <- json_get_string(text, "reason")
    list(device = NA_character_, runtime = reason)
}

faiss_summary <- function() {
    text <- tryCatch(
        faiss_info_json_cpp(),
        error = function(e) NA_character_
    )
    available <- json_get_bool(text, "available")
    gpu <- json_get_bool(text, "gpu")
    gpu_cagra <- json_get_bool(text, "gpu_cagra")
    fastscan <- json_get_bool(text, "fastscan")
    reason <- json_get_string(text, "reason")
    runtime <- if (isTRUE(available)) {
        combine_nonempty(
            "FAISS C++ library",
            if (isTRUE(gpu)) "FAISS GPU headers" else "CPU-only FAISS headers",
            if (isTRUE(gpu_cagra)) "GpuIndexCagra available" else NA_character_,
            if (isTRUE(fastscan)) "FastScan available" else NA_character_
        )
    } else if (!is.na(reason)) {
        reason
    } else {
        NA_character_
    }
    list(
        device = if (isTRUE(gpu)) {
            "CPU/GPU depending on requested FAISS index"
        } else {
            "CPU"
        },
        runtime = runtime,
        gpu = isTRUE(gpu),
        gpu_cagra = isTRUE(gpu_cagra),
        fastscan = isTRUE(fastscan)
    )
}

#' Check whether FAISS GPU support is available
#'
#' @return `TRUE` when faissR was compiled and linked against a FAISS build
#'   that reports GPU support.
#' @examples
#' faiss_gpu_available()
#' @export
faiss_gpu_available <- function() {
    text <- tryCatch(
        faiss_info_json_cpp(),
        error = function(e) NA_character_
    )
    isTRUE(json_get_bool(text, "available")) &&
        isTRUE(json_get_bool(text, "gpu"))
}

cuvs_summary <- function() {
    text <- tryCatch(
        cuvs_info_json_cpp(),
        error = function(e) NA_character_
    )
    available <- json_get_bool(text, "available")
    reason <- json_get_string(text, "reason")
    device <- json_get_string(text, "device")
    compute <- json_get_string(text, "compute_capability")
    total_memory <- json_get_number(text, "total_memory")
    runtime <- if (isTRUE(available)) {
        combine_nonempty(
            "RAPIDS cuVS C API",
            if (!is.na(compute)) {
                paste0("compute capability ", compute)
            } else {
                NA_character_
            },
            cuda_memory_summary(NA_real_, total_memory)
        )
    } else if (!is.na(reason)) {
        reason
    } else {
        NA_character_
    }
    list(device = if (!is.na(device)) device else "CUDA GPU", runtime = runtime)
}

json_get_bool <- function(text, key) {
    value <- json_capture(text, key, "(true|false)")
    if (is.na(value)) {
        return(NA)
    }
    identical(tolower(value), "true")
}

json_get_number <- function(text, key) {
    value <- json_capture(text, key, "([0-9]+(?:\\.[0-9]+)?)")
    if (is.na(value)) {
        return(NA_real_)
    }
    as.numeric(value)
}

json_get_string <- function(text, key) {
    value <- json_capture(text, key, "\"((?:\\\\.|[^\"\\\\])*)\"")
    if (is.na(value)) {
        return(NA_character_)
    }
    json_unescape(value)
}

json_capture <- function(text, key, value_pattern) {
    key_pattern <- paste0("\"", gsub("([\\W])", "\\\\\\1", key), "\"")
    pattern <- paste0(key_pattern, "\\s*:\\s*", value_pattern)
    match <- regexec(pattern, text, perl = TRUE)
    parts <- regmatches(text, match)[[1L]]
    if (length(parts) < 2L) NA_character_ else parts[2L]
}

json_unescape <- function(value) {
    value <- gsub("\\\\n", "\n", value)
    value <- gsub("\\\\r", "\r", value)
    value <- gsub("\\\\t", "\t", value)
    value <- gsub("\\\\\"", "\"", value)
    gsub("\\\\\\\\", "\\\\", value)
}

cuda_memory_summary <- function(free_memory, total_memory) {
    if (is.na(total_memory) || total_memory <= 0) {
        return(NA_character_)
    }
    total <- bytes_to_gib(total_memory)
    if (!is.na(free_memory) && free_memory >= 0) {
        return(paste0(
            bytes_to_gib(free_memory),
            " GiB free / ",
            total,
            " GiB total"
        ))
    }
    paste0(total, " GiB total")
}

bytes_to_gib <- function(bytes) {
    format(round(bytes / 1024^3, 2), nsmall = 2L, trim = TRUE)
}

first_nonempty <- function(...) {
    values <- unlist(list(...), use.names = FALSE)
    values <- values[!is.na(values) & nzchar(values)]
    if (length(values) == 0L) NA_character_ else values[1L]
}

combine_nonempty <- function(...) {
    values <- unlist(list(...), use.names = FALSE)
    values <- values[!is.na(values) & nzchar(values)]
    values <- unique(values)
    if (length(values) == 0L) NA_character_ else paste(values, collapse = ", ")
}
