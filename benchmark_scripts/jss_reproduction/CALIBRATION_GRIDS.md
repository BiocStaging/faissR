# Publication calibration grids

The publication calibration crossed the three public metrics (`euclidean`,
`cosine`, and `correlation`), CPU/CUDA backends, supported methods,
`k = 15, 30, 50, 100`, and target recall 0.90, 0.95, and 0.99. Provider
constraints were repaired before execution, so the authoritative grid is the
instantiated grid rather than a short hand-written parameter list.

Run `analysis/build_consistency_artifacts.R` against the verified campaign
archive to create:

- `reference_record_dimensions.csv`: the complete 87-record exact-reference
  key, including dimensions, query counts, sampling rule, seeds, fingerprints,
  provider identity, and CPU cross-audit fields.
- `calibration_candidate_grid_manifest.csv`: one row for each of the 63 source
  grids, with backend, method, metric, row count, candidate count, and SHA-256.
- `calibration_candidate_grid_public.csv.gz`: all 41,229 instantiated candidate
  rows with their exact provider parameters.
- `experiment_version_boundaries.csv` and `experiment_version_changes.csv`:
  the separation and validity controls for the 0.99.21 campaign and 0.99.25
  controlled CPU experiment.

From the repository root:

```sh
Rscript benchmark_scripts/jss_reproduction/analysis/build_consistency_artifacts.R \
  --campaign_root=/path/to/final_campaign \
  --out_dir=manuscript/jss/derived/consistency_artifacts
```

The script asserts 87 reference records, 63 public-metric source grids, and
41,229 instantiated rows. A count or provenance mismatch stops reconstruction.
The supplementary article summarizes the schedules; the compressed CSV is the
normative record of every candidate value after shape-dependent construction
and provider-validity repair.
