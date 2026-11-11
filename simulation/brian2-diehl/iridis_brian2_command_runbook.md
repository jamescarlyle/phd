# Iridis Brian2 sigma sweep: repeatable terminal runbook

This is the deduplicated command sequence for the working Iridis X setup established on 30 October 2026. It runs independent experiments, not a parallelised Brian2 simulation.

## Files to retain with this runbook

- The parameterised, working diehl.py.
- diehl_sigma.slurm from the sigma-sweep attachment.
- The four unpacked MNIST IDX files in mnist/.
- requirements-iridis.txt once the working environment is frozen.

The runbook assumes these files are in ~/brian2-stdp on Iridis. The model must already read SIGMA_THRESHOLD_MV, SEED, N_TRAIN, N_OBSERVE, N_TEST, MNIST_PATH and DATA_PATH from the environment, accept train/observe/test arguments, and assign:

```python
ng_exc.sigma_threshold = SIGMA_THRESHOLD_MV * mV
```

The sigma assignment must precede the initial noise draw. This is a noise-standard-deviation sweep, not a baseline-threshold sweep. The attached batch file provides the confirmed modules, separate run directories and stage sequencing.

## 1. Connect and transfer, if starting with only the Mac copy

On the Mac, use the actual external login address previously used to reach Iridis X. IRIDIS_LOGIN_HOST below is a placeholder: the conversation established loginX002 as an internal node name, not the external SSH address.

```bash
export IRIDIS_REMOTE=jc6n25@IRIDIS_LOGIN_HOST
ssh "$IRIDIS_REMOTE" 'mkdir -p ~/brian2-stdp'

cd ~/brian2-stdp
rsync -avP \
  --exclude='.venv/' \
  --exclude='__pycache__/' \
  --exclude='.git/' \
  --exclude='data/' \
  --exclude='logs/' \
  --exclude='iridis-results/' \
  ./ "$IRIDIS_REMOTE:brian2-stdp/"

ssh "$IRIDIS_REMOTE"
```

The Mac project directory must contain diehl_sigma.slurm and the unpacked mnist/ directory before transfer. A Mac virtual environment is not transferred.

## 2. Establish the Iridis environment

On Iridis:

```bash
cd ~/brian2-stdp

if type deactivate >/dev/null 2>&1; then deactivate; fi
module purge
module load python/3.14.0 gcc/16.1.0

python -m venv .venv
source .venv/bin/activate

python -m pip install --upgrade pip
if [ -s requirements-iridis.txt ]; then
    python -m pip install -r requirements-iridis.txt
else
    python -m pip install 'brian2==2.11.0' 'numpy==2.5.4' scipy cython matplotlib progressbar2
fi

python -m pip check
python -m pip freeze > requirements-iridis.txt
```

The Python, GCC, NumPy and Brian2 versions above were confirmed working on ruby049. The requirements file is the preferred record for reproducing the complete package environment. The fallback only pins the two observed scientific-package versions; it is not a complete lockfile.

For an existing environment, the venv creation and installation commands are setup steps, not required before every submission.

## 3. Verify configuration and imports

```bash
module list
sinfo -p amd -o '%P %l'
python -u -c 'import sys; print("Python:", sys.executable, flush=True); import numpy; print("NumPy:", numpy.__version__, numpy.__file__, flush=True); import brian2; print("Brian2:", brian2.__version__, flush=True)'

grep -nE 'sigma_threshold|SIGMA_THRESHOLD_MV' diehl.py
grep -nE '^#!|^#SBATCH|module load|activate|SIGMA_THRESHOLD_MV|RUN=' diehl_sigma.slurm
bash -n diehl_sigma.slurm
```

Confirmed settings:

```text
Python module: python/3.14.0
GCC module:    gcc/16.1.0
Partition:     amd
Walltime cap:  2-12:00:00 = 60 hours
Array:         0-5%6
Task mapping:  task ID = sigma in mV
```

These are recorded values, not a guarantee that the configuration will remain unchanged a month later. Check the actual output rather than substituting the earlier incorrect red partition or guessed module versions.

## 4. Snapshot the model once per sweep

```bash
mkdir -p logs
MODEL_SNAPSHOT=$(mktemp "$PWD/diehl-sigma-XXXXXXXX.py")
cp diehl.py "$MODEL_SNAPSHOT"
```

Keep the snapshot until the submitted jobs have finished. The batch file reads DIEHL_MODEL and copies that snapshot into each experiment directory. No source edits are needed between sigma values.

## 5. Submit the short sweep

```bash
ARRAY_ID=$(DIEHL_MODEL="$MODEL_SNAPSHOT" N_TRAIN=1000 N_OBSERVE=1000 N_TEST=200 SEED=42 \
  sbatch --parsable diehl_sigma.slurm)
ARRAY_ID=${ARRAY_ID%%;*}
printf '%s\n' "$ARRAY_ID" | tee last-smoke-array-id.txt
```

This submits six independent pipelines at sigma 0, 1, 2, 3, 4 and 5 mV. The batch file's default walltime is two hours. The %6 cap permits up to six tasks concurrently, subject to scheduling and account limits. [web:39]

Inspect this array using the monitoring commands below. Continue to the full sweep only after the short pipelines succeed.

## 6. Submit the full sweep

```bash
ARRAY_ID=$(DIEHL_MODEL="$MODEL_SNAPSHOT" N_TRAIN=60000 N_OBSERVE=2000 N_TEST=1000 SEED=42 \
  sbatch --parsable --time=1-06:00:00 diehl_sigma.slurm)
ARRAY_ID=${ARRAY_ID%%;*}
printf '%s\n' "$ARRAY_ID" | tee last-full-array-id.txt
```

Each task receives its own 30-hour walltime, within the recorded 60-hour partition cap. The command-line time overrides the two-hour default. [web:126]

At the observed approximate rate of 20 minutes per 1,000 training presentations, 60,000 extrapolates to roughly 20 training hours, plus observation and testing. Actual runtime can vary with sigma and retries.

The same model snapshot should be retained for seed replicates. Repeating the full submission with SEED=43 or SEED=44 creates separate arrays. Do not change the simple array range to 0-17: this batch file maps task ID directly to sigma.

## 7. Monitor any submitted array

ARRAY_ID is set by the submission commands. After reconnecting, restore it with either:

```bash
ARRAY_ID=$(cat last-full-array-id.txt)
```

or use last-smoke-array-id.txt for the smoke sweep.

```bash
squeue -r -j "$ARRAY_ID" -o '%.18i %.9P %.20j %.2t %.10M %N'
```

The final column is the execution node. A loginX002 terminal prompt does not mean that the simulation is running on the login node.

Choose one sigma, for example 3 mV:

```bash
SIGMA=3
tail -f "logs/diehl-sigma-${ARRAY_ID}_${SIGMA}.err"
```

The progress display is in stderr, not the .out startup log. Ctrl-C stops the log viewer, not the scheduled job.

For a readable progress snapshot and startup/configuration output:

```bash
tr '\r' '\n' < "logs/diehl-sigma-${ARRAY_ID}_${SIGMA}.err" | tail -n 30
cat "logs/diehl-sigma-${ARRAY_ID}_${SIGMA}.out"
```

After tasks leave the queue:

```bash
sacct -j "$ARRAY_ID" --format=JobID,State,Elapsed,ExitCode
```

A header-only squeue output is not proof of success. Check sacct and the application logs. [web:61]

## 8. Check final results

```bash
RESULTS="/scratch/$USER/brian2-sigma/$ARRAY_ID"
find "$RESULTS" -name COMPLETED -print
grep -H 'Accuracy:' logs/diehl-sigma-"${ARRAY_ID}"_*.out
ls -lh "$RESULTS/3/data/"
```

The batch file creates COMPLETED only after train, observe and test all return successfully. Expected model outputs include weights.npy, theta.npy, assign.npy and confusion.npy. The simple sigma batch file does not automatically create the CSV summaries from the earlier, separate AST-adapter bundle.

## 9. Retrieve results to the Mac

On the Mac, set the actual array ID printed at submission:

```bash
export IRIDIS_REMOTE=jc6n25@IRIDIS_LOGIN_HOST
ARRAY_ID=REPLACE_WITH_ARRAY_ID
mkdir -p "$HOME/brian2-stdp/iridis-results/$ARRAY_ID/logs"

rsync -avP \
  "$IRIDIS_REMOTE:/scratch/jc6n25/brian2-sigma/$ARRAY_ID/" \
  "$HOME/brian2-stdp/iridis-results/$ARRAY_ID/"

rsync -avP \
  "$IRIDIS_REMOTE:brian2-stdp/logs/diehl-sigma-${ARRAY_ID}_*" \
  "$HOME/brian2-stdp/iridis-results/$ARRAY_ID/logs/"

rsync -avP \
  "$IRIDIS_REMOTE:brian2-stdp/requirements-iridis.txt" \
  "$HOME/brian2-stdp/iridis-results/$ARRAY_ID/"
```

Keep the parameterised model, batch file, requirements and this runbook together. Important outputs should not be left only on scratch. [web:28]

## 10. Cancel only when necessary

Cancel the entire array:

```bash
scancel "$ARRAY_ID"
```

Or only sigma 3 mV:

```bash
scancel "${ARRAY_ID}_3"
```

Cancellation is not checkpointing. The supplied model/batch file does not automatically resume interrupted training. [web:39]

## Troubleshooting only: compute-node import check

Use this only if imports work on the login node but fail inside a job:

```bash
srun --partition=amd --nodes=1 --ntasks=1 --cpus-per-task=1 --mem=1G --time=00:05:00 bash -lc '
set -e
module purge
module load python/3.14.0 gcc/16.1.0
source "$HOME/brian2-stdp/.venv/bin/activate"
hostname
module list
python -u -c "import sys; print(\"Python:\", sys.executable, flush=True); import numpy; print(\"NumPy:\", numpy.__version__, numpy.__file__, flush=True); import brian2; print(\"Brian2:\", brian2.__version__, flush=True)"
'
```

Do not reinstall NumPy based solely on the generic source-directory error. Capture the direct NumPy traceback in the actual failing environment first.

## Commands deliberately excluded from the main workflow

- The invalid red partition.
- Guessed python/3.12 and gcc/13.2.0 module names.
- The earlier baseline-threshold-offset sweep: this runbook varies sigma instead.
- Running bash diehl_sigma.slurm or python diehl.py directly on a login node.
- Repeated environment recreation, speculative NumPy reinstalls, and old job IDs.


DIEHL_MODEL="$MODEL_SNAPSHOT" N_TRAIN=60000 N_OBSERVE=10000 N_TEST=10000 SEED=42 sbatch --time=1-06:00:00 diehl_sigma.slurm
