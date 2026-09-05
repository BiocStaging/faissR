# faissR Journal of Statistical Software materials

## Sources and evidence

- `faissR_jss.tex`, `faissR_jss_supplement.tex`, and `faissR_jss.bib`:
  authoritative article, supplement, and bibliography.
- `code.R` and `replication_article.R`: single commented entry point and
  analysis orchestration. `code.html` is executed compact-mode output.
- `build_manuscript_tables.R`: 18 archive-backed numerical summaries.
  Their stable identifiers do not equal the typeset table numbers.
- `build_paired_cpu_figure.R` and `build_comprehensive_r_figure.R`:
  checksum-verified controlled-pair and seven-package comparison figures.
- `build_architecture_figures.R`: software architecture diagrams.
- `analyze_completed_systems.R` and `completed_systems/`: checksum-verified
  raw tuned-HNSW and CPU/CUDA query-workload results and their reanalysis.
- `paired_cpu_comparison/`, `comprehensive_r_comparison/`, `cpu_loodo/`,
  and `faissR_jss_evidence_snapshot.tar.gz`: recorded experiment evidence,
  retaining original execution identities and accompanying checksum ledgers.
- `practical_cpu_example.R`: Biobase sample.ExpressionSet example.
  Biobase is a package import; no external dataset package is needed.
  It reports fresh observed recall and fitted-index reuse. Its small timings
  illustrate the API and are not cross-package benchmark measurements.
- `build_docx.py` and `build_supplement_docx.py`: editable reading copies.
  The official JSS-class PDF, not Word pagination, is the submission format.

## Reproduction

From this directory, with a functional CPU installation of faissR:

```sh
Rscript code.R
Rscript -e 'knitr::spin("code.R", knit = TRUE)'
```

To reanalyze the supplied evidence without a GPU:

```sh
FAISSR_JSS_MODE=archive FAISSR_JSS_DERIVED_DIR=derived Rscript code.R
```

Use `FAISSR_JSS_MODE=all` for both modes. Digests are checked before analysis.
Outputs include verification records, numerical-summary manifests,
completed-systems tables, paired figures, and session information. Exact
execution versions remain in the machine-readable provenance; they must not
be replaced by the current package version.

Build the manuscript and supplement:

```sh
Rscript build_architecture_figures.R
latexmk -pdf -halt-on-error faissR_jss.tex
latexmk -pdf -halt-on-error faissR_jss_supplement.tex
python3 build_docx.py
python3 build_supplement_docx.py
```

Set `FAISSR_JSS_EXAMPLE_OUT` to a destination when running
`practical_cpu_example.R` to retain CSVs, session information, and freshly
renderable `practical_cpu_output.tex`. Example timings vary across executions.

## Submission boundaries

The article includes only analyzed evidence. The seven-package comparison
contains 216 tasks and 6,480 route repetitions, including failures and
timeouts. Reported approximate-recall eligibility is the recorded mean-recall
screen, not an uncomputed confidence bound. Descriptive interface tables are
maintained in LaTeX; empirical summaries are rebuilt by the scripts above.

Full experiment launchers are under `benchmark_scripts/jss_reproduction/`.
They need the recorded data, container, hardware, and scheduler. Historical
run identifiers and paths are provenance, not instructions to rerun old jobs.
Internal planning/review files are not part of the submission materials.

A persistent archival identifier is not yet available. The checksummed
repository bundle does not substitute for such a deposit. The source package
excludes manuscript, benchmark scripts, and internal review files via
`.Rbuildignore`. See `SUBMISSION_AUDIT.md` for verification and remaining
submission requirements.

JSS requirements: https://www.jstatsoft.org/authors
