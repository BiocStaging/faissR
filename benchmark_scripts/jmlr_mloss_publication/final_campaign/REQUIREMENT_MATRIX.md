# JSS requirement-to-script matrix

This matrix is the completion contract for the publication campaign.
Every computational claim maps to an R program, independent Slurm jobs,
and an expected archive location. TabulaMuris is intentionally excluded.

| Evidence requirement | R implementation | Slurm launchers | Output |
|---|---|---|---|
| Metric-matched exact references with independent CPU audit | `common/benchmark_precompute_exact_references_cuda.R` | `references/run_real_references_cuda_*.sh`, `references/run_synthetic_references_cuda.sh` | `final_campaign/references/` plus reference objects beside datasets |
| Real-data calibration for every faissR method, backend, metric, k, and recall target | `common/benchmark_method_tuning_from_reference.R` | `calibration/real/{cpu,cuda}/` | `final_campaign/calibration/real/` |
| Norm-stress MIPS calibration | same calibration program | `calibration/mips/{cpu,cuda}/` | `final_campaign/calibration/mips/` |
| Held-out explicit-method and automatic-selection validation | `common/benchmark_jmlr_tuned_methods.R` | `held_out/{cpu,cuda}/` | `final_campaign/held_out/` |
| External-package cold comparison | `common/benchmark_jmlr_tuned_methods.R` | external launchers in `held_out/cpu/` and `held_out/cuda/` | `final_campaign/held_out/` |
| Public reusable-index build/query comparison | `common/benchmark_reusable_external_indexes.R` | `reusable_external/` | `final_campaign/reusable_external/` |
| Float32, fitted-index, compiled self-removal, batching, and GPU-copy ablations | `common/benchmark_jss_systems_ablations.R` | `ablations/` | `final_campaign/ablations/` |
| Metric and degenerate-row conformance | `common/benchmark_metric_conformance.R` | `analysis/run_metric_conformance_*.sh` | `final_campaign/analysis/metric_conformance/` |
| Low-dimensional grid evidence | held-out and ablation programs | grid launchers in `held_out/` plus `ablations/` | held-out and ablation archives |
| Auto-versus-oracle, completion, target attainment, and figures | `analysis/aggregate_publication_results.R`, `analysis/build_publication_figures.R` | `analysis/run_held_out_analysis_*.sh` | `final_campaign/analysis/held_out_*/` |
| Leave-one-dataset-out sensitivity | `analysis/analyze_leave_one_dataset_out.R` | `analysis/run_held_out_analysis_*.sh` | `leave_one_dataset_out/` within held-out analysis |
| Calibration completeness and negative evidence | `analysis/aggregate_calibration_results.R` | `analysis/run_calibration_audit_cpu12.sh` | calibration analysis archive |
| Reusable-index completeness and summaries | `analysis/aggregate_reusable_external_indexes.R` | `analysis/run_reusable_external_audit_cpu12.sh` | reusable-index analysis archive |
| Installed-version, external-comparator inventory, query-mode-aware CPU/CUDA route, unsupported-contract, provider, GPU-residency, and container identity checks | `common/benchmark_package_route_qa.R` | `qa/` | `final_campaign/qa/` |
| Immutable dataset, result, software, container, and provenance freeze | `analysis/audit_publication_freeze.R` | `analysis/run_freeze_audit_*.sh` | freeze audit archives |
