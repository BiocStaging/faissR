# CPU automatic-selection validation

This workflow independently evaluates the CPU `method = "auto"` policy with one
version-pinned package build. Each Slurm-array task contains one
dataset-by-metric-by-k-by-target cell and its six prespecified validation
replicates. This prevents a slow dataset from blocking unrelated cells.
Timeouts and execution failures are retained as outcomes.

The completion array tests the installed CPU policy on independent query
samples. The existing held-out analysis is a separate experiment: it performs
leave-one-dataset-out (LOODO) selection from explicit method routes, excludes
the named test dataset before choosing a route, and reports target attainment,
method agreement, exact-selection/abstention frequency, and the
selected-route/oracle time ratio.

```bash
cd /scratch/firenze/NN

export SINGULARITY_IMAGE=/scratch/firenze/NN/singularity/fastembedr_cuda.sif
export EXPECTED_FAISSR_VERSION=0.99.25
export FAISSR_PACKAGE_COMMIT=b33a70116887474a2ed70d84de0c80bb77e9db66
export CAMPAIGN_RESULTS_ROOT=/scratch/firenze/NN/faissR_JMLR_MLOSS/final_campaign

AUTO_JOB=$(sbatch --parsable \
  --export=ALL,SINGULARITY_IMAGE="$SINGULARITY_IMAGE",EXPECTED_FAISSR_VERSION="$EXPECTED_FAISSR_VERSION",FAISSR_PACKAGE_COMMIT="$FAISSR_PACKAGE_COMMIT" \
  benchmark_scripts/jss_reproduction/validation/cpu_auto_selection/run_cpu_auto_validation_cpu12.sh)

sbatch --dependency=afterany:"$AUTO_JOB" \
  benchmark_scripts/jss_reproduction/validation/cpu_auto_selection/run_cpu_auto_selection_audit_cpu12.sh
```

CPU LOODO uses the explicit held-out routes from the version-pinned campaign
and does not depend on the CPU-auto array. Submit the existing held-out
analysis only when reproducing that cross-fitted result:

```bash
sbatch --export=ALL,\
SINGULARITY_IMAGE="$SINGULARITY_IMAGE",\
EXPECTED_FAISSR_VERSION="$EXPECTED_FAISSR_VERSION",\
FAISSR_PACKAGE_COMMIT="$FAISSR_PACKAGE_COMMIT",\
CAMPAIGN_RESULTS_ROOT="$CAMPAIGN_RESULTS_ROOT",\
SINGULARITYENV_FAISSR_IMAGE_COMMIT="$FAISSR_PACKAGE_COMMIT",\
APPTAINERENV_FAISSR_IMAGE_COMMIT="$FAISSR_PACKAGE_COMMIT" \
benchmark_scripts/jss_reproduction/final_campaign/analysis/run_held_out_analysis_cpu12.sh
```

The CPU-auto assessment and LOODO assessment are reported separately: the
first tests the installed policy on independent queries, while the second
excludes each named dataset before reconstructing a route choice.
