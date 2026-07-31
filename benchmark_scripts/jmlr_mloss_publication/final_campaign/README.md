# Final JSS HPC campaign

This directory contains separate Slurm launchers. Do not submit the whole
tree blindly. Each `.sh` file is an independent job with the established
CPU or CUDA header.

`submit_campaign.R` is the single commented HPC submission entry point. It
does not replace or merge launchers: it validates the image identity and
submits one existing `.sh` file at a time for one explicitly selected phase.
It never advances automatically to the next phase.

## Fixed campaign

- Real datasets: `COIL20`, `USPS`, `FashionMNIST`, `FlowRepository_FR-FCM-ZYRM_files`, `flow18`, `MNIST`, `imagenet`, `MetRef`, `mass41`.
- TabulaMuris is excluded from the manuscript campaign.
- Metrics: Euclidean, cosine, correlation, and inner product where supported.
- k: 15, 30, 50, and 100.
- Recall targets: 0.90, 0.95, and 0.99.
- Calibration seed: 4. Held-out seeds: 20260706 and 20260807.
- Three held-out timing repetitions; 2000-second timeout.
- Input manifests point to float32 datasets.
- Generated calibration, reference, held-out, and reusable-index computation
  launchers require the exact faissR version read from `DESCRIPTION` and stop
  before loading data if the Singularity image contains another version.
- The frozen image must contain `Rnanoflann`, `RANN`, `RcppAnnoy`, `RcppHNSW`,
  `rnndescent`, `BiocNeighbors`, `FNN`, `nabor`, and `uwot`; each external
  CPU launcher fails during preflight when its required package is absent.
- Before timed jobs are accepted, CPU/CUDA route QA inventories comparator
  versions and checks the exact installed `faissR` version. CUDA QA also
  requires CUDA, FAISS-GPU, and cuVS and proves that `nn_gpu()` accepts a
  direct `float::fl()` input and returns device pointers with
  `result_residency = "cuda"`, zero host copies, and no compatibility
  double-to-float conversion.
- Route QA uses self-query calls for grid, NN-descent, NSG, and Vamana,
  separate-query calls elsewhere, and `float::fl()` inputs throughout. It
  records capability-declared unsupported method/metric cells without
  misclassifying them as runtime failures.
- CPU route QA executes a small public-API contract fixture for every eligible
  external comparator and checks dimensions, finite sorted distances, and
  self-neighbor exclusion. A package without an exported standalone KNN API
  is recorded as `not_public_api` rather than timed through package internals.
- Route-QA archives retain the Singularity SHA-256 digest and file metadata;
  CUDA QA also records the visible NVIDIA devices.
- `uwot` and `cuda.ml` are API-audit rows, not timed self-KNN comparators:
  the installed `uwot` API exposes no standalone KNN result, while
  `cuda.ml` returns supervised prediction models.

## Required order

1. Run the image/version/commit preflight at the top of
   `submission_commands.txt`, export the reported `FAISSR_PACKAGE_COMMIT`, and
   submit both CPU/CUDA package route-QA jobs. Stop unless both pass.
2. Audit existing exact references and calibration evidence. Regenerate only
   rows that fail the version, commit, fingerprint, metric, seed, or query-row
   checks.
3. If calibration changes a compiled policy, commit the change, regenerate
   these launchers, rebuild the image, and repeat step 1. Held-out timings from
   an earlier image are not eligible.
4. Submit each launcher under `held_out/cpu/` and `held_out/cuda/` using the
   validated frozen image.
5. Submit the reusable external-index jobs, low-dimensional ablations, and
   metric-conformance jobs.
6. Submit the held-out, reusable-index, conformance, and ablation analysis
   jobs.
7. Run the strict freeze audits with `FAISSR_PACKAGE_COMMIT` set to the
   immutable commit embedded in the rebuilt image.

Held-out validation must never be reused to alter tuning policies.

## Typical submission

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda_faissR_0.99.19.sif
export EXPECTED_FAISSR_VERSION='0.99.20'

# Run the preflight block at the top of submission_commands.txt. It defines
# FAISSR_PACKAGE_COMMIT only after checking the installed version and embedded
# commit. Then submit these two jobs and inspect their reports before continuing.
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/qa/run_package_route_qa_cpu12.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/qa/run_package_route_qa_cuda.sh
```

The equivalent guarded entry point is:

```bash
Rscript benchmark_scripts/jmlr_mloss_publication/final_campaign/submit_campaign.R --phase=list
Rscript benchmark_scripts/jmlr_mloss_publication/final_campaign/submit_campaign.R --phase=qa
```

After inspecting a phase's reports, submit the next phase explicitly in this
order: `references`, `calibration`, `calibration_audit`, `held_out`,
`diagnostics`, `aggregate`, and `freeze`. Use `--dry-run` to print every
`sbatch` command without accessing the image or submitting work. Every live
submission writes a CSV ledger containing the launcher, Slurm job identifier,
image path, package version, and embedded package commit.

The image filename is a deployment label and is not accepted as package
identity. The preflight reads `packageVersion("faissR")` inside the image
and the embedded 40-character `FAISSR_IMAGE_COMMIT`; both must match the
frozen campaign even when the filename contains an older version string.

All evidence is written below
`/scratch/firenze/NN/faissR_JMLR_MLOSS/final_campaign/`.
