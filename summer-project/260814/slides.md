---
marp: true
theme: default
header: 'James Carlyle Neuromorphic Research Update 2026/08/07'
headingDivider: 1
footer: ''
style: |

  section {font-size: 0.9em}
---
# Research Questions

### RQ1 – CMOS‑compatible scalable SNN architecture
What memristor–CMOS co‑designs for synapses and neurons enable a scalable, multilayer spiking neural network that can be fabricated using the
CMOS processes available at Zepler? Within this constraint, which crossbar topologies, neuron circuit models (e.g. LIF variants),
and spike‑routing schemes jointly optimise trainability, energy per spike, and silicon area for edge‑scale event‑based workloads?

### RQ2 – Efficient on‑chip learning for multilayer memristor SNNs
Which on‑chip learning algorithms—such as STDP/VDSP and hardware‑feasible approximations to spiking backpropagation—can be implemented efficiently in
multilayer memristor SNNs, and how do their accuracy, convergence speed, and energy per update compare to ex‑situ training
with weight transfer under realistic device non‑idealities?

### RQ3 – Robustness and exploitation of device variability
What levels of device‑to‑device and cycle‑to‑cycle variability in memristor synapses and neurons can a multilayer SNN tolerate before task accuracy
degrades beyond a defined threshold, and how can on‑chip learning rules be designed so that such variability either remains harmless or
actively improves training speed and final accuracy?

### RQ4 – System‑level performance on event‑based tasks
Can a multilayer memristor SNN with on‑chip learning achieve competitive task accuracy, energy per event, and latency on representative
event‑based vision or time‑series benchmarks compared with state‑of‑the‑art software ANN/SNN baselines, when implemented under Zepler‑compatible
CMOS and realistic memristor non‑idealities?
