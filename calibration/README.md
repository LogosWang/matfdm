# Decoupled calibration (restarted 2026-08-04)

This controller starts from GitHub commit `52ecfd7` and uses the ten values in
that commit's `build_p_decouple.m` as multiplier 1.  It does not import a
candidate, result, or checkpoint from the pre-clone task.

Targets and constraints are unchanged: total-oxide 1 nm fronts at doses
0/0.5/3 target 40/60/100 nm, with 60--70 nm a low-weight soft band at 0.5 dpa;
Cr is the largest oxidized-metal atomic fraction at every dose; oxidized Cr
inventory strictly decreases with dose; and at 3 dpa `Cr%-Fe% <= 15`.

The parameter order is `kCr,kFe,kSi,kspin,DCr2O3O,DFe3O4,DFeCr2O4,DSiO2,
kRobin,E_mag`.  These parameters are treated as a coupled ten-dimensional
system.  There is no kinetics/composition or transport/front block split.

## Search strategy

Generation 1 is sampled directly by persistent ask--tell active CMA-ES
(`pycma 4.4.4`, population 10) around the GitHub baseline in log-multiplier
space with `sigma=0.65`. Every later ten-case batch is one CMA population;
after all ten real evaluations finish, their rank
updates the mean, global step size, and complete 10x10 covariance matrix. No
parameter roles or blocks are prescribed.

Constraint handling is lexicographic: every actually feasible sample ranks
ahead of every infeasible sample; infeasible samples rank by normalized hard-
constraint violation and then target objective. Eight generations without a
new historical best, a severely ill-conditioned covariance, or a mature
pycma stop condition triggers a reproducible restart. Restarts alternate
between the historical best and a deterministic broad-domain center while
retaining the permanent fitness history.

The optimizer state is written atomically to `optimizer/cma_state.pkl` after
each ask. A retry re-emits the same pending population instead of advancing a
generation twice. Human-readable generation, covariance, mean, fitness
history, and proposal artifacts are archived with each batch.

## Isolation and operation

Every case/dose writes to `decouple/<case>/dose*` and
`checkpoint/<case>/decouple_dose*`; logs and metrics are also keyed by case.
The archived 2026-07-31 tree is never on a new run path.

Calibration post-processing is data-only: `fields_timeseries.mat`, all final
CSV files, and metric inputs are retained, while figure construction and PNG
export are skipped. `CALIB_ENABLE_PLOTS=1` is the explicit opt-in override for
non-production diagnostics.

```bash
CALIB_REPO_DIR=/mnt/c/Users/vool/matfdm_calibration_20260731 calibration/calibrate.sh start
calibration/calibrate.sh status
calibration/calibrate.sh stop
calibration/calibrate.sh resume
```

The controller checks every minute and launches all 30 R2025b single-threaded
legs in a generation in one startup pass. A two-second ServiceHost stagger
does not serialize the simulations. Failed legs are classified from only the
log bytes written by their last attempt (5001, access violation, OOM, license,
I/O, or fatal runtime), then restarted under the same case/dose and checkpoint
with exponential backoff. A leg is reaped only after 30 minutes without
checkpoint or log progress. A silent five-minute external watchdog restores a
missing controller; a four-hour OpenClaw audit is separate and user-visible.

Checkpoint saves use a temporary file followed by replacement, so an
interrupted write cannot truncate the last valid `checkpoint.mat`. The
controller quarantines zero-byte or unreadable checkpoints under
`calibration/quarantine/checkpoints/` and restarts only that same case/dose
from the beginning. A clean process exit gets a completion-file grace recheck
before restart to avoid duplicate work during Windows filesystem visibility
lag.

`pycma` is vendored under `calibration/vendor`; the pinned source dependency is
listed in `requirements-calibration.txt` so controller restarts do not depend
on a user-level Python installation.
