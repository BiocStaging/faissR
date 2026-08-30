# Controlled external CPU comparisons

This module provides the remaining external comparisons used by the JSS
evaluation. It is separate from the completed controlled HNSW module because
the provider contracts differ.

Together, the two controlled modules cover the three representative families
needed for the article: exhaustive search (`FNN`), HNSW (`BiocNeighbors` and
`RcppHNSW`, already completed), and NN-descent (`rnndescent`). Other interfaces
surveyed in the article are documented in the software-capability comparison;
they are not treated as interchangeable timing replicates when their algorithm,
metric, or returned-object contract differs.

- `exact_FNN` compares exhaustive Euclidean calls from `faissR` and
  `FNN::get.knn(algorithm = "brute")` on the three prespecified tractable
  datasets. Successful cells are labeled exhaustive-provider pairs, not ANN
  target successes.
- `nndescent_rnndescent` compares the package-owned NN-descent-derived route
  with `rnndescent::nnd_knn()` for Euclidean, cosine, and correlation distance.
  Speed summaries require both routes to attain mean recall@k of at least 0.99
  in every prespecified validation replicate.

Each dataset-by-k task runs both routes in one Slurm allocation and on one node.
The first route is selected deterministically from the validation seed and the
order alternates over three repeats. Every timed call runs in an isolated R
worker after an untimed 128-row warm-up. The recorded ratio is
`T_external / T_faissR`, so values above one favor `faissR`.

The four method/metric launchers are intentionally separate. The submission
helper schedules them and an `afterany` audit, preserving failures and timeouts
as evidence rather than silently dropping them.

```bash
cd /scratch/firenze/NN

export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=b33a70116887474a2ed70d84de0c80bb77e9db66

bash benchmark_scripts/jss_reproduction/validation/paired_external_cpu_comparison/submit_paired_external_cpu.sh
```

The submission helper first runs `preflight_paired_external_cpu.sh` inside the
same image. No Slurm job is submitted unless the image contains the expected
`faissR`, `FNN`, and `rnndescent` packages and the benchmark inputs are visible.
