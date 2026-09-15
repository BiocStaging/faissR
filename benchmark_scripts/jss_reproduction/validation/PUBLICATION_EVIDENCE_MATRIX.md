# Publication evidence matrix

This matrix records the evidence boundary for the JSS article. It distinguishes
completed audited experiments from protocols that were prepared but are not
used to support a numerical claim.

| Scientific question | Evidence | Status in the article |
|---|---|---|
| Does query count or index reuse change observed cost? | `query_workload/`: five datasets, external query counts 1, 32, and up to 1,024, cold and repeated calls, and amortized totals | Completed and checksum-audited for the focused workload. The experiment does not recalibrate the installed selector by query workload. |
| Is the single-timing screening winner stable? | `calibration_confirmation/`: prespecified shortlist and five isolated randomized timings | Not completed. The article reports the observed one-timing limitation and the available near-tie diagnostic; it makes no replicated-confirmation claim. |
| Does installed automatic selection attain its requested tier on independent queries? | Existing CPU HNSW and CUDA automatic validation with two independently sampled query sets and point mean recall | Completed for the recorded point-recall criterion. The separate bootstrap/tie-aware approximate-recall protocol was not completed and is excluded. |
| How does faissR compare with other R interfaces? | `comprehensive_r_comparison/` for seven external interfaces; `paired_cpu_hnsw_pareto/` for independently tuned HNSW | Both experiments completed and passed their audits. Same-family, task-level, and experimental-derived comparisons are reported separately. |
| What overhead does the R interface add over native FAISS/cuVS? | Proposed same-allocation native calls decomposing conversion, search, wrapping, and transfer | Not completed; the article makes no native-interface-overhead estimate. |
| Are CPU HNSW comparisons point-recall-matched? | Independent calibration and validation in `paired_cpu_hnsw_pareto/`, with observed cold and fitted recall for each provider pair | Completed and checksum-audited. Table 5 includes only pairs satisfying the prespecified point mean-recall criterion. |
| What are build, warm-query, and break-even costs? | Direct build and fitted-query phases in `paired_cpu_hnsw_pareto/`; cold and repeated calls in `query_workload/` | Completed. The break-even result is explicitly HNSW reuse versus rebuilt one-shot Flat calls, not versus a reusable exact index. |
| What is established for GPU-resident continuation? | `gpu_resident_interoperability/`: device consumer, explicit host transfer, lifetime, and ownership checks | The interface contract is reported. Transfer speed and downstream performance are unmeasured and are not claimed. |
| What are per-cell host and device memory costs? | `resource_memory/`: proposed isolated-worker host and device measurements | Not completed; the article contains no quantitative memory comparison. |
| How are failures and timeouts represented? | Complete denominators and recorded failures/timeouts in calibration and public-interface comparisons | Descriptive counts are reported. No failure-aware performance profile or capped-runtime estimand is claimed. |
| Does selector performance depend on dataset or domain identity? | Named-dataset and grouped-domain holdouts, route-confusion tables, and selector-regret summaries | Completed as post hoc sensitivity analyses using the explicit-route archive. They are not presented as validation of the installed candidate universe. |
| How much does the automatic route lag the fastest feasible tested route? | `analysis/analyze_selector_regret.R`, summarized by dataset and route family | Completed for the installed CUDA policy and its tested candidate set. |
| Are boundary ties material? | Exact-route tie-aware audit; identifier-overlap recall for approximate methods | Exact-route handling is completed. Approximate recall is explicitly reported as unadjusted identifier overlap; no bootstrap or tie-aware approximate result is claimed. |
| Are exact routes exact despite tied identifiers? | Exact-reference and route-contract audits | Completed; passing exhaustive routes are labelled `exact-audited`. |
| Are zero vectors, constant rows, and non-finite values defined? | Metric-conformance tests, `nn_metric_preflight()`, help pages, and backend-specific contract table | Completed and documented. |
| What do `exact`, `flat`, and `bruteforce` mean? | Capability-dependent dispatch table and resolved-provider metadata | Completed and documented. |
| How are package-owned derived graph routes defined? | Pseudocode, complexity, supported metrics, randomness, and differences from canonical algorithms | Documented in the supplement and marked experimental; excluded from principal performance claims. |
| Does the policy generalize to other hardware? | Hardware fingerprint and explicit L40S calibration scope | No hardware-independent optimum is claimed. Mismatched hardware is reported as extrapolated. |
| Can users impose memory or latency budgets? | Current public selector contract | Not implemented; the limitation is stated without implying benchmark support. |
| Is the replication package self-consistent? | Checksums, source manifests, executable audits, and `audit_submission.py` | Archive and source audits pass. A clean-export audit must be rerun after the current revision is committed. |

## Interpretation boundaries

- The original wide grids are screening evidence. No replicated-confirmation
  result is used to redefine the installed policy.
- Independent query seeds provide recall evidence; repeated timings of one
  query set provide runtime evidence only.
- Quantitative host or device memory is excluded until an isolated-worker audit
  is complete; process-lifetime `VmHWM` values are not treated as per-cell peaks.
- Same-node paired comparisons answer end-to-end public-interface questions.
  They are not kernel-only benchmarks.
- CPU and CUDA automatic policies are reported separately. No result from one
  backend is used as validation of the other.
