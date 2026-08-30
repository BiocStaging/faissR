# Comprehensive comparison with R nearest-neighbor packages

This experiment compares faissR with FNN, RANN, rnndescent, BiocNeighbors,
Rnanoflann, RcppAnnoy, and RcppHNSW. It is an end-to-end public-interface
comparison, not a kernel-only benchmark.

One Slurm-array task fixes dataset, metric, `k`, and independent query seed.
Every applicable route is then executed on that same node in a reproducibly
randomized and rotated order. Each route/repetition runs in a fresh R process.
This design prevents CPU-node differences and process high-water marks from
being attributed to package differences.

The design uses nine datasets, Euclidean/cosine/correlation, `k` equal to 15,
30, 50, or 100, two independent query seeds, and three timing repetitions.
Route-level execution is capped at 1,200 seconds. Failures and timeouts remain
in the planned-cell denominator.

Package coverage follows validated public metric contracts:

- Euclidean: all seven external packages;
- cosine: rnndescent, BiocNeighbors, RcppAnnoy angular, and RcppHNSW;
- correlation: rnndescent;
- faissR exact, automatic, and corresponding graph routes provide within-task
  references for the external comparisons.

FNN contributes brute-force, kd-tree, and cover-tree routes; RANN contributes
kd-tree and bd-tree routes; BiocNeighbors contributes exhaustive, HNSW, and
Annoy routes. These are route-level results and are also summarized by package.

Submit everything, including the dependent audit, with one command:

```bash
bash benchmark_scripts/jss_reproduction/validation/comprehensive_r_comparison/submit_comprehensive_r_comparison.sh
```

The command returns immediately after submitting the array and audit. There is
no manual second submission step. Quantitative manuscript claims require the
final report to end in `COMPREHENSIVE R COMPARISON AUDIT PASSED`.
