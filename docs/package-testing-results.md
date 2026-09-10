# Cross-platform CPU validation: 10 September 2026

Tested faissR 0.99.41 working tree based on commit
`ccf983c770adb9e09b307ebb64167f7ff45ad7b8`, with the local portability fixes.
This report does not imply a published release or a GitHub push.

Identical source archive SHA256 on all targets:
`4caddbff0e405c40178181e4dd9909b0be20435a39ed4b973f42111e46c9e22a`.

| Platform | R | Profile | Errors | Warnings | Notes |
|---|---|---|---:|---:|---:|
| macOS 14.5 arm64, Homebrew FAISS 1.14.3 | 4.6.0 | Functional CPU | 0 | 0 | 0 |
| Ubuntu 24.04 x86_64, FAISS 1.11.0, Rcpp 1.1.0 | 4.3.3 | Functional CPU | 0 | 0 | 4 |
| Debian 13 x86_64, FAISS 1.11.0-3, bundled R BLAS | 4.6.0 | Functional CPU | 0 | 0 | 0 |
| Windows 10 x64, Rtools-compatible patched FAISS 1.11.0 | 4.6.1 | Functional CPU | 0 | 0 | 0 |
| Windows 10 x64, FAISS absent | 4.6.1 | Diagnostic-only | 0 | 0 | 0 |

All five profiles passed installation, capability smoke tests and
`R CMD check --as-cran --no-manual`, including examples and vignette rebuilding.
Each functional profile reported 3,055 passing assertions and 119 skips.
The diagnostic profile reported 2,018 passing assertions and 144 skips.
All had zero failed assertions and zero test warnings. Skips include GPU-only
tests and repository-only scripts absent from the source-package archive.

Fixes: Windows now probes complete numerical libraries before enabling FAISS;
Rcpp >= 1.1.0 is declared in both Imports and LinkingTo; FAISS-dependent vignette
examples are capability-aware. Negative tests confirm rejection of old Rcpp,
invalid explicit numerical flags and missing required FAISS. Native search
algorithms and public API behavior were not changed.

BiocCheck 1.49.30 reports 0 errors, 0 warnings and 2 notes: its recommendation to
raise the minimum R version to 4.6.0, and inability to verify Bioc-Devel mailing
list subscription without administrator credentials. The former was retained
to avoid excluding the successfully tested R 4.3.3 configuration. R >= 3.0.2
declares the feature needed for versioned LinkingTo, not a tested R 3.0.2 build.

Ubuntu's four notes concern debug-library size, network time verification,
ORCID author formatting differences between R versions, and a distribution
compiler flag. No checks were disabled to suppress those notes.

See [test-lab instructions](package-testing.md) for recipes, command entry
points, artifact layout and interpretation. Local operators retain the source,
patch, SIF checksums, environment metadata and complete logs under the private
lab's `runs/verified-041-20260910` directory. Raw private-machine logs are not
published automatically. Windows ARM64, macOS Intel, CUDA/cuVS, sanitizers,
performance measurements and PDF manual generation were not validated here.
