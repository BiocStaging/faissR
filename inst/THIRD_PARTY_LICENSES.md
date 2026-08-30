# External native libraries

`faissR` is distributed under the MIT license. It does not vendor or
redistribute FAISS, cuVS, the CUDA toolkit, or NVIDIA drivers.

| Component | License | Distribution relationship |
|---|---|---|
| FAISS | MIT ([license](https://github.com/facebookresearch/faiss/blob/main/LICENSE)) | Required system library supplied by the user or build environment. |
| RAPIDS cuVS | Apache License 2.0 ([license](https://github.com/rapidsai/cuvs/blob/main/LICENSE)) | Optional system library supplied by the user or build environment. |
| NVIDIA CUDA toolkit and driver | NVIDIA CUDA SDK EULA ([terms](https://docs.nvidia.com/cuda/eula/index.html)) | Optional user-installed runtime/toolkit; not redistributed by `faissR`. |

The package's source distribution contains interface and configuration code,
not copies of these libraries. Users and binary distributors remain
responsible for satisfying the applicable external licenses and for using an
ABI-compatible compiler and library stack.
