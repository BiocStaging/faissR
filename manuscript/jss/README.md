# faissR manuscript for the Journal of Statistical Software

This directory contains the JSS-format manuscript source:

- `faissR_jss.tex`: article source in the official JSS LaTeX class.
- `faissR_jss.bib`: references used by the article.
- `faissR_jss_supplement.tex`: supplementary-material source.
- `code.R` and `code.html`: commented standalone replication entry point and
  freshly executed output.
- `replication_article.R`: compact examples, pre-analysis archive verification,
  checksummed-result validation, and analysis orchestration.
- `build_manuscript_tables.R`: recreates every article and supplement table
  and writes a checksum manifest.
- `build_paired_cpu_figure.R`: verifies the checksummed controlled-pair evidence and
  recreates the main-text dataset-level log-ratio figure.
- `paired_cpu_comparison/`: checksummed controlled same-node CPU HNSW pairs.
- `faissR_jss_evidence_snapshot.tar.gz` and its `.sha256` file: checksummed
  campaign evidence and required pre-analysis digest. This is a version-pinned
  experiment snapshot; the archival frozen release will follow package acceptance.
- `cpu_loodo/`: checksummed machine-readable CPU leave-one-dataset-out results
  reconstructed from the explicit independent-query routes in the latest HPC transfer.
- `practical_cpu_example.R`: executable Bioconductor `ALL` example covering
  exact search, three recall-targeted HNSW calls, observed recall, returned
  evidence, and fitted-index reuse.
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

Recreate all 15 manuscript and supplement tables from the checksummed snapshot on a
regular computer with:

```sh
FAISSR_JSS_MODE=archive \
FAISSR_JSS_DERIVED_DIR=derived \
Rscript code.R
```

The archive digest is checked before extraction. A mismatch stops the script
before any result is read. Successful execution writes
`archive_verification.csv`, `manuscript_tables/manuscript_table_manifest.csv`,
`manuscript_tables/MANUSCRIPT_TABLE_AUDIT.txt`, a fresh `sessionInfo.txt`, and
the consistency artifacts `reference_record_dimensions.csv`,
`calibration_candidate_grid_manifest.csv`,
`calibration_candidate_grid_public.csv.gz`,
`experiment_version_boundaries.csv`, and `experiment_version_changes.csv`.
Use `FAISSR_JSS_MODE=all` to run the compact package examples and archive
reconstruction in one process.

Recreate the paired CPU figure directly with:

```sh
Rscript build_paired_cpu_figure.R
```

Run the practical CPU example with the Bioconductor `ALL` and `Biobase`
packages listed in the package `Suggests` field:

```sh
Rscript practical_cpu_example.R
```

Set `FAISSR_JSS_EXAMPLE_OUT` to retain its CSV summaries and provenance file.
The example timings explain the public API and are not treated as formal
cross-package benchmark evidence.

The full special-hardware experiment uses
`benchmark_scripts/jss_reproduction/final_campaign/submit_campaign.R`.
That single commented entry point validates the version-pinned image and submits the
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
independent-query within-dataset validation, and dataset-withholding analyses.
The replication workflow includes route QA, exact-reference and calibration audits,
independent-query evaluation, reusable-index
experiments, auto-versus-oracle analysis, and archive checksums. Only evidence
that passes the corresponding audit is eligible for a reported result.

The current JSS instructions request a commented replication script, rendered
output, session information, and a feasible reduced path when full experiments
need special hardware: <https://www.jstatsoft.org/authors>.

The publication campaign must use a container containing the exact package
version and commit named by the route-QA launchers. After any executable
package change, rebuild the image and run both route-QA jobs before submitting
timed work; earlier containers are not valid substitutes even when their CUDA
libraries are unchanged.
