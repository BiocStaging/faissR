#!/usr/bin/env bash
set -euo pipefail

ROOT=${PACKAGE_TEST_ROOT:?Set PACKAGE_TEST_ROOT on a disk with sufficient free space}
HERE=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$HERE/cuda-ubuntu-faiss.def.in"
DEBIAN_TEMPLATE="$HERE/cuda-debian-faiss.def.in"
mkdir -p "$ROOT/build-logs"

render_and_build() {
    local name=$1
    local image=$2
    local architectures=$3
    local cuvs=$4
    local definition="$ROOT/build-logs/$name.def"
    local partial="$definition.partial"
    sed -e "s|@CUDA_IMAGE@|$image|g" \
        -e "s|@CUDA_ARCHS@|$architectures|g" \
        "$TEMPLATE" > "$partial"
    if [ "$cuvs" = "yes" ]; then
        sed -e '/@INSTALL_CUVS@/r '"$HERE/cuda-install-cuvs.inc" \
            -e '/@INSTALL_CUVS@/d' "$partial" > "$definition"
    else
        sed '/@INSTALL_CUVS@/d' "$partial" > "$definition"
    fi
    rm -f "$partial"
    bash "$HERE/build.sh" "$definition" "$name"
}

render_debian_and_build() {
    local name=$1
    local version=$2
    local architectures=$3
    local definition="$ROOT/build-logs/$name.def"
    sed -e "s|@CUDA_VERSION@|$version|g" \
        -e "s|@CUDA_ARCHS@|$architectures|g" \
        "$DEBIAN_TEMPLATE" > "$definition"
    bash "$HERE/build.sh" "$definition" "$name"
}

# CUDA 12.4 predates native Blackwell code generation. The compute_80 PTX
# retained by FAISS and faissR lets the Blackwell driver test JIT compatibility.
render_and_build \
    cuda-12.4-ubuntu22-faiss \
    nvidia/cuda:12.4.1-devel-ubuntu22.04 \
    '80-real;80-virtual' no

render_and_build \
    cuda-12.8-ubuntu24-faiss \
    nvidia/cuda:12.8.1-devel-ubuntu24.04 \
    '80-real;89-real;90-real;120-real;120-virtual' no

render_and_build \
    cuda-13.2-ubuntu24-faiss \
    nvidia/cuda:13.2.0-devel-ubuntu24.04 \
    '80-real;89-real;90-real;100-real;120-real;120-virtual' no

render_and_build \
    cuda-13.2-ubuntu24-faiss-cuvs \
    nvidia/cuda:13.2.0-devel-ubuntu24.04 \
    '80-real;89-real;90-real;100-real;120-real;120-virtual' yes

# Debian uses an isolated conda CUDA toolkit so the image does not depend on a
# distribution CUDA metapackage or alter the host driver.
render_debian_and_build \
    cuda-13.2-debian13-faiss \
    13.2 \
    '80-real;89-real;90-real;100-real;120-real;120-virtual'
