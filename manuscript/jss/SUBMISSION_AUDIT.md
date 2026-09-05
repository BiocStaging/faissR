# Submission audit

Date: 2026-09-05. Package: faissR 0.99.34.
This is a maintenance report, not part of the scientific article.

## Corrections

- Corrected a substantive mismatch between the archived analysis and the
  manuscript: the reported approximate-route eligibility uses point mean
  identifier-overlap recall, not an uncomputed bootstrap lower bound.
  Exact-reference audits remain distinct from approximate target attainment.
- Replaced the stale external-data example with an executed Biobase example,
  including observed recall, fitted-index reuse, and training-only preprocessing.
- Corrected the tuned RcppHNSW fitted-query median to 1.09 and restricted the
  warm-query advantage statement to its 15 HNSW cells, not all 60 CPU cells.
- Clarified that comprehensive-comparison timeout counts are route-call counts,
  not counts of distinct pairs.
- Added checksummed completed tuned-HNSW and query-workload evidence and an
  executable analysis. Fixed reproduction when the workspace path contains spaces.
- Made the architecture figure source and required evidence files eligible for
  Git tracking. Removed the obsolete experiment-plan document.
- Updated installation examples and removed obsolete graph-clustering guidance.
- Regenerated the article, supplement, Word copies, vignette, reference manual,
  and executed compact replication output. Corrected Word figure embedding and
  cross-reference handling.
- Rebalanced the article around software use, independently tuned CPU HNSW,
  query-workload behavior, and the completed seven-interface comparison.
  CUDA automatic selection is retained as a secondary sensitivity analysis.
- Defined the validation repeats explicitly: each timing repeat reruns the
  route and recomputes recall against the fixed exact reference for that query
  seed. Exact audits and approximate point-recall eligibility remain distinct.
- Restricted GPU-residency claims to the audited ownership, lifetime, and
  explicit-transfer contract; algorithmic timing comparisons all return host
  matrices and claim no residency speed benefit.
- Added truthful outcome denominators for the comprehensive comparison and
  qualified the 13-batch break-even result as HNSW reuse versus rebuilt,
  one-shot Flat calls rather than versus a reusable exact index.
- Fixed an invalid rcmdcheck argument in CI and corrected the Valgrind invocation
  to run the R executable through its debugger interface.

## Verification

- Functional local installation of 0.99.34 with external FAISS succeeded.
- R CMD check --as-cran --no-manual: 0 errors, 0 warnings, 1 note (new
  submission). Tests, examples, compiled-code checks, Rd consistency, online
  incoming checks, and vignette rebuilding passed under a valid UTF-8 locale.
  The reference manual was built separately.
- BiocCheck 1.49.30: 0 errors, 0 warnings, 0 notes, with only the
  credential-dependent Bioconductor mailing-list/support lookup explicitly
  disabled. All package-source, function-length, formatting, documentation,
  dependency, license, vignette, and unit-test checks ran.
- The complete replication entry point passed checksum validation, archive
  analysis and compact examples. Completed-systems audits passed for 720 tuned
  HNSW repetitions and 60 CPU plus 60 CUDA query-workload cells.
- Static manuscript/reference/version and asset checks passed. JSS-layout article:
  19 pages; supplement: 19 pages.
- A clean `git archive` reproduced checksum-gated evidence analysis, the compact
  CPU example, both 19-page PDFs, and both editable Word documents without
  relying on untracked workspace files.

## Publication boundary

The immutable Git commit containing this report identifies the audited source,
manuscript, replication code, and checksummed evidence snapshot. Historical
experiment identities remain in machine-readable manifests; the scientific
narrative names only the current package release.

An immutable archival release and persistent identifier still require deposit.
Hosted Windows/Linux builds and the corrected native-memory workflow have not
been rerun during this audit. Local checks do not establish those outcomes.
Raw experiment versions and commits are preserved, even though the article
presents the current package; relabelling historical results would be misleading.
Restricted datasets require acquisition from their original sources.
The article makes no quantitative GPU-residency claim and presents automatic
selection as an optional experimental policy. Its principal performance claims
come from the completed matched-node CPU, tuned-HNSW, query-workload, and CUDA
route experiments.

JSS guidance consulted: https://www.jstatsoft.org/authors and
https://www.jstatsoft.org/guides/submission. Shorter length alone does not
guarantee acceptance; reproducible software use and supported claims remain
the principal criteria.
