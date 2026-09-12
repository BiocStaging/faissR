#!/usr/bin/env Rscript

# Recreate the compact public single-cell object used by the vignette.
# This script requires the suggested Bioconductor packages listed below and
# network access for the first scRNAseq download. The installed vignette uses
# only the resulting offline RDS file.

required <- c(
    "BiocSingular", "S4Vectors", "scater", "scRNAseq", "scran", "scuttle",
    "SingleCellExperiment", "SummarizedExperiment"
)
missing <- required[
    !vapply(required, requireNamespace, logical(1L), quietly = TRUE)
]
if (length(missing)) {
    stop(
        "Install the missing Bioconductor packages first: ",
        paste(missing, collapse = ", "),
        call. = FALSE
    )
}

args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args)) {
    args[[1L]]
} else {
    file.path("inst", "extdata", "zeisel_brain_pca.rds")
}

sce <- scRNAseq::ZeiselBrainData(ensembl = TRUE, location = FALSE)
sce <- scuttle::logNormCounts(sce)
variance <- scran::modelGeneVar(sce)
top_genes <- scran::getTopHVGs(variance, n = min(2000L, nrow(sce)))

set.seed(1001L)
sce <- scater::runPCA(
    sce,
    subset_row = top_genes,
    ncomponents = 50L,
    BSPARAM = BiocSingular::IrlbaParam(),
    name = "PCA"
)

cell_type_columns <- intersect(
    c("level1class", "level2class", "tissue", "group #"),
    colnames(SummarizedExperiment::colData(sce))
)
compact <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = matrix(integer(), nrow = 0L, ncol = ncol(sce))),
    colData = SummarizedExperiment::colData(sce)[
        , cell_type_columns, drop = FALSE
    ]
)
colnames(compact) <- colnames(sce)
SingleCellExperiment::reducedDim(compact, "PCA") <-
    SingleCellExperiment::reducedDim(sce, "PCA")
S4Vectors::metadata(compact)$faissR_provenance <- list(
    source_package = "scRNAseq",
    source_function = "ZeiselBrainData",
    source_url = "https://bioconductor.org/packages/scRNAseq",
    source_doi = "https://doi.org/10.1126/science.aaa1934",
    source_accessed = as.character(Sys.Date()),
    source_reference = "Zeisel et al. (2015), Science 347:1138-1142",
    preprocessing = paste(
        "logNormCounts; modelGeneVar; 2000 HVGs; 50-component PCA",
        "with BiocSingular::IrlbaParam; seed 1001"
    ),
    source_dimensions = c(features = nrow(sce), cells = ncol(sce)),
    pca_dimensions = dim(SingleCellExperiment::reducedDim(compact, "PCA")),
    package_versions = vapply(
        required,
        function(package) as.character(utils::packageVersion(package)),
        character(1L)
    )
)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
saveRDS(compact, output, compress = "xz", version = 2L)
message(
    "Wrote ", normalizePath(output),
    " (", file.info(output)$size, " bytes)"
)
