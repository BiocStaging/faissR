#!/usr/bin/env bash
set -euo pipefail

ROOT=${PACKAGE_TEST_ROOT:?Set PACKAGE_TEST_ROOT on a disk with sufficient free space}
ARCHIVE=$(realpath "${1:?Usage: run-cuda-matrix.sh SOURCE.tar.gz NEW_OUTPUT}")
OUT=$(realpath -m "${2:?A new output directory is required}")
HERE=$(cd "$(dirname "$0")" && pwd)
test ! -e "$OUT" || {
    echo "Refusing to reuse output directory: $OUT" >&2
    exit 1
}
mkdir -p "$OUT"

run_one() {
    local label=$1
    local profile=$2
    local arch=$3
    local cuda_root=${4:-/usr/local/cuda}
    local image="$ROOT/images/$label.sif"
    local result="$OUT/$label"
    if [ ! -f "$image" ]; then
        printf '%s,%s,%s\n' "$label" BLOCKED missing_image >> "$OUT/matrix.csv"
        return
    fi
    if CONTAINER_CUDA_HOME="$cuda_root" \
        FAISSR_CUDA_ARCH="$arch" FAISSR_CUDA_PTX_ARCH="$arch" \
        bash "$HERE/run-cuda.sh" "$image" "$ARCHIVE" "$result" "$profile"; then
        printf '%s,%s,%s\n' "$label" PASS complete >> "$OUT/matrix.csv"
    else
        printf '%s,%s,%s\n' "$label" FAIL check_logs >> "$OUT/matrix.csv"
    fi
}

printf '%s\n' 'target,status,detail' > "$OUT/matrix.csv"
run_one cuda-12.4-ubuntu22-faiss cuda-native 80
run_one cuda-12.8-ubuntu24-faiss cuda-native 120
run_one cuda-13.2-ubuntu24-faiss cuda-native 120
run_one cuda-13.2-ubuntu24-faiss-cuvs cuda-cuvs 120
run_one cuda-13.2-debian13-faiss cuda-native 120 /opt/cuda
cat "$OUT/matrix.csv"
