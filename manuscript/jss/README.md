# faissR manuscript for the Journal of Statistical Software

This directory contains the JSS-format manuscript source:

- `faissR_jss.tex`: article source in the official JSS LaTeX class.
- `faissR_jss.bib`: references used by the article.
- `faissR_jss_supplement.tex`: supplementary-material source.
- `code.R` and `code.html`: compact article replication entry points.
- `replication_article.R`: frozen-result validation and collation.
- `build_docx.py`: reproducibly converts the JSS source to the Word reading
  copy while preserving package names, code blocks, tables, and workflow
  figures.
- `build_supplement_docx.py`: converts the supplementary source to an editable
  Word reading copy.
- `jss.cls`, `jss.bst`, `jsslogo.jpg`: official JSS template files.

Build the article and supplementary PDFs with:

```sh
latexmk -pdf faissR_jss.tex
latexmk -pdf faissR_jss_supplement.tex
```

Regenerate the editable Word reading copies with:

```sh
python3 build_docx.py
python3 build_supplement_docx.py
```

Run the compact CPU replication and regenerate its executed HTML report from
this directory with:

```sh
Rscript code.R
Rscript -e 'knitr::spin("code.R", knit = TRUE)'
```

The full special-hardware replication uses
`benchmark_scripts/jmlr_mloss_publication/final_campaign/submit_campaign.R`.
That single commented entry point validates the frozen image and submits the
existing independent CPU/CUDA launchers one phase at a time; it does not hide
their resource headers or advance past an unchecked evidence gate.

Generated PDFs, DOCX files, LaTeX intermediates, and internal review-cycle
reports are intentionally excluded from version control. The LaTeX, BibTeX,
replication, and document-builder sources are tracked. The package
`.Rbuildignore` excludes this directory from the Bioconductor source tarball.

The current manuscript distinguishes metric correctness, desired-recall
attainment, and independent held-out performance. Comparative speed tables,
external-package comparisons, reusable-index measurements, and the
auto-versus-oracle analysis remain intentionally pending until the frozen HPC
campaign is complete. Before submission, those jobs must be aggregated,
author declarations must be approved, and the replication archive must be
frozen with checksums.

The current JSS instructions require a PDF in JSS style, software source, and
replication materials for every reported result:
<https://www.jstatsoft.org/guides/submission>.

The publication campaign must use a container containing the exact package
version and commit named by the route-QA launchers. After any executable
package change, rebuild the image and run both route-QA jobs before submitting
timed work; earlier containers are not valid substitutes even when their CUDA
libraries are unchanged.
