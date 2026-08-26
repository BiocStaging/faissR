# faissR manuscript for the Journal of Statistical Software

This directory contains the JSS-format manuscript source:

- `faissR_jss.tex`: article source in the official JSS LaTeX class.
- `faissR_jss.bib`: references used by the article.
- `faissR_jss_supplement.tex`: supplementary-material source.
- `code.R` and `code.html`: compact article replication entry points.
- `replication_article.R`: frozen-result validation and collation.
- `practical_cpu_example.R`: executable 20,000-row Letter Recognition example
  covering exact search, three recall-targeted auto calls, observed recall,
  returned evidence, and fitted-index reuse.
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

Run the practical CPU example after installing the optional `mlbench` package:

```sh
Rscript practical_cpu_example.R
```

Set `FAISSR_JSS_EXAMPLE_OUT` to retain its CSV summaries and provenance file.
The example timings explain the public API and are not treated as formal
cross-package benchmark evidence.

The full special-hardware replication uses
`benchmark_scripts/jss_reproduction/final_campaign/submit_campaign.R`.
That single commented entry point validates the frozen image and submits the
existing independent CPU/CUDA launchers one phase at a time; it does not hide
their resource headers or advance past an unchecked evidence gate. Its ledger
is updated after every submission so a partial Slurm phase remains auditable.
The companion `sync_publication_suite.sh` utility verifies that a user-supplied
HPC mirror contains the same submitter and all 203 launchers before QA begins.

Generated PDFs, DOCX files, LaTeX intermediates, and internal review-cycle
reports are intentionally excluded from version control. The LaTeX, BibTeX,
replication, and document-builder sources are tracked. The package
`.Rbuildignore` excludes this directory from the Bioconductor source tarball.

The manuscript distinguishes metric correctness, desired-recall attainment,
and independent held-out performance. The replication workflow includes route
QA, exact-reference and calibration audits, held-out evaluation, reusable-index
experiments, auto-versus-oracle analysis, and archive checksums. Only evidence
that passes the corresponding audit is eligible for a reported result.

The current JSS instructions require a PDF in JSS style, software source, and
replication materials for every reported result:
<https://www.jstatsoft.org/guides/submission>.

The publication campaign must use a container containing the exact package
version and commit named by the route-QA launchers. After any executable
package change, rebuild the image and run both route-QA jobs before submitting
timed work; earlier containers are not valid substitutes even when their CUDA
libraries are unchanged.
