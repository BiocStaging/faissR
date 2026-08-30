# Leave-one-dataset-out selector sensitivity

For each held-out dataset and backend/metric/k/target cell, the cross-fitted analysis excludes every row from that named dataset before selecting a method family. It first uses the same predeclared shape group; when that group is absent, it uses the three nearest training datasets in log(n)-log(p) space. It maximizes complete qualifying dataset coverage and then minimizes median log runtime.

A cross-fitted operating point passes when the held-out route is complete and is either exact-audited or, for an approximate route, its mean query recall@k meets the requested threshold in every prespecified validation replicate. Exact selection and approximate target attainment are reported separately. Minimum query recall is not used for eligibility.

The installed package `method = "auto"` result is reported separately as a non-independent diagnostic because its compiled policy summarizes the full calibration collection. It is not presented as leave-one-dataset-out evidence.

Held-out cells: 324.
Cross-fitted operating points attained: 301.
Cross-fitted abstentions: 4.
Cross-fitted exact selections: 11.
Cross-fitted method-family agreements with the held-out empirical oracle: 292.
