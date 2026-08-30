\name{nn_capabilities}
\alias{nn_capabilities}
\title{Nearest-neighbour method capabilities}
\usage{
nn_capabilities(runtime = FALSE)
}
\arguments{
\item{runtime}{Logical; when \code{FALSE} (the default), report support by
design without checking the current compiled/runtime libraries. When
\code{TRUE}, add \code{resolved_backend}, \code{runtime_available},
\code{runtime_reason}, and \code{runtime_notes} columns for the current
installation. \code{runtime_reason} uses stable labels such as
\code{"available"}, \code{"unsupported_combination"}, \code{"missing_faiss"},
\code{"missing_faiss_gpu"}, \code{"missing_cuda"},
\code{"missing_cuda_route"}, and \code{"missing_cuvs"} for benchmark
preflight tables.}
}
\value{
A data frame with one row per public \code{method}, \code{backend}
(\code{"auto"}, \code{"cpu"}, or \code{"cuda"}), and \code{metric}
combination. Columns include \code{supported}, \code{exact},
\code{implementation}, \code{implementation_status}, and \code{notes}.
Package-owned \code{*_style} routes are marked \code{"experimental"};
external-provider NN-descent is identified separately. If
\code{runtime = TRUE}, runtime availability columns are appended.
}
\description{
\code{nn_capabilities()} returns the public method/backend/metric support table
used by the nearest-neighbour API. It separates combinations that are supported
by design from combinations that should be treated as expected skips in
benchmarks.
}
\details{
faissR exposes three public nearest-neighbour metrics: \code{"euclidean"},
\code{"cosine"}, and \code{"correlation"}. Correlation is centered cosine
similarity.

The capability table reports metric support only when the selected route
computes neighbours under that metric. FAISS Flat, IVF-Flat, IVFPQ, and HNSW
support cosine and correlation by using normalized dot-product searches.
CAGRA and NNDescent support cosine and correlation by using normalized
Euclidean graph search. Public CUDA HNSW
uses RAPIDS cuVS HNSW from a CAGRA seed graph with a cuVS CPU hierarchy and
    records that wrapper design
in metadata rather than presenting it as a pure all-GPU HNSW implementation.
Public CPU NSG uses faissR's distinct native NSG/MRNG-derived route for all
metrics because linked FAISS graph builders can abort
during graph construction; large high-dimensional CPU inputs use deterministic
FAISS HNSW seeding before the derived pruning pass.
Public CUDA \code{method = "cagra"} can resolve to FAISS GPU CAGRA or direct
cuVS CAGRA; \code{options(faissR.cagra_implementation = "faiss_gpu")} or
\code{"cuvs"} forces one provider, while \code{"auto"} uses a deterministic
shape rule: direct cuVS CAGRA is selected for compact high-dimensional
self-KNN, and FAISS GPU CAGRA remains the default when both providers are
available for other shapes. Availability preflights respect the forced provider
for all supported CAGRA metrics, and returned approximate NN objects record
\code{cagra_provider} plus \code{cagra_provider_option}.

Use \code{runtime = TRUE} for benchmark preflight checks that must distinguish
a valid method/metric combination from a route that is unavailable in the
current build, such as FAISS GPU rows on a CPU-only installation.
}
\examples{
caps <- nn_capabilities()
subset(caps, method == "flat" & supported)
runtime_caps <- nn_capabilities(runtime = TRUE)
}
