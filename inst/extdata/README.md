# Vignette data

`zeisel_brain_pca.rds` is a compact `SingleCellExperiment` derived from the
public Zeisel mouse-brain single-cell RNA-sequencing data distributed by the
Bioconductor [`scRNAseq`](https://bioconductor.org/packages/scRNAseq) package.
The source study is Zeisel et al. (2015),
<https://doi.org/10.1126/science.aaa1934>. The installed artifact contains cell
metadata and 50 PCA coordinates, but not the expression assay. Recreate it
with:

```sh
Rscript inst/scripts/prepare_zeisel_brain_pca.R
```

The preparation script records source dimensions, preprocessing, package
versions, source URLs, and the access date in
`metadata(object)$faissR_provenance`. The artifact is formally documented in
the package as `?zeisel_brain_pca`.
