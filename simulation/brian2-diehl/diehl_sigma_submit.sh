#!/bin/bash
set -euo pipefail

mkdir -p logs

for NEURON_INDEX in 0 1 2 3; do
    N_NEURONS=$(( 400 + 400 * NEURON_INDEX ))

    for SIGMA_THRESHOLD_MV in 0 1 2 3 4 5; do
        JOB_LABEL="diehl-sigma-${SIGMA_THRESHOLD_MV}mV-${N_NEURONS}neuron"

        sbatch \
            --job-name="$JOB_LABEL" \
            --partition=amd \
            --nodes=1 \
            --ntasks=1 \
            --cpus-per-task=1 \
            --mem=8G \
            --time=60:00:00 \
            --output="logs/${JOB_LABEL}-%A_%a.out" \
            --error="logs/${JOB_LABEL}-%A_%a.err" \
            --export=ALL,SIGMA_THRESHOLD_MV="$SIGMA_THRESHOLD_MV",N_NEURONS="$N_NEURONS",SEED="${SEED:-42}",N_TRAIN="${N_TRAIN:-60000}",N_OBSERVE="${N_OBSERVE:-10000}",N_TEST="${N_TEST:-10000}" \
            diehl_sigma.slurm
    done
done
