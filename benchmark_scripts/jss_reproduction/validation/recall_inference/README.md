# Tie-aware recall and sampling uncertainty

This focused campaign reevaluates the installed CPU and CUDA automatic policies.
For every dataset, metric, `k`, target, and independent query seed it records:

- identifier-overlap mean query recall;
- tie-aware recall, with unmatched boundary candidates exactly rescored;
- a deterministic one-sided 95% query-bootstrap lower confidence bound;
- the 5th percentile and minimum of query-level tie-aware recall as lower-tail
  diagnostics;
- the frequency and credit magnitude of observed boundary substitutions; and
- three timing repetitions, explicitly treated as runtime repetitions rather
  than three independent recall samples.

Approximate target attainment requires the tie-aware lower confidence bound to
meet the requested target for both independent query seeds. Exact-family routes
remain eligible through the separate exactness audit.

This is an empirical query-bootstrap bound for the uniformly sampled audited
rows. It is not a distribution-free guarantee for all rows or for a new
dataset. Timing repetitions reuse the same audited queries and therefore do not
increase the recall sample size.

The audit job also runs a prespecified sensitivity analysis on flow18, mass41,
and ImageNet. It compares 128, 256, 512, and up to 1,024 audited queries, and
1,000 versus 5,000 bootstrap resamples. Query counts below the available sample
use 50 deterministic without-replacement subsamples. The analysis reports
decision stability and the 5th percentile of query-level recall; it does not
claim to replace a label- or density-stratified audit.

Submit from an HPC compute or interactive node after synchronizing the code:

```bash
cd /scratch/firenze/NN
export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=<version-inside-the-image>
export FAISSR_PACKAGE_COMMIT=<40-character-commit-inside-the-image>
bash benchmark_scripts/jss_reproduction/validation/recall_inference/submit_recall_inference.sh
```

The manuscript target-attainment tables must not be regenerated until the audit
report is complete.
