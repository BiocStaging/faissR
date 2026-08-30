# JSS Replication Suite

This directory contains the computational replication suite for the
*Journal of Statistical Software* article. Outputs are written below
`faissR_JSS_REPRODUCTION` unless an explicit output directory is supplied.

The original method-by-method calibration and validation launchers remain in
`cpu/`, `cuda/`, `calibration/`, and `final_campaign/`. The publication-facing
experiments added after that campaign are organized by scientific question in
`validation/`. Submit them through
`validation/publication_campaign/submit_publication_campaign.sh`; its final
audit checks that every required report is present and passing.

## Resource headers

CPU files retain the established CPU resources: account `immunology`,
partition `ada`, one node, 12 tasks, and 48 hours. CUDA files retain account
`l40sfree`, partition `l40s`, one node, two tasks, one L40S GPU, and 48 hours.
Only the job name and log filename vary by method.

## Files

- `references/run_exact_references_cuda.sh`: preferred fast CUDA exact
  references, with an independent CPU FAISS Flat audit before saving.
- `references/run_exact_references_cpu12.sh`: slower CPU-only alternative.
- `cpu/`: one independent-query publication benchmark file per CPU method or external
  R-package method.
- `cuda/`: one independent-query publication benchmark file per CUDA method.
- `common/`: shared R drivers required by the individual Slurm files.
- `validation/`: metric conformance, selector sensitivity, controlled
  comparisons, publication figures, provenance, and checksummed snapshot jobs.
- `validation/gpu_resident_interoperability/`: isolated CUDA residency,
  transfer, memory, lifetime, and downstream C-callable consumer audit.
- `validation/recall_inference/`: focused CPU/CUDA automatic-policy audit with
  tie-aware recall and query-bootstrap lower confidence bounds.
- `validation/resource_memory/`: isolated-process host and device memory
  measurements, including failed and out-of-memory cells.
- `validation/publication_campaign/`: phase-based submission and final evidence
  audit for the additional JSS experiments.
- `final_campaign/`: the complete independent-job campaign and its precise
  run order used to generate the original calibration evidence.

## Run One By One

First submit the CUDA reference job and wait until it finishes:

```bash
cd /scratch/firenze/NN
sbatch benchmark_scripts/jss_reproduction/references/run_exact_references_cuda.sh
```

Use `run_exact_references_cpu12.sh` instead only when a CUDA node is not
available. Both scripts create the same reference filenames; the CUDA script
saves a result only after its CPU audit passes. The audit uses up to 64
queries and automatically reduces that count for very large datasets to keep
the independent CPU check near five billion distance operations.
After using the calibration results to update `tuning = "auto"` and rebuilding
the Singularity image, submit publication methods individually:

```bash
sbatch benchmark_scripts/jss_reproduction/cpu/run_faissR_hnsw_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/cpu/run_RANN_kd_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/cuda/run_faissR_cagra_cuda.sh
sbatch benchmark_scripts/jss_reproduction/cuda/run_faissR_gpu_resident_exact_cuda.sh
```

All files in `cpu/` and `cuda/` are independent jobs. Submit each file once.
Do not combine CPU and CUDA methods in one Slurm job, and do not reuse
calibration output as independent-query validation.

After the one-method jobs finish, aggregate CPU and CUDA evidence separately:

```bash
sbatch benchmark_scripts/jss_reproduction/analysis/run_aggregate_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/analysis/run_aggregate_cuda.sh
```

The aggregator selects the newest run for each method and suite, requires two
validation seeds and three repetitions, and ranks a method only when every
measured run reaches the requested recall. It writes fastest and second-fastest
qualifying methods, exact baselines, `method = "auto"` versus the oracle method,
recall-compliance counts, failures, and successful route mismatches.

Timing comparisons are paired before summarization. The aggregator writes
cell-level pairs, one median ratio per dataset, and an across-dataset summary
in `jss_paired_performance_cells.csv`,
`jss_paired_performance_by_dataset.csv`, and
`jss_paired_performance_summary.csv`. External ratios are comparator time over
faissR-auto time. The dedicated selector analysis defines feasible-route regret
as selected-route time over the fastest target-eligible empirical-route time,
including the selected route itself. Each dataset
has equal weight in the final median, IQR, and range, while incomplete pairs,
timeouts, and out-of-memory events remain explicit.

The same aggregate pass performs a descriptive selection-stability audit. It
reconstructs the fastest eligible explicit faissR route within every
validation seed and timing repeat, collapses exhaustive aliases resolving to
the same provider, and writes
`jss_selection_stability_replicates.csv`,
`jss_selection_stability_cells.csv`, and
`jss_selection_stability_summary.csv`. Modal-route frequency, route-switch
frequency, auto/oracle agreement, target retention, runtime variation, and
auto/oracle timing ratios diagnose noisy winners. The grids are not refitted,
so these outputs do not estimate parameter-level reselection probabilities.

Run the systems ablations independently:

```bash
sbatch benchmark_scripts/jss_reproduction/ablations/run_systems_ablations_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/ablations/run_systems_ablations_cuda.sh
```

These analyses distinguish two estimands. External package timings answer the
end-to-end, user-visible public-API question. Conditional search/index
contrasts hold representation and execution phase fixed. The ablation
aggregator writes fixed-route float32/double ratios, fixed-route warm/cold
ratios, float32 cache-disabled route/Flat ratios, and a dataset-first component
summary. Ratios below one favor the numerator. Route/Flat includes index
construction, search, and result creation and is not a kernel-only algorithm
benchmark.

After the independent-query runs and ablations are complete, follow
`validation/README.md` to run the three-metric conformance suite,
automatic-selector/oracle comparison, named-dataset and grouped-domain holdout sensitivity,
publication figures, and strict archive-integrity audit.

For the additional experiments requested for the final article, first inspect
the phase list and then submit one phase at a time:

```bash
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh list
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh r_comparison
```

The remaining phases and their prerequisites are documented in
`validation/publication_experiment_order.md`. Separate submissions avoid Slurm
queue-limit failures and make each evidence block independently auditable.

The completed same-node HNSW comparison is under
`validation/paired_cpu_comparison/`. The comprehensive controlled comparison
with FNN, RANN, rnndescent, BiocNeighbors, Rnanoflann, RcppAnnoy, and RcppHNSW
is under `validation/comprehensive_r_comparison/`. Independent CPU and CUDA
automatic-policy validation is included in `validation/recall_inference/`.
These modules use version-pinned experiment snapshots; “frozen release” is
reserved for the package version accepted by Bioconductor.

`validation/paired_cpu_hnsw_pareto/` independently tunes faissR,
BiocNeighbors, and RcppHNSW on calibration queries, records recall-time curves,
and coexecutes the selected provider-specific configurations on an independent
validation seed. It is the required evidence for provider-level HNSW speed
claims; the completed fixed-configuration experiment remains explicitly
labeled as such.

`validation/recall_inference/` distinguishes the two independent validation
query seeds from the three repeated timings of each query set. Approximate
eligibility uses tie-aware recall at the kth-neighbor boundary and a one-sided
95% query-bootstrap lower confidence bound; exact-family routes retain their
separate exhaustive audit.

The leave-one-dataset-out analysis is cross-fitted at the named-dataset level:
all rows from the omitted dataset are excluded before family selection. It
writes per-cell, per-dataset, and backend/metric/target summaries of
operating-point attainment, selected/oracle time ratio, route-family agreement,
abstention, and exact selection. Exact-audited routes and approximate
target-attaining routes are distinct evidence classes. The installed
full-calibration `method = "auto"` result is reported separately and is not
used as evidence of out-of-collection generalization.
The grouped analysis prespecifies image-derived, cytometry, and metabolomics
groups and excludes every dataset in the held-out domain. Both reconstructions
use the complete explicit held-out CUDA candidate set (exact-family and CAGRA);
that set does not contain explicit IVF and therefore is not a like-for-like
reconstruction of the compiled Flat/IVF policy. Pairwise and joint route
confusion tables make this distinction machine-readable.

These jobs compare float32 and double input, cold and warm fitted-index reuse,
compiled and R-side self-neighbour removal, and GPU-resident exact search with
an explicit device-to-host copy. They use COIL20 and MNIST at `k = 30` to
cover contrasting dataset shapes without duplicating the full method grid.

Every one-method and systems-ablation launcher performs a package/backend
preflight inside the same Singularity invocation used for measurement. A stale
image or missing shared library therefore fails once with the original R load
diagnostic before method workers are launched. Systems-ablation worker output
is retained separately under `worker_logs/`.

The double-input ablation converts a `float::float32` dataset explicitly with
`float::dbl()`. Calling `as.matrix()` on a float object retains its S4 float32
class and is not a valid double-input control.

Reference files are saved in their dataset directories and reused by every
method. Synthetic data are generated only when their manifest is absent.
References and result rows include the source dataset MD5 fingerprint. A
reference with a missing or different fingerprint is rejected, even when its
matrix dimensions and `k` still match.

## Experimental Design

Each faissR publication file tests one method with `tuning = "auto"`,
`k = 15,30,50,100`, target recall 0.90/0.95/0.99, two independent-query seeds, three
repetitions, and a 2,000-second timeout per combination. Real datasets use
Euclidean, cosine, and correlation distances. Grid files run only the 2D/3D
spatial suite. External packages
run only metrics supported by their public KNN interface.

Rtsne and `umap::umap` are not included as standalone KNN methods because they
are embedding consumers rather than comparable KNN result providers.
