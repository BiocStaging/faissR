# Final JSS HPC campaign

This directory contains separate Slurm launchers. Do not submit the whole
tree blindly. Each `.sh` file is an independent job with the established
CPU or CUDA header.

## Fixed campaign

- Real datasets: `COIL20`, `USPS`, `FashionMNIST`, `FlowRepository_FR-FCM-ZYRM_files`, `flow18`, `MNIST`, `imagenet`, `MetRef`, `mass41`.
- TabulaMuris is excluded from the manuscript campaign.
- Metrics: Euclidean, cosine, correlation, and inner product where supported.
- k: 15, 30, 50, and 100.
- Recall targets: 0.90, 0.95, and 0.99.
- Calibration seed: 4. Held-out seeds: 20260706 and 20260807.
- Three held-out timing repetitions; 2000-second timeout.
- Input manifests point to float32 datasets.
- The frozen image must contain `Rnanoflann`, `RANN`, `RcppAnnoy`,
  `rnndescent`, `BiocNeighbors`, `FNN`, `nabor`, and `uwot`; each external
  CPU launcher fails during preflight when its required package is absent.
- `cuda.ml` is an API-audit row, not a timed self-KNN comparator, because
  its public interface returns supervised prediction models.

## Required order

1. Submit the four metric-separated real reference launchers and
   `references/run_synthetic_references_cuda.sh`.
2. Submit every required launcher under `calibration/real/` and
   `calibration/mips/`.
3. Submit `analysis/run_calibration_audit_cpu12.sh` and inspect missing
   cells and negative evidence.
4. Update and freeze the compiled C++ tuning policies from calibration only,
   commit faissR, and rebuild the Singularity image.
5. Submit each launcher under `held_out/cpu/` and `held_out/cuda/`.
6. Submit the reusable external-index jobs, low-dimensional ablations,
   metric-conformance jobs, and CPU/CUDA package route-QA jobs.
7. Submit the held-out, reusable-index, and ablation analysis jobs.
8. Run the strict freeze audits with `FAISSR_PACKAGE_COMMIT` set to the
   immutable commit embedded in the rebuilt image.

Held-out validation must never be reused to alter tuning policies.

## Typical submission

```bash
cd /scratch/firenze/NN
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_euclidean.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_cosine.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_correlation.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_real_references_cuda_inner_product.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/references/run_synthetic_references_cuda.sh

# Submit jobs one by one, for example:
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/calibration/real/cpu/run_tune_faissR_hnsw_cpu12_euclidean_real.sh
sbatch benchmark_scripts/jmlr_mloss_publication/final_campaign/calibration/real/cuda/run_tune_faissR_cagra_cuda_euclidean_real.sh
```

All evidence is written below
`/scratch/firenze/NN/faissR_JMLR_MLOSS/final_campaign/`.
