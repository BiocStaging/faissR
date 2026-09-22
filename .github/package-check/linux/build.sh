#!/usr/bin/env bash
set -euo pipefail
ROOT=${PACKAGE_TEST_ROOT:?Set PACKAGE_TEST_ROOT on a disk with sufficient free space}
DEF=${1:?Usage: build.sh definition.def image-name}
NAME=${2:?Provide a unique image name}
mkdir -p "$ROOT/images" "$ROOT/cache" "$ROOT/tmp" "$ROOT/build-logs"
export SINGULARITY_CACHEDIR="$ROOT/cache" SINGULARITY_TMPDIR="$ROOT/tmp"
export APPTAINER_CACHEDIR="$ROOT/cache" APPTAINER_TMPDIR="$ROOT/tmp" TMPDIR="$ROOT/tmp"
ENGINE=${CONTAINER_ENGINE:-singularity}
export SINGULARITY_MKSQUASHFS_PROCS=2
IMAGE="$ROOT/images/$NAME.sif"
test ! -e "$IMAGE" || { echo "Refusing to replace $IMAGE" >&2; exit 1; }
if grep -q '@BASE_ARCHIVE@' "$DEF"; then
    BASE="$ROOT/images/debian-bundled-base.tar"
    if test ! -f "$BASE"; then
        docker save -o "$BASE.partial" "${DEBIAN_BASE_IMAGE:-faissr-debian-bundled-blas:20260910}"
        mv "$BASE.partial" "$BASE"
    fi
    sed "s|@BASE_ARCHIVE@|$BASE|" "$DEF" > "$ROOT/build-logs/$NAME.def"
    DEF="$ROOT/build-logs/$NAME.def"
fi
if grep -q '@UBUNTU_BASE@' "$DEF"; then
    BASE=${UBUNTU_BASE_IMAGE:?Set UBUNTU_BASE_IMAGE to the existing Ubuntu SIF}
    sed "s|@UBUNTU_BASE@|$BASE|" "$DEF" > "$ROOT/build-logs/$NAME.def"
    DEF="$ROOT/build-logs/$NAME.def"
fi
build_options=(--fakeroot)
if [ "${PACKAGE_TEST_KEEP_FAILED_BUILD:-0}" = "1" ]; then
    build_options+=(--no-cleanup)
fi
"$ENGINE" build "${build_options[@]}" "$IMAGE" "$DEF" 2>&1 | tee "$ROOT/build-logs/$NAME.log"
sha256sum "$IMAGE" > "$IMAGE.sha256"
"$ENGINE" inspect --deffile "$IMAGE" > "$IMAGE.def"
