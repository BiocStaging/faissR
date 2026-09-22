#!/usr/bin/env bash
set -euo pipefail

IMAGE=$(realpath "${1:?Usage: run-cuda.sh IMAGE ARCHIVE OUTPUT cuda-native|cuda-cuvs}")
ARCHIVE=$(realpath "${2:?Source archive required}")
CONTAINER_ARCHIVE="/$(basename "$ARCHIVE")"
OUT=${3:?Unique output directory required}
PROFILE=${4:-cuda-native}
case "$PROFILE" in
    cuda-native|cuda-cuvs) ;;
    *) echo "Profile must be cuda-native or cuda-cuvs." >&2; exit 2 ;;
esac

HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
test ! -e "$OUT/status.csv" || {
    echo "Output already contains a run: $OUT" >&2
    exit 1
}
mkdir -p "$OUT/tmp"
sha256sum "$IMAGE" "$ARCHIVE" > "$OUT/inputs.sha256"

ENGINE=${CONTAINER_ENGINE:-singularity}
CUDA_ROOT=${CONTAINER_CUDA_HOME:-/usr/local/cuda}
CUVS_ROOT=${CONTAINER_CUVS_HOME:-/opt/cuvs}
REQUIRE_CUVS=0
USE_CUVS=0
if [ "$PROFILE" = "cuda-cuvs" ]; then
    REQUIRE_CUVS=1
    USE_CUVS=1
fi

"$ENGINE" exec --nv --cleanenv --containall --no-home \
    --bind "$HERE:/harness:ro" \
    --bind "$ARCHIVE:$CONTAINER_ARCHIVE:ro" \
    --bind "$OUT:/results" \
    --bind "$OUT/tmp:/tmp" \
    --env "PACKAGE_TEST_COMMIT=${PACKAGE_TEST_COMMIT:-UNRECORDED}" \
    --env "PACKAGE_TEST_IMAGE=$(basename "$IMAGE")" \
    --env "CUDA_HOME=$CUDA_ROOT" \
    --env "PATH=/opt/R/bin:/usr/local/bin:/usr/bin:/bin:$CUDA_ROOT/bin" \
    --env "LD_LIBRARY_PATH=$CUDA_ROOT/lib:$CUDA_ROOT/lib64:/usr/local/lib:$CUVS_ROOT/lib:$CUVS_ROOT/lib64" \
    --env "CUVS_HOME=$CUVS_ROOT" \
    --env "FAISSR_REQUIRE_FAISS=1" \
    --env "FAISSR_REQUIRE_CUDA=1" \
    --env "FAISSR_REQUIRE_CUDA_RUNTIME=1" \
    --env "FAISSR_USE_CUVS=$USE_CUVS" \
    --env "FAISSR_REQUIRE_CUVS=$REQUIRE_CUVS" \
    --env "FAISSR_CUDA_ARCH=${FAISSR_CUDA_ARCH:-}" \
    --env "FAISSR_CUDA_PTX_ARCH=${FAISSR_CUDA_PTX_ARCH:-}" \
    "$IMAGE" Rscript /harness/run.R \
        "$CONTAINER_ARCHIVE" /results "$PROFILE" /harness/faissR-smoke.R
