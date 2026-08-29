# Controlled paired CPU comparison

This experiment replaces analytically paired timings from separate Slurm jobs
for the primary CPU HNSW comparison. Each Slurm array task fixes one dataset,
one `k`, and one comparator. `faissR_hnsw` and the comparator therefore run in
the same allocation and on the same node.

The design includes nine datasets, `k = 15, 30, 50, 100`, two independent
validation-query seeds, five paired timing repetitions, and two comparators:
`BiocNeighbors_hnsw` and `RcppHNSW_hnsw`. Within each validation seed, the
first route is selected reproducibly at random and route order alternates over
repetitions. Every route repetition runs in a fresh R child process. Dataset
and reference loading are outside the timers; an untimed 128-row API warm-up
precedes measurement, and the faissR index cache is then cleared.

Three quantities are kept separate:

1. end-to-end cold one-shot self-KNN time;
2. reusable-index build time; and
3. fitted-index query time for the 1,024 prespecified validation queries.

Both routes receive the same R double matrix. This controls representation for
the paired algorithm/provider comparison; separate system ablations quantify
faissR's float32 input advantage. Mean recall@k and minimum query recall are
recorded for both cold and fitted results. A speed ratio is always
`T_comparator / T_faissR`, so values above one favor faissR.

Euclidean distance is the primary reusable-index comparison because all three
interfaces expose the required fitted-index operation. Cosine one-shot results
from separate jobs are not used for headline paired speed claims.

Submit from an HPC compute or interactive node after synchronizing the suite:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/path/to/frozen_faissR_image.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=<40-character-commit-embedded-in-image>

PAIR_JOB=$(sbatch --parsable \
  benchmark_scripts/jss_reproduction/validation/paired_cpu_comparison/run_paired_hnsw_cpu12.sh)

sbatch --dependency=afterany:${PAIR_JOB} \
  benchmark_scripts/jss_reproduction/validation/paired_cpu_comparison/run_paired_hnsw_audit_cpu12.sh
```

The audit uses `afterany` deliberately so failures and timeouts remain visible.
It fails unless all 720 planned pairs are present and each pair proves matching
hostname/allocation and opposite route positions.
