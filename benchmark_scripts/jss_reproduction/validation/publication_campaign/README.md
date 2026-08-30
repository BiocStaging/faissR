# JSS publication evidence campaign

This directory is the public entry point for the additional experiments used
to strengthen the JSS article. Folder and output names describe scientific
questions rather than editorial history.

## Required identity

Run from an HPC compute or interactive node in `/scratch/firenze/NN`:

```bash
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=<version-inside-image>
export FAISSR_PACKAGE_COMMIT=<40-character-commit-inside-image>
```

The scripts stop when these values are absent. Use one unchanged image for the
entire campaign.

## Phases

```bash
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh list
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh all
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh r_comparison
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh hnsw_pareto
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh query_workload
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh calibration_confirmation
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh recall_inference
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh gpu_interoperability
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh resource_memory
```

`recall_inference` is the definitive independent-query validation of both the
CPU and CUDA installed automatic policies. It supersedes the older standalone
CPU-auto array by adding tie-aware recall and lower confidence bounds, so the
two modules should not both be submitted.

Submit phases separately. This respects Slurm submission and GPU concurrency
limits and makes failed phases easy to resume without duplicating completed
evidence. `r_comparison` requires FNN, RANN, rnndescent, BiocNeighbors,
Rnanoflann, RcppAnnoy, and RcppHNSW; `hnsw_pareto`
requires `BiocNeighbors` and `RcppHNSW`; GPU phases require the package's CUDA
capability.

`failure_profiles` is an analysis phase, not a benchmark. After the ordinary
held-out analysis has generated `jss_robust_method_summary.csv`, export its
absolute path and submit:

```bash
export ROBUST_METHOD_SUMMARY=/scratch/firenze/NN/.../jss_robust_method_summary.csv
sbatch benchmark_scripts/jss_reproduction/validation/run_failure_aware_profiles_cpu12.sh
```

Grouped leave-one-domain-out and route-confusion analyses likewise reuse the
explicit held-out archive and do not require rerunning nearest-neighbor search.

`calibration_confirmation` reuses the completed screening archive. Before
submitting that phase, set `CALIBRATION_RESULTS_ROOT` to its absolute
`calibration/real` directory. The path is deliberately explicit so an older or
partial archive cannot be selected silently.

## Unattended complete campaign

Schedulers may count every array element against the per-user submission
limit. Submitting all phases at once can therefore fail partway through a
module. `submit_complete_campaign.sh` is the quota-safe entry point for a new
complete run. It stages all seven scientific modules, splits the 504- and
324-cell arrays into at most 108 submitted elements at a time, and advances by
dependent controller jobs. The user does not need to return between phases.

```bash
export CALIBRATION_RESULTS_ROOT=/scratch/firenze/NN/faissR_JMLR_MLOSS/final_campaign/calibration/real
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_complete_campaign.sh
```

The campaign ledger is written below
`faissR_JSS_REPRODUCTION/submissions/complete_<campaign-id>/`. Each module
retains its own scientific audit; the controller continues after an audit job
finishes so that a failed module remains visible without suppressing later
evidence collection.

## Evidence activation rule

A submitted or completed Slurm job is not sufficient. Numerical claims enter
the manuscript only after the module audit succeeds, its raw result manifest
is complete, and the package/image identity agrees across modules. Run the
campaign audit after copying all output directories under one synchronized
`faissR_JSS_REPRODUCTION` root:

```bash
Rscript benchmark_scripts/jss_reproduction/validation/publication_campaign/audit_publication_campaign.R \
  --root=/scratch/firenze/NN/faissR_JSS_REPRODUCTION \
  --out_dir=/scratch/firenze/NN/faissR_JSS_REPRODUCTION/campaign_audit
```
