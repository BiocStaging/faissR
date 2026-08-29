nn_capability <- function(supported, exact, implementation, notes) {
    list(
        supported = isTRUE(supported),
        exact = if (isTRUE(supported)) exact else NA,
        implementation = if (isTRUE(supported)) {
            implementation
        } else {
            NA_character_
        },
        notes = notes
    )
}

nn_auto_backend_capability <- function(method, metric) {
    cpu <- nn_capability_row(method, "cpu", metric)
    cuda <- nn_capability_row(method, "cuda", metric)
    supported <- isTRUE(cpu$supported[[1L]]) || isTRUE(cuda$supported[[1L]])
    exact <- c(
        if (isTRUE(cpu$supported[[1L]])) cpu$exact[[1L]] else NA,
        if (isTRUE(cuda$supported[[1L]])) cuda$exact[[1L]] else NA
    )
    exact <- exact[!is.na(exact)]
    nn_capability(
        supported,
        if (length(exact)) all(as.logical(exact)) else NA,
        "runtime CPU/CUDA selector",
        if (supported) {
            paste(
                "Auto uses a validated CUDA route when its runtime is",
                "available, and otherwise uses a supported CPU route."
            )
        } else {
            "No CPU or CUDA route is exposed for this method/metric."
        }
    )
}

nn_auto_method_capability <- function(backend, metric, all_metrics, euclidean) {
    if (identical(backend, "cpu")) {
        return(nn_capability(
            all_metrics,
            NA,
            "shape-aware CPU selector",
            paste(
                "Selects among exact, grid, FAISS, and package-owned graph",
                "routes using shape, metric, k, and target recall."
            )
        ))
    }
    notes <- if (euclidean) {
        paste(
            "Selects among CUDA grid, exhaustive FAISS GPU/cuVS, and",
            "IVF-Flat routes using shape, k, target recall, and availability."
        )
    } else {
        paste(
            "Selects among transformed exhaustive and graph CUDA routes",
            "using shape, k, target recall, and runtime availability."
        )
    }
    nn_capability(all_metrics, NA, "shape-aware CUDA selector", notes)
}

nn_exact_capability <- function(
    method,
    backend,
    metric,
    all_metrics,
    euclidean
) {
    if (identical(method, "flat")) {
        implementation <- if (identical(backend, "cpu")) {
            "FAISS CPU Flat"
        } else {
            "FAISS GPU Flat"
        }
    } else if (identical(backend, "cpu")) {
        implementation <- "FAISS CPU Flat"
    } else if (euclidean) {
        implementation <- "FAISS GPU Flat or cuVS brute force"
    } else {
        implementation <- "FAISS GPU Flat or transformed cuVS brute force"
    }
    nn_capability(
        all_metrics,
        TRUE,
        implementation,
        paste(
            "Cosine uses row normalization; correlation uses row centering",
            "and normalization before exhaustive search."
        )
    )
}

nn_grid_capability <- function(backend, non_ip_metric) {
    nn_capability(
        non_ip_metric,
        TRUE,
        if (identical(backend, "cpu")) {
            "native CPU 2D/3D grid"
        } else {
            "native CUDA 2D/3D grid"
        },
        if (non_ip_metric) {
            paste(
                "Only valid for 2D/3D self-KNN; transformed metrics use",
                "Euclidean grid search."
            )
        } else {
            "Grid search does not expose raw inner-product search."
        }
    )
}

nn_hnsw_capability <- function(backend, all_metrics) {
    cpu <- identical(backend, "cpu")
    nn_capability(
        all_metrics,
        FALSE,
        if (cpu) "FAISS HNSW" else "RAPIDS cuVS HNSW from CAGRA",
        if (cpu) {
            paste(
                "FAISS HNSW; cosine and correlation use normalized",
                "inner-product HNSW."
            )
        } else {
            paste(
                "cuVS HNSW builds a CAGRA seed graph and converts it with the",
                "host dataset; metadata records this hybrid design."
            )
        }
    )
}

nn_ivf_capability <- function(method, backend, all_metrics) {
    provider <- if (identical(backend, "cpu")) "FAISS CPU" else "FAISS GPU"
    index <- if (identical(method, "ivf")) "IVF-Flat" else "IVF-PQ"
    nn_capability(
        all_metrics,
        FALSE,
        paste(provider, index),
        paste(
            index,
            "uses L2 directly; cosine and correlation use row",
            "transforms before search."
        )
    )
}

nn_fastscan_capability <- function(backend, all_metrics) {
    cpu <- identical(backend, "cpu")
    nn_capability(
        all_metrics,
        FALSE,
        if (cpu) {
            "FAISS CPU IVFPQ FastScan with Flat refinement"
        } else {
            "RAPIDS cuVS CUDA IVF-PQ with 4-bit compressed codes"
        },
        if (cpu) {
            paste(
                "Uses FAISS IndexIVFPQFastScan with 4-bit lookup tables and",
                "optional Flat reranking after metric-specific transforms."
            )
        } else {
            paste(
                "Uses direct cuVS 4-bit IVF-PQ after metric transforms and",
                "does not silently fall back to CPU FAISS FastScan."
            )
        }
    )
}

nn_package_graph_capability <- function(method, backend, all_metrics) {
    cpu <- identical(backend, "cpu")
    label <- if (identical(method, "nsg")) {
        "NSG/MRNG-derived"
    } else {
        "Vamana-derived"
    }
    implementation <- if (identical(method, "nsg")) {
        if (cpu) {
            "native CPU NSG candidate graph"
        } else {
            "native CUDA NSG candidate graph"
        }
    } else if (cpu) {
        "native Vamana candidate graph"
    } else {
        "native Vamana candidate graph with CUDA refinement"
    }
    nn_capability(
        all_metrics,
        FALSE,
        implementation,
        paste(
            "faissR's distinct",
            label,
            "candidate-graph implementation uses compiled pruning and",
            if (cpu) "CPU refinement." else "native CUDA candidate refinement."
        )
    )
}

nn_nndescent_capability <- function(backend, all_metrics) {
    cpu <- identical(backend, "cpu")
    nn_capability(
        all_metrics,
        FALSE,
        if (cpu) "native CPU NNDescent" else "cuVS CUDA NN-descent",
        if (cpu) {
            paste(
                "Package-owned CPU NN-descent uses deterministic seed",
                "neighbours and compiled fixed-width graph storage."
            )
        } else {
            "CUDA uses direct RAPIDS cuVS NN-descent after metric transforms."
        }
    )
}

nn_cagra_capability <- function(backend, all_metrics) {
    supported <- identical(backend, "cuda") && all_metrics
    nn_capability(
        supported,
        FALSE,
        "FAISS GPU CAGRA or cuVS CAGRA",
        if (identical(backend, "cuda")) {
            paste(
                "CUDA-only approximate graph search with a FAISS GPU, direct",
                "cuVS, or deterministic shape-aware provider rule."
            )
        } else {
            "CAGRA is CUDA-only."
        }
    )
}

nn_method_capability <- function(method, backend, metric) {
    all_metrics <- metric %in% nn_metric_labels()
    euclidean <- identical(metric, "euclidean")
    non_ip_metric <- metric %in% c("euclidean", "cosine", "correlation")
    if (identical(method, "auto")) {
        return(nn_auto_method_capability(
            backend,
            metric,
            all_metrics,
            euclidean
        ))
    }
    if (method %in% c("exact", "flat", "bruteforce")) {
        return(nn_exact_capability(
            method,
            backend,
            metric,
            all_metrics,
            euclidean
        ))
    }
    if (identical(method, "grid")) {
        return(nn_grid_capability(backend, non_ip_metric))
    }
    if (identical(method, "hnsw")) {
        return(nn_hnsw_capability(backend, all_metrics))
    }
    if (method %in% c("ivf", "ivfpq")) {
        return(nn_ivf_capability(method, backend, all_metrics))
    }
    if (identical(method, "ivfpq_fastscan")) {
        return(nn_fastscan_capability(backend, all_metrics))
    }
    if (method %in% c("nsg", "vamana")) {
        return(nn_package_graph_capability(method, backend, all_metrics))
    }
    if (identical(method, "nndescent")) {
        return(nn_nndescent_capability(backend, all_metrics))
    }
    if (identical(method, "cagra")) {
        return(nn_cagra_capability(backend, all_metrics))
    }
    nn_capability(FALSE, NA, NA_character_, "Unsupported method.")
}
