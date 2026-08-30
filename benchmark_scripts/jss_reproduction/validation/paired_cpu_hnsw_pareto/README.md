# Recall-matched CPU HNSW Pareto comparison

This experiment complements the prespecified-configuration comparison. It does
not replace or overwrite those results.

For `faissR`, `BiocNeighbors`, and `RcppHNSW`, calibration varies `ef.search`
across five levels for every dataset and `k`. At `k = 30`, it additionally
varies graph-construction effort (`ef.construction = 100, 200, 400`). `M` or
`nlinks` is held at 16 so the experiment remains tractable and interpretable.
Each provider's fastest configuration passing the point-recall calibration
screen (mean recall at least 0.99 in all three calibration repeats) is selected
independently. This screen is distinct from empirical query-bootstrap
validation attainment. The selected faissR
and comparator configurations are then coexecuted in the same Slurm task and
node for five repetitions using the independent validation seed.

Both routes receive the same R double matrix. Cold-call timing includes public
API conversion, graph construction, full self-search, provider output, sorting
as returned by the provider, and self-neighbor removal. faissR performs removal
in compiled code; comparator removal is part of the timed R wrapper. This is an
end-to-end API comparison, not a kernel-only comparison. The validation phase
also records matched-configuration reusable-index construction and fitted-query
timings separately. Fitted queries use the audited 1,024-query validation set,
request `k + 1`, and remove the known query row before recall is calculated.
Each fitted route runs in an isolated worker. The resident-set increase across
index construction is an empirical index-memory estimate; the R object size is
reported separately because it excludes native external-pointer storage.
Portable faissR index serialization is unsupported and receives no artificial
timing.

The raw rows record requested threads, Slurm allocation, Linux CPU affinity,
thread-control environment variables, process thread counts before/after the
call, input representation, recall, elapsed time, failures, and timeouts.
Process thread counts are observable runtime metadata, not proof that every
thread was actively computing throughout the call.

Submit from an HPC compute or interactive node:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=b33a70116887474a2ed70d84de0c80bb77e9db66
bash benchmark_scripts/jss_reproduction/validation/paired_cpu_hnsw_pareto/submit_pareto.sh
```

The audit fails if any of the 72 independent-validation result files or 720
route runs are absent. Numerical claims belong in the manuscript only after
`PARETO VALIDATION AUDIT PASSED` is produced.
