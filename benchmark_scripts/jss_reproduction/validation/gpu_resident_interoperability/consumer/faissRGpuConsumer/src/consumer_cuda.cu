#include <cuda_runtime.h>
#include <cstddef>

__global__ void checksum_kernel(const int* indices, const float* distances,
                                std::size_t n,
                                unsigned long long* index_sum,
                                double* distance_sum) {
    const std::size_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    atomicAdd(index_sum, static_cast<unsigned long long>(indices[i]));
    atomicAdd(distance_sum, static_cast<double>(distances[i]));
}

extern "C" int faissr_consumer_checksum_cuda(
    const int* indices, const float* distances, std::size_t n,
    unsigned long long* host_index_sum, double* host_distance_sum) {
    unsigned long long* device_index_sum = nullptr;
    double* device_distance_sum = nullptr;
    cudaError_t status = cudaMalloc(&device_index_sum, sizeof(*device_index_sum));
    if (status != cudaSuccess) return static_cast<int>(status);
    status = cudaMalloc(&device_distance_sum, sizeof(*device_distance_sum));
    if (status != cudaSuccess) {
        cudaFree(device_index_sum);
        return static_cast<int>(status);
    }
    cudaMemset(device_index_sum, 0, sizeof(*device_index_sum));
    cudaMemset(device_distance_sum, 0, sizeof(*device_distance_sum));
    const int threads = 256;
    const int blocks = static_cast<int>((n + threads - 1) / threads);
    checksum_kernel<<<blocks, threads>>>(
        indices, distances, n, device_index_sum, device_distance_sum);
    status = cudaGetLastError();
    if (status == cudaSuccess) status = cudaDeviceSynchronize();
    if (status == cudaSuccess) {
        status = cudaMemcpy(host_index_sum, device_index_sum,
                            sizeof(*device_index_sum), cudaMemcpyDeviceToHost);
    }
    if (status == cudaSuccess) {
        status = cudaMemcpy(host_distance_sum, device_distance_sum,
                            sizeof(*device_distance_sum), cudaMemcpyDeviceToHost);
    }
    cudaFree(device_index_sum);
    cudaFree(device_distance_sum);
    return static_cast<int>(status);
}
