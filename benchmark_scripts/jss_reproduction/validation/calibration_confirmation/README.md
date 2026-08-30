# Replicated calibration confirmation

The original wide parameter grids remain the screening stage. This module
creates a prespecified confirmation set for every dataset/metric/k/target cell:
the three fastest feasible screening candidates plus the fastest candidate from
each additional method family lying within 25% of the screening winner, capped
at five candidates.

Every retained candidate is timed five times in an isolated R worker. Execution
order is randomized reproducibly within each Slurm cell. The confirmed winner
minimizes median elapsed time, with deterministic tie-breaking by recall,
method, and candidate identifier.

The audit reports configuration-selection stability, method-family stability,
elapsed-time IQR/MAD/CV, regret from the original single timing, and the number
of winner changes whose robust median differs by no more than 5%. Results are
kept separate from the screening archive and do not alter package policy until
the audit has passed and the confirmed policy is compiled deliberately.

For each operating cell, the robust winner is the target-eligible retained
candidate with the smallest median of five elapsed times. Exact-audited routes
are eligible by exactness; approximate routes must attain the requested mean
query recall in every confirmation repetition. Configuration stability is the
fraction of repetitions in which that candidate is fastest, and method-family
stability is the corresponding fraction for its method. One-run selection
regret is

```text
median time of the screening winner / median time of the robust winner.
```

This regret is conditional on the prespecified confirmation set rather than
the full screening grid. Candidate-level output includes the median, quartiles,
MAD, coefficient of variation, minimum confirmed recall, and repeat count. The
audit fails on failed runs, missing candidates, duplicate candidate-repeat
rows, incomplete repetition counts, or a cell without an eligible candidate.

From `/scratch/firenze/NN`, export the image, expected package version,
40-character package commit, and the explicit path to the completed screening
`calibration/real` directory as `CALIBRATION_RESULTS_ROOT`; then run
`submit_confirmation.sh`. The helper
submits manifest preparation, separate 324-cell CPU and CUDA arrays, and a
dependent audit. The projected screening-time total for five repetitions was
approximately 92 CPU node-hours and 18.5 GPU-hours before data-loading and
queue overhead; actual wall time depends on the cluster.
