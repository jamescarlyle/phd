#!/bin/bash -l

set -euo pipefail

module purge
module load python/3.14.0 gcc/16.1.0
source "$HOME/brian2-stdp/.venv/bin/activate"

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export MPLBACKEND=Agg
export PYTHONUNBUFFERED=1

export SIGMA_THRESHOLD_MV="${SIGMA_THRESHOLD_MV:?SIGMA_THRESHOLD_MV must be set}"
export N_NEURONS="${N_NEURONS:?N_NEURONS must be set}"
export SEED="${SEED:-42}"
export N_TRAIN="${N_TRAIN:-1000}"
export N_OBSERVE="${N_OBSERVE:-1000}"
export N_TEST="${N_TEST:-200}"

PROJECT="$HOME/brian2-stdp"
MODEL="${DIEHL_MODEL:-$PROJECT/diehl.py}"

RUN="/scratch/$USER/brian2-sigma/${SLURM_JOB_ID}-${SIGMA_THRESHOLD_MV}mV-${N_NEURONS}neuron"
mkdir -p "$RUN"
export DATA_PATH="$RUN/data"
export MNIST_PATH="$PROJECT/mnist"

cp "$MODEL" "$RUN/diehl.py"
cd "$RUN"

cat > parameters.txt <<EOF
sigma_threshold_mV=$SIGMA_THRESHOLD_MV
n_neurons=$N_NEURONS
seed=$SEED
n_train=$N_TRAIN
n_observe=$N_OBSERVE
n_test=$N_TEST
slurm_job_id=${SLURM_JOB_ID:-local}
EOF

python -u -c 'import sys, numpy, brian2; print("Python:", sys.executable); print("NumPy:", numpy.__version__); print("Brian2:", brian2.__version__)'

for stage in train observe test; do
    printf '\nStarting stage: %s\n' "$stage"
    python -u diehl.py "$stage"
done

touch COMPLETED
