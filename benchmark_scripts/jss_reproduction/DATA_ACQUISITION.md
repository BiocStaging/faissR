# Dataset Acquisition and Redistribution

The publication archive uses an explicit `yes`/`no` redistribution policy.
There are no unresolved redistribution entries. A `no` decision is
conservative: the converted float32 matrix is excluded, while source identity, release or
accession, preprocessing, dimensions, and a frozen fingerprint are retained.
Users must accept any source terms themselves.

## Source-required datasets

| Dataset | Required acquisition | Local preparation recorded by the benchmark |
|---|---|---|
| COIL20 | Download the processed COIL-20 archive `coil-20-proc.zip` from the Columbia source page. | Convert images to grayscale where needed and flatten each image to 16,384 pixels without scaling, PCA, or dimensionality reduction. |
| USPS | Acquire the `usps` data from the recorded `Rdimtools` source release. | Retain the 11,000 by 256 feature matrix and labels without added scaling or reduction. |
| FlowRepository FR-FCM-ZYRM | Download the 102 FCS files from accession `FR-FCM-ZYRM`. | Retain the 32 recorded biological-marker channels, apply `asinh(x / 5)`, and derive labels from filenames. |
| MNIST | Download the recorded training and test IDX files from the listed mirror. | Concatenate train and test rows and flatten the 28 by 28 pixels without added scaling or reduction. |
| ImageNet features | Obtain authorized ILSVRC 2012 access under the ImageNet access agreement and acquire or regenerate the recorded 1,024-dimensional DINOv2 representation. | Preserve the 1,281,167 by 1,024 feature matrix and class indices without an additional benchmark-time transform. Source images and derived features are not redistributed by faissR. |
| MetRef | Acquire `MetRef` from the recorded `KODAMA` source release. | Remove zero-column-sum variables, then apply the recorded KODAMA normalization and scaling without PCA or embedding. |

The provenance CSV is the normative record:

```text
benchmark_scripts/jss_reproduction/validation/dataset_provenance_jss_template.csv
```

Before a frozen run, copy it to `Data/dataset_provenance_jss.csv`, record the
actual acquisition date, and retain the source release used. Do not place a
source-required converted matrix in a public replication archive.

## Explicitly redistributable datasets

Fashion-MNIST is recorded under MIT terms. The `flow18` and `mass41` source
files are recorded under CC BY 4.0. Any redistributed artifact must retain the
applicable notice, citation, and attribution.

## Fingerprint verification

After local preparation, verify the resulting RData files against the frozen
MD5 values:

```bash
Rscript benchmark_scripts/jss_reproduction/common/verify_publication_datasets.R \
  --provenance=/scratch/firenze/NN/Data/dataset_provenance_jss.csv \
  --data-root=/scratch/firenze/NN \
  --out=/scratch/firenze/NN/Data/dataset_provenance_audit.csv
```

The command fails if a policy is not `yes` or `no`, required provenance is
blank, a file is absent, or a fingerprint differs. The publication freeze
audit repeats these checks against the benchmark manifest.
