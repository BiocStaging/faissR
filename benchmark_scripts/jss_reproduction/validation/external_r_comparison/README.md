# External R comparator experiment

This focused experiment addresses the JSS request for broader empirical comparison with existing R nearest-neighbor software. It contains separate CPU launchers for:

- exhaustive Euclidean search: `faissR` exact versus `FNN::get.knn(algorithm = "brute")`;
- HNSW: `faissR` HNSW versus `RcppHNSW::hnsw_knn()` for Euclidean and cosine distance; and
- NN-descent: the package-owned faissR NN-descent-derived route versus `rnndescent::nnd_knn()` for Euclidean, cosine, and correlation distance.

Every method-metric combination has its own Slurm file. The CPU header remains the established 1-node, 12-task, 48-hour header. Runs use nine datasets, `k = 15, 30, 50, 100`, two validation query seeds, three timing repeats, and a 2,000-second per-cell timeout. Failures, timeouts, and out-of-memory results remain part of the evidence.

The quadratic FNN brute-force route is prespecified for the three tractable datasets MetRef, COIL20, and USPS. The corresponding faissR exact job runs all nine datasets, but the paired exhaustive analysis uses only datasets completed by both interfaces. This restriction is part of the design rather than a post hoc deletion of slow cells.

The experiment is an end-to-end public-API comparison. The external configurations and effective thread controls are written into each result row. It is not presented as a microbenchmark of the underlying algorithms.

The ratio is `external_time / faissR_time`; values greater than one favor
faissR. Pairing is analytical matching by dataset, metric, `k`, validation seed,
and repeat. Because each method-metric combination is submitted as a separate
one-method Slurm job, same-node execution is not guaranteed and cross-method
order is not randomized. Each timed call uses a fresh R worker. Dataset and
reference loading occur before timing, `gc()` is called immediately before the
timer, and neither an untimed search warm-up nor an operating-system cache flush
is performed.

The audit emits two views for approximate-method comparisons. The
prespecified-interface view includes every successful paired replicate. The
point-recall-matched view retains a dataset-metric-`k` cell only when both routes
achieve mean recall@`k` of at least 0.99 in every validation replicate. Observed
recall for both routes remains in the paired output; speed is never interpreted
as an algorithm comparison when this equivalence criterion is not met.

After synchronizing this directory to `/scratch/firenze/NN/benchmark_scripts/jss_reproduction/validation/external_r_comparison`, submit from an HPC compute or interactive node:

```bash
cd /scratch/firenze/NN

export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda_faissR_0.99.21_0903532_20260806.sif
export EXPECTED_FAISSR_VERSION=0.99.21
export FAISSR_PACKAGE_COMMIT=0903532baf02b340a90921db18edc4deae5ea462
export SINGULARITYENV_FAISSR_IMAGE_COMMIT="$FAISSR_PACKAGE_COMMIT"
export APPTAINERENV_FAISSR_IMAGE_COMMIT="$FAISSR_PACKAGE_COMMIT"

bash benchmark_scripts/jss_reproduction/validation/external_r_comparison/submit_external_r_comparison.sh
```

The submission helper launches 12 independent method-metric jobs and one `afterany` audit. `afterany` is intentional: the audit must report missing and failed jobs instead of disappearing behind an unsatisfied dependency.
