# Publication evidence matrix

This matrix defines the evidence required for the JSS article. It separates
new computation from analyses of existing archives and software-description
changes. A numerical claim is activated only after the corresponding audit
passes.

| Scientific question | Evidence | HPC requirement |
|---|---|---|
| Does query count or index reuse change the preferred route? | `query_workload/`: external query counts 1, 32, and 1,024; selected full self-search cells; cold and repeated calls; amortized totals | Pending; not in the current analysed archive |
| Is the single-timing screening winner stable? | `calibration_confirmation/`: prespecified shortlist, five isolated randomized timings, robust median selection, stability and regret | New CPU and CUDA jobs |
| Does installed automatic selection attain its requested tier on independent queries? | `recall_inference/`: CPU and CUDA auto, two query seeds, tie-aware recall, one-sided bootstrap lower bounds, separate timing repetitions | New CPU and CUDA jobs |
| How does faissR compare with other R interfaces? | `comprehensive_r_comparison/` for FNN, RANN, rnndescent, BiocNeighbors, Rnanoflann, RcppAnnoy, and RcppHNSW; `paired_cpu_hnsw_pareto/` adds recall-matched HNSW tuning | New CPU jobs |
| What overhead does the R interface add over native FAISS/cuVS? | Same-allocation native C++ calls on a focused workload subset, decomposing conversion, index/search, metadata/wrapping, and host-transfer time | Pending; no native-overhead estimate is currently admissible |
| Are comparisons point-recall-matched? | Independent calibration and validation in `paired_cpu_hnsw_pareto/`; observed recall retained for every external pair | Pending; no Pareto or fitted ratio is currently admissible |
| What are build, warm-query, and break-even costs? | `query_workload/`; fitted-query claims remain conditional on successful identity and recall audits | Pending; functional reuse only in the current article |
| What is gained by GPU-resident continuation? | `gpu_resident_interoperability/`: device consumer, explicit host transfer, lifetime and ownership checks | Pending; API/ownership contract only in the current article |
| What are per-cell host and device memory costs? | `resource_memory/`: one fresh R process per cell, Linux `VmHWM`, retained host increment, result footprint, process GPU peak, OOM and timeout outcomes | Pending; no quantitative memory claim is currently admissible |
| How should failures and timeouts affect speed claims? | `analysis/analyze_failure_aware_profiles.R`: planned-cell denominator, performance profile, and capped-runtime sensitivity | Existing archive only |
| Does selector performance depend on dataset or domain identity? | Named-dataset and grouped-domain holdout analyses plus route-confusion and selector-regret tables | Existing explicit-route archive only |
| How much does the automatic route lag the fastest feasible route? | `analysis/analyze_selector_regret.R`, reported by dataset, metric, k, target, and route family | Existing archive only |
| Are boundary ties material? | Tie frequency, tie credit, overlap recall, tie-aware recall, and lower confidence bounds in `recall_inference/` | Included above |
| Are exact routes exact despite tied identifiers? | Existing exact-reference and route-contract audits; exact-family cells are reported as `exact-audited`, not ANN target failures | No new job |
| Are zero vectors, constant rows, and non-finite values defined? | Existing metric-conformance suite, `nn_metric_preflight()`, help pages, and backend-specific contract table | No new job |
| What do `exact`, `flat`, and `bruteforce` mean? | Capability-dependent dispatch table and resolved-provider metadata in the article and package documentation | No new job |
| How are package-owned derived graph routes defined? | Pseudocode, complexity, supported metrics, randomness, and differences from canonical algorithms in the supplement; these routes remain secondary | No new job |
| Does the policy generalize to other hardware? | Hardware fingerprint and explicit L40S calibration scope; a second machine is optional and cannot establish universal optimality | No mandatory job |
| Can users impose memory or latency budgets? | Not implemented in the evaluated API; state as a limitation and future selector constraint rather than inferring support from benchmarks | No job can resolve this |
| Is the replication package self-consistent? | Versioned experiment roots, package/image commit checks, raw manifests, Slurm exits, report audits, checksums, and `publication_campaign/audit_publication_campaign.R` | Final audit job or local analysis |

## Interpretation boundaries

- The original wide grids are screening evidence. Confirmation results measure
  timing stability and do not silently redefine the installed policy.
- Independent query seeds provide recall evidence; repeated timings of one
  query set provide runtime evidence only.
- `VmHWM` is used only from an isolated process. Host and device memory are
  reported separately.
- Same-node paired comparisons answer end-to-end public-interface questions.
  They are not kernel-only benchmarks.
- CPU and CUDA automatic policies are reported separately. No result from one
  backend is used as validation of the other.
