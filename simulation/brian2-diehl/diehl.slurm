#!/bin/bash
#SBATCH --job-name=diehl-mnist
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --reservation=none
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

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

PROJECT="$HOME/brian2-stdp"
RUN="/scratch/$USER/brian2-stdp/$SLURM_JOB_ID"

mkdir -p "$RUN"

export DATA_PATH="$RUN/data"
export MNIST_PATH="$PROJECT/mnist"
export N_TRAIN="${N_TRAIN:-60000}"
export N_OBSERVE="${N_OBSERVE:-2000}"
export N_TEST="${N_TEST:-1000}"
export SEED="${SEED:-42}"

cp "$PROJECT/diehl.py" "$RUN/diehl.py"
cd "$RUN"

hostname
python -m pip freeze > requirements.txt
printf 'Output directory: %s\n' "$DATA_PATH"

/usr/bin/time -v python -u diehl.py train
/usr/bin/time -v python -u diehl.py observe
/usr/bin/time -v python -u diehl.py test
