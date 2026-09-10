#!/usr/bin/env bash
set -euo pipefail
IMAGE=$(realpath "${1:?Provide the baseline image with Rcpp older than 1.1.0}")
ARCHIVE=$(realpath "${2:?Provide the source package archive}")
OUT=${3:?Provide a new output directory}
test ! -e "$OUT" || { echo "Output already exists" >&2; exit 1; }
mkdir -p "$OUT/library" "$OUT/tmp"
OUT=$(realpath "$OUT")
ENGINE=${CONTAINER_ENGINE:-singularity}
sha256sum "$IMAGE" "$ARCHIVE" > "$OUT/inputs.sha256"
"$ENGINE" exec --cleanenv --containall --no-home \
    --bind "$ARCHIVE:/source.tar.gz:ro" --bind "$OUT:/results" \
    --bind "$OUT/tmp:/tmp" "$IMAGE" Rscript -e '
stopifnot(packageVersion("Rcpp") < "1.1.0")
cat("Installed Rcpp:", as.character(packageVersion("Rcpp")), "\n")
status <- system2(file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--library=/results/library", "/source.tar.gz"),
    stdout="/results/install.log", stderr="/results/install.log")
log <- readLines("/results/install.log", warn=FALSE)
stopifnot(status != 0L, any(grepl("Rcpp", log)),
    any(grepl("1.1.0", log)), any(grepl("required", log)))
cat("PASS: old Rcpp is rejected before native compilation\n")
' 2>&1 | tee "$OUT/negative-test.log"
