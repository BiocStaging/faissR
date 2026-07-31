# JSS experiment plan

## Purpose

The remaining experiments must support four claims and no more:

1. `faissR` returns correct neighbors under Euclidean, cosine, correlation,
   and raw inner-product contracts.
2. Recall-targeted settings achieve the requested operating point on held-out
   query samples often enough to be useful, with failures and misses reported.
3. The automatic selector is competitive with the fastest qualifying explicit
   `faissR` method without using held-out timings to alter its policy.
4. Float32 input, fitted-index reuse, compiled self-removal, batching, and GPU
   residency explain measurable systems-level differences.

The study does not need another broad calibration pass unless the audit finds a
missing calibration cell used by the compiled policy. TabulaMuris is excluded
from the manuscript campaign.

## Frozen design

- Datasets: COIL20, USPS, FashionMNIST, FlowRepository FR-FCM-ZYRM, flow18,
  MNIST, ImageNet features, MetRef, and mass41.
- Metrics: Euclidean, cosine, correlation, and raw inner product where the
  method contract supports them.
- Neighbor counts: 15, 30, 50, and 100.
- Recall targets: 0.90, 0.95, and 0.99.
- Calibration seed: 4.
- Held-out query seeds: 20260706 and 20260807.
- Timing repetitions: three per held-out seed.
- Query reference size: at most 1,024 rows, with exact references generated at
  k=100 and cropped for smaller k.
- Timeout: 2,000 seconds per method/dataset job.
- CPU allocation: 12 tasks; record effective threading separately.
- CUDA allocation: one NVIDIA L40S and two CPU tasks.
- Input: the existing float32 dataset files, without benchmark-side scaling.

## Gate 1: software and image identity

Do not run timed jobs until both route-QA launchers pass. They must show the
same `faissR` version and immutable commit used by the manuscript, inventory all
comparison packages, and record the Singularity SHA-256 digest. CUDA QA must
also prove CUDA/FAISS-GPU/cuVS availability and a true GPU-resident `nn_gpu()`
result with zero device-to-host result copies.

```bash
cd /scratch/firenze/NN
# First run the preflight block at the top of
# benchmark_scripts/jmlr_mloss_publication/final_campaign/submission_commands.txt.
# It validates the image and exports FAISSR_PACKAGE_COMMIT.
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/qa/run_package_route_qa_cpu12.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/qa/run_package_route_qa_cuda.sh
```

Stop if the installed package version differs, a required provider is absent,
or an explicit CUDA route resolves to CPU. The image is an external execution
artifact; this plan does not rebuild it.

## Gate 2: reference and calibration audit

After route QA passes, audit existing exact references and calibration outputs
before resubmitting expensive computation. A reference is reusable only when
dataset fingerprint, metric, seed, query rows, k=100, package version, package
commit, and embedded image commit agree. A compiled policy is usable only when
its candidate completed every dataset assigned to the shape group; below-target
policies must retain negative-evidence metadata.

```bash
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_calibration_audit_cpu12.sh
```

Rerun only the reference or calibration launchers named as missing by that
audit. If this changes compiled policy code, regenerate the campaign, rebuild
and revalidate the image, and discard any held-out timings from the superseded
image. Held-out rows must never be used to revise the policy in this study.

## Experiment 1: held-out faissR methods

Run every applicable explicit `faissR` method and `method="auto"` separately on
CPU and CUDA. The method set is exact, Flat, brute force, grid (2D/3D only),
HNSW, IVF, IVF-PQ, IVF-PQ FastScan, NN-descent, NSG, Vamana, and CAGRA
(CUDA only). Capability-declared unsupported cells are evidence, not failures;
runtime errors, timeouts, route mismatches, and silent fallback are failures.

Use the independent launchers under:

```text
benchmark_scripts/jmlr_mloss_publication/final_campaign/held_out/cpu/
benchmark_scripts/jmlr_mloss_publication/final_campaign/held_out/cuda/
```

Primary outputs per cell are cold end-to-end time, mean/median/minimum recall,
target attainment, rank agreement, distance error, peak host memory, route and
provider metadata, conversion path, and failure state. CUDA rows also record
result residency, transfer counts/timing, and device-memory telemetry when
available.

## Experiment 2: comparison with other R packages

The CPU comparison includes exported, task-equivalent routes from
Rnanoflann, RANN, FNN, nabor, RcppAnnoy, RcppHNSW, rnndescent, and
BiocNeighbors. `uwot` and `cuda.ml` remain API-audit rows because the frozen
public APIs do not return an equivalent standalone self-KNN result. Do not time
namespace internals or supervised prediction as a substitute.

Distance diagnostics use the `faissR` public metric scale. The adapter
converts `BiocNeighbors` cosine output from normalized Euclidean distance
to `1 - cosine` with `distance^2 / 2` inside the timed call and records the
conversion in `method_parameters`.

Use the external-package launchers in the same `held_out/cpu/` directory.
Euclidean is the common comparison metric; cosine is additionally evaluated
for RcppHNSW and eligible BiocNeighbors routes. Correlation and raw inner
product are reported for `faissR` only unless another package exposes the same
public contract. Compare cold with cold. Warm query timing is a separate
experiment and is never ranked against a one-call cold result.

## Experiment 3: build-once/query-many comparison

Run the nine launchers under:

```text
benchmark_scripts/jmlr_mloss_publication/final_campaign/reusable_external/
```

They compare public reusable-index APIs for RcppAnnoy, RcppHNSW, and
BiocNeighbors. Report construction, first sampled query, and three repeated
sampled-query timings separately. Use the same held-out reference query rows;
do not present sampled-query timing as an all-row self-search time.

Then run:

```bash
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_reusable_external_audit_cpu12.sh
```

## Experiment 4: systems ablations

Use the existing CPU and CUDA ablation jobs to estimate paired effects for:

- base double versus `float::fl()` input;
- cache disabled, cache-enabled cold, and cache-enabled warm calls;
- R-side versus compiled self-neighbor removal;
- host materialization versus GPU-resident exact output.

The existing archive already contains 92 eligible CPU and 124 eligible CUDA
measurements. Rerun only if the package version or dataset fingerprint differs
from the held-out campaign. Analyze with:

```bash
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_ablation_audit_cpu12.sh
```

## Experiment 5: aggregate and test the selector

After all held-out launchers finish, submit:

```bash
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_held_out_analysis_cpu12.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_held_out_analysis_cuda.sh
```

For each dataset/backend/metric/k/target cell, define the empirical oracle as
the fastest explicit `faissR` method that completed all six held-out timings
(two seeds times three repeats) and met the target in every repeat. Report:

- automatic-selector target attainment;
- auto/oracle cold-time ratio;
- recall difference;
- resolved-method/provider agreement;
- abstention or exact-selection rate;
- leave-one-dataset-out sensitivity.

The overall cross-package winner is a separate Euclidean/cosine comparison and
does not redefine the internal `faissR` oracle.

## Statistical summaries

The dataset is the unit for cross-method conclusions. Report median and IQR
across timing repetitions within each dataset cell, then summarize target
attainment and completion across datasets. Do not treat query rows as
independent experimental replicates. Report all eligible datasets, timeouts,
unsupported routes, and failures; avoid a complete-case-only league table.

For paired systems ablations, report the within-cell time or memory ratio and a
dataset-level paired summary. For method rankings, show the fastest and second
fastest qualifying method plus an exact baseline. Exact-family routes that
resolve to the same provider count as one mathematical algorithm, although
their wrapper overhead remains visible.

## Final freeze

Run the strict CPU and CUDA freeze audits only after the held-out analyses have
completed and set `FAISSR_PACKAGE_COMMIT` to the immutable 40-character commit
inside the validated image:

```bash
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_freeze_audit_cpu12.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/analysis/run_freeze_audit_cuda.sh
```

The manuscript can make comparative speed claims only after both audits pass
and the resulting tables are regenerated by
`manuscript/jss/replication_article.R` from the frozen archive.
