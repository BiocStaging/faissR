# JSS Publication Validation Runs

`PUBLICATION_EVIDENCE_MATRIX.md` maps every required scientific claim to its
experiment, archive-only analysis, or documentation change. New experiments
should be submitted phase by phase through `publication_campaign/`.

These jobs provide the validation evidence for the JSS article. They extend
the held-out suite; they do not replace the one-method CPU and CUDA jobs in
`../cpu/` and `../cuda/`.

All launchers preserve the established HPC headers. CPU jobs use account
`immunology`, partition `ada`, one node, 12 tasks, and 48 hours. CUDA jobs use
account `l40sfree`, partition `l40s`, one node, two tasks, one L40S GPU, and 48
hours. Every R process runs inside the configured Singularity image.

## Required run order

Run commands from `/scratch/firenze/NN`.

The active evaluation set contains nine real datasets and excludes
TabulaMuris. Historical refresh output remains archived but is not required
for the article or its aggregate tables.

### 1. Complete held-out method evidence

The original publication suite already supplies one Slurm file per method.
Submit every applicable file separately. Do not combine methods in a job and
do not use calibration rows as held-out evidence.

```bash
for f in benchmark_scripts/jss_reproduction/cpu/*.sh; do echo "sbatch $f"; done
for f in benchmark_scripts/jss_reproduction/cuda/*.sh; do echo "sbatch $f"; done
```

Each faissR method tests Euclidean, cosine, and correlation;
`k = 15, 30, 50, 100`; recall targets 0.90, 0.95, and 0.99; two held-out
seeds; three repetitions; and a 2,000-second timeout. Failures, unsupported
combinations, and timeouts remain in the evidence archive.

### 2. Metric contracts

```bash
sbatch benchmark_scripts/jss_reproduction/validation/run_metric_conformance_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/validation/run_metric_conformance_cuda.sh
```

The jobs test all public NN method families against direct mathematical
references. They check smaller-is-better returned distance order, descending
positive-scale invariance, correlation positive-affine invariance, output
shape, finite distances, and resolved CPU/CUDA route identity. Zero-norm cosine
and constant-row correlation cases are tested separately: a finite result on
the requested backend passes, and a documented CUDA error that explicitly
refuses CPU-side repair also passes. Unexpected errors and silent backend
changes fail. Exact, Flat, and brute-force cells are fatal when a contract
fails; explicitly unsupported approximate combinations are retained in the
CSV.

### 3. Systems ablations

```bash
sbatch benchmark_scripts/jss_reproduction/ablations/run_systems_ablations_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/ablations/run_systems_ablations_cuda.sh
```

These paired jobs measure float32 versus double input, cache-disabled versus
cold/warm fitted-index reuse, compiled versus R self-neighbour removal, and
GPU-resident search versus an explicit host copy. CUDA rows now record sampled
per-process GPU memory from `nvidia-smi` at 100-ms intervals. Provider calls
are treated as the completion barrier; explicit result copies are timed in
`host_copy_sec` and excluded from GPU-resident search time.

### 4. Automatic selector, empirical oracle, and LOODO sensitivity

Run these only after all held-out method jobs are complete:

```bash
sbatch benchmark_scripts/jss_reproduction/validation/run_selector_validation_cpu12.sh
sbatch benchmark_scripts/jss_reproduction/validation/run_selector_validation_cuda.sh
```

Each job rebuilds the robust evidence table, compares the version-pinned
`method = "auto"` result with the fastest qualifying explicitly requested
method, and performs cross-fitted leave-one-dataset-out (LOODO) sensitivity
analysis. For a held-out dataset, every row from that dataset is removed before
the analysis selects a method family using the remaining datasets in the same
predeclared shape group. If that group is absent, it uses the three nearest
datasets in log(n)-log(p) space. Coverage is maximized before median log runtime
is minimized. The held-out dataset is used only for evaluation.

The LOODO outputs report, per held-out dataset, operating-point attainment,
selected/oracle time ratio, route-family agreement, abstention frequency, and
exact-selection frequency. Exact-audited selections are kept separate from
approximate target attainment. The installed full-calibration `method =
"auto"` result is retained in separate `package_auto_*` columns as a
non-independent diagnostic; it is not presented as LOODO evidence and this
analysis never edits the compiled selector.

`../analysis/analyze_grouped_leave_domain_out.R` repeats the exclusion at the
prespecified domain level: all image-derived, all cytometry, or the metabolomics
dataset is omitted before selection. The complete explicit held-out CUDA
candidate universe contains exact-family routes and CAGRA but not explicit IVF.
The generated route-confusion tables therefore compare recorded decisions
without attributing the compiled-policy IVF versus cross-fitted CAGRA change to
cross-fitting itself.

The same jobs create PDF speed-recall and auto-oracle figures plus their exact
CSV plotting data.

### 5. Query-workload sensitivity

The focused `query_workload/` module holds metric, `k`, and recall target fixed
while varying the number and type of queries. It records cold calls, repeated
calls against package index caches, selected routes, recall, and transparent
amortized totals for 1, 10, and 100 batches. It includes `m = 1, 32, 1024` on
five representative datasets and full self-search on three tractable datasets.
These measurements are validation evidence and are not fed back into the
compiled automatic policy.

### 6. Replicated timing, recall inference, memory, and interoperability

The publication extension is organized under scientific module names:

- `calibration_confirmation/` retimes a prespecified candidate shortlist five
  times in isolated workers and reports configuration/method stability and
  one-run selection regret;
- `recall_inference/` applies tie-aware recall and a one-sided query-bootstrap
  lower confidence bound without treating timing repetitions as independent
  recall evidence;
- `paired_cpu_hnsw_pareto/` independently calibrates each HNSW provider before
  same-node validation;
- `paired_external_cpu_comparison/` adds FNN and rnndescent comparisons;
- `resource_memory/` measures each route/workload/repetition in a fresh R
  worker, making process `VmHWM` valid per cell and sampling GPU memory by PID;
  and
- `gpu_resident_interoperability/` quantifies device-side continuation and the
  cost of explicit host materialization.

Use `publication_campaign/submit_publication_campaign.sh` as the public
submission entry point. Submit phases separately to respect cluster limits.

### 7. Dataset provenance and immutable freeze

Copy `dataset_provenance_jss_template.csv` to
`/scratch/firenze/NN/Data/dataset_provenance_jss.csv` and fill every field,
including the actual acquisition date. Redistribution is resolved as `yes` or
`no`; unresolved or unknown placeholders are forbidden. A `no` row
means that the converted matrix is excluded from the replication archive and
must be reconstructed from the recorded source/release or accession. Follow
`DATA_ACQUISITION.md`, then verify all local files before running the audits:

```bash
Rscript benchmark_scripts/jss_reproduction/common/verify_publication_datasets.R \
  --provenance=/scratch/firenze/NN/Data/dataset_provenance_jss.csv \
  --data-root=/scratch/firenze/NN
```

Do not infer permission from a software-package license when the underlying
dataset terms are unstated. Then set the exact faissR commit embedded in the
container and run both audits:

```bash
export FAISSR_PACKAGE_COMMIT=<40-character-faissR-git-commit>
sbatch --export=ALL benchmark_scripts/jss_reproduction/validation/run_freeze_audit_cpu12.sh
sbatch --export=ALL benchmark_scripts/jss_reproduction/validation/run_freeze_audit_cuda.sh
```

The audit is intentionally strict. It fails when a dataset is missing, a
result fingerprint does not match the current file, provenance is incomplete,
or the package commit/container SHA-256 is absent. The output also records
`sessionInfo()`, faissR backend information, CPU/GPU inventory, and checksums.

## Evidence map

| Scientific question | Evidence-producing code |
|---|---|
| Held-out CPU/CUDA methods, metrics, k, recall | `../cpu/`, `../cuda/`, and `../common/benchmark_jmlr_tuned_methods.R` |
| Paired faissR-auto versus external comparators and empirical oracle | `run_selector_validation_*.sh` and `../analysis/aggregate_publication_results.R` |
| Installed and cross-fitted feasible-route regret | `../analysis/analyze_selector_regret.R` |
| Three-metric conformance | `run_metric_conformance_*.sh` |
| CPU/CUDA systems ablations and GPU memory | `../ablations/` and `../common/benchmark_jss_systems_ablations.R` |
| Leave-one-dataset-out sensitivity | `../analysis/analyze_leave_one_dataset_out.R` |
| Grouped leave-one-domain-out sensitivity | `../analysis/analyze_grouped_leave_domain_out.R` |
| Query count, query mode, and repeated-index use | `query_workload/` |
| Tied-boundary recall and query-sampling uncertainty | `recall_inference/` and `../analysis/analyze_recall_inference.R` |
| Replicated timing, selection stability, and one-run regret | `calibration_confirmation/` |
| Independently tuned CPU HNSW Pareto comparison | `paired_cpu_hnsw_pareto/` |
| GPU-resident downstream continuation and explicit transfer | `gpu_resident_interoperability/` |
| Isolated per-cell host/device memory and OOM accounting | `resource_memory/` |
| Failure-aware and capped-runtime profiles | `../analysis/analyze_failure_aware_profiles.R` |
| Speed-recall and dataset-level paired log-ratio figures | `../analysis/build_publication_figures.R` |
| Provenance and immutable freeze | `run_freeze_audit_*.sh` and `../analysis/audit_publication_freeze.R` |

## Output root

New validation outputs are written below:

```text
/scratch/firenze/NN/faissR_JSS_REPRODUCTION/validation/
```
