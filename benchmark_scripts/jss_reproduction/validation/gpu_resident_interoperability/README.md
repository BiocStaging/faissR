# GPU-resident interoperability and transfer decomposition

This experiment quantifies a distinct software property: retaining nearest-
neighbor output on an NVIDIA GPU for a downstream compiled consumer. It is not
an algorithm comparison between GPU- and host-resident routes.

Five datasets and query batches of 1, 32, and 1,024 rows are evaluated in 15
isolated Slurm tasks with five repetitions. Each repetition records:

- `nn_gpu()` search time before any result transfer;
- a device-side checksum kernel launched by a separate minimal R package;
- explicit `gpu_knn_to_host()` materialization time;
- the device and host byte footprints implied by the public layout;
- process-scoped host `VmHWM` and sampled process GPU memory;
- residency, copy-count, device, provider, and ABI metadata; and
- device memory after the owning R object is removed and garbage collected.

The downstream package in `consumer/faissRGpuConsumer` includes
`<faissR_api.h>`, verifies ABI version 1, retrieves
`faissR_nn_cuda_tuned_gpu_call` through `R_GetCCallable()`, and launches a CUDA
kernel over `indices_ptr` and `distances_ptr`. It copies only two checksum
scalars to host. The full-transfer phase materializes both neighbor matrices.
The operation order alternates by repetition.

The benchmark intentionally does not compare `nn_gpu()` against ordinary
`nn()` timing: the former returns device-resident output and the latter returns
host matrices. Algorithm comparisons in the manuscript use host-resident
outputs for every route; this module decomposes residency benefit separately.

Submit from a compute or interactive node after synchronizing the scripts:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=b33a70116887474a2ed70d84de0c80bb77e9db66
bash benchmark_scripts/jss_reproduction/validation/gpu_resident_interoperability/submit_gpu_interop.sh
```

No numerical claim should be added until the report ends with
`GPU RESIDENCY/INTEROPERABILITY AUDIT PASSED`.
