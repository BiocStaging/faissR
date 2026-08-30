# CPU leave-one-dataset-out evidence

These files are the machine-readable CPU leave-one-dataset-out (LOODO)
selection results reported in the JSS manuscript. They were reconstructed from
the explicit CPU held-out routes in the version-pinned HPC campaign; they do
not represent an evaluation of the installed `method = "auto"` policy.

The analysis excludes the named evaluation dataset before selecting a method
family from the remaining datasets. The public analysis implementation is
`benchmark_scripts/jss_reproduction/analysis/analyze_leave_one_dataset_out.R`.

- `jss_leave_one_dataset_out.csv`: one row per held-out operating-point cell.
- `jss_leave_one_dataset_out_summary.csv`: summaries by metric and target.
- `jss_leave_one_dataset_out_by_dataset.csv`: summaries by held-out dataset.
- `JSS_LEAVE_ONE_DATASET_OUT_REPORT.md`: compact audit report.
- `checksums.sha256`: SHA-256 digests for the four evidence files.

The eventual accepted-package archival release will provide the final combined
replication archive. This directory preserves the current result independently
of that future release freeze.
