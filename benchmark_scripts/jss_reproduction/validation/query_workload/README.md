# Query-workload validation

This focused experiment tests how query workload affects route selection and
elapsed time. It is not another parameter-tuning campaign. The fixed operating
point is Euclidean distance, `k = 30`, and target recall 0.99.

The CPU and CUDA launchers evaluate `m = 1, 32, 1024` explicit query rows on
five representative datasets. Full self-search (`m = n`) is additionally run
for MetRef, COIL20, and MNIST. The sampled query rows come from the audited
exact-reference row set and are unique; MetRef therefore uses 873 rows for a
request of 1,024. Known self-identifiers are removed before recall is computed.

For each method, package fitted-index caches are cleared before the first call.
Method order is randomized reproducibly within each query workload, while all
methods for one dataset/backend run in the same Slurm allocation and node.
The first call is labeled `cold`; two identical calls are labeled
`warm_repeated_query`. The audit reports cold time, median warm-query time, the
explicit estimate `max(0, cold - warm)` for construction, and amortized totals
`cold + (A - 1) * warm` for 1, 10, and 100 batches. The estimated construction
component is deliberately not described as a directly instrumented provider
timer.

The experiment measures the present selector contract: query count and
self/external-query mode are inputs, but expected future reuse is not. It does
not modify the installed automatic policy.

Submit from an HPC compute or interactive node:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=b33a70116887474a2ed70d84de0c80bb77e9db66
bash benchmark_scripts/jss_reproduction/validation/query_workload/submit_query_workload.sh
```

The CPU and CUDA audits are separate so a GPU scheduling or capability failure
cannot obscure a completed CPU workload experiment.
