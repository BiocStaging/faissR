# Isolated resource and memory benchmark

This module measures host and device memory for representative faissR routes.
Every method, dataset, query mode, and repetition is executed in a fresh R
worker. Consequently, Linux `VmHWM` belongs to exactly one benchmark cell and
cannot inherit a high-water mark from an earlier method.

The experiment uses five prespecified datasets, Euclidean distance, `k = 30`,
and the 0.99 requested recall tier. CPU routes are `auto`, `flat`, `hnsw`, and
`ivf`; CUDA routes are `auto`, `flat`, `cagra`, and `ivf`. Each route is tested
for a 1,024-row external-query workload and full self-search. Three isolated
repetitions are run. Failures, timeouts, and out-of-memory exits remain in the
result table.

Each worker records baseline, post-input, and post-search resident memory;
process `VmHWM`; R object size; result-buffer bytes; provider and route
metadata; and recall against the archived exact query set. CUDA workers also
sample process-scoped `nvidia-smi` memory every 100 ms. The reported GPU peak is
the maximum sample for that worker process. Host and device measurements are
never combined into one quantity.

This experiment does not claim that `object.size()` measures a native FAISS or
cuVS index. The difference between post-search and post-input resident memory
is reported as an empirical process-level retained-memory increment. It can
include provider resources, allocator retention, and result storage.

Submit from `/scratch/firenze/NN` after exporting the image, package version,
and 40-character commit:

```bash
bash benchmark_scripts/jss_reproduction/validation/resource_memory/submit_resource_memory.sh
```

Quantitative memory claims require both audit reports to end in
`RESOURCE MEMORY AUDIT PASSED`.
