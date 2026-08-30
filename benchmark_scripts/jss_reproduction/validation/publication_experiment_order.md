# Publication experiment order

The route-contract tests and the first same-node HNSW comparison are complete.
They should not be rerun merely because this plan was updated. The following
modules produce the additional evidence requested for the final JSS analysis.

## Phase A: independent policy and comparator validation

1. `comprehensive_r_comparison/`: same-node comparison with FNN, RANN,
   rnndescent, BiocNeighbors, Rnanoflann, RcppAnnoy, and RcppHNSW.
2. `paired_cpu_hnsw_pareto/`: independently calibrated, recall-matched HNSW
   Pareto comparison for faissR, BiocNeighbors, and RcppHNSW.
3. `recall_inference/`: installed CPU and CUDA automatic policies on two
   independent query seeds, with tie-aware recall and lower confidence bounds.

These phases resolve the empirical scope of CPU auto and broaden the external
R comparison without mixing independently scheduled timings.

## Phase B: workload and timing stability

4. `query_workload/`: query counts 1, 32, 1,024, and full self-search; cold and
   repeated calls; estimated construction and amortized totals.
5. `calibration_confirmation/`: five isolated, randomized timings for the
   prespecified shortlist from each calibration cell.

The original wide calibration grid remains a screening experiment. The
confirmation module quantifies winner's-curse sensitivity without silently
replacing the installed package policy.

## Phase C: memory and GPU interoperability

6. `resource_memory/`: fresh-process host `VmHWM`, retained-memory increment,
   result footprint, process GPU peak, failures, OOMs, and timeouts.
7. `gpu_resident_interoperability/`: device-side consumer, explicit host-copy
   time, ownership/lifetime metadata, and memory after garbage collection.

Host and device memory remain separate estimands. GPU-resident continuation is
not compared directly with a host-resident route as if they had identical
output contracts.

## Phase D: archive-only analyses

After the held-out archive and the phases above pass their audits:

8. Run `analysis/analyze_failure_aware_profiles.R` on the robust method summary.
9. Run grouped leave-one-domain-out, route-confusion, selector-regret, and
    per-dataset analyses from the explicit held-out archive.
10. Regenerate tables and figures only from the version-pinned evidence root.

Failure-aware profiles keep timeout, OOM, unsupported, and failed cells in the
denominator. Their capped-runtime result is a prespecified sensitivity analysis,
not an observed completion time.

## Submission

Export one image/version/commit identity and submit phases separately:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=<version-inside-image>
export FAISSR_PACKAGE_COMMIT=<40-character-commit-inside-image>

bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh list
bash benchmark_scripts/jss_reproduction/validation/publication_campaign/submit_publication_campaign.sh r_comparison
```

Continue with the other phases listed by the command only after checking the
previous phase's audit and Slurm status. This avoids exceeding the cluster's
submission and GPU concurrency limits.
