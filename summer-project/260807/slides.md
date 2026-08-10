---
marp: true
theme: default
header: 'James Carlyle Neuromorphic Research Update 2026/08/07'
headingDivider: 1
footer: ''
style: |

  section {font-size: 0.9em}
---
# Event Processing and Spiking Neural Networks

James Carlyle

7 August 2026
Dr. Firman Simanjuntak, Prof. Mark Zwolinski
AI for Sustainability CDT
University of Southampton

# Research Questions (draft)

## RQ1 – Architecture

How can memristor–CMOS hybrid synapse and neuron circuits be architected to implement a scalable multilayer spiking neural network core that supports on‑chip learning while remaining compatible with CMOS processes available at Zepler?

What crossbar topology, neuron models, and spike‑routing schemes best balance trainability, energy efficiency, and area for edge‑scale event‑based processing?

## RQ2 – On‑chip learning and FPGA co‑design

Which on‑chip learning algorithms (e.g. STDP / VDSP and supervised spiking backprop approximations) can be realised efficiently in hardware for multilayer memristor–CMOS SNNs, and how do they perform versus ex‑situ training plus weight transfer?

How can FPGA‑based SNN prototypes be co‑designed to act both as a rapid experimentation platform and as a training controller for the analog core, including write‑verify of memristive synapses and closed‑loop evaluation?

## RQ3 – System‑level performance and robustness

Can a multilayer memristor–CMOS SNN with on‑chip learning achieve competitive accuracy, energy per event, and latency on representative event‑based vision or time‑series tasks compared with FPGA‑only and software SNN baselines?

How robust is the trained hardware to device variations and input noise, and what design rules emerge for scaling trainable memristive SNNs?

# Proposed methods and research approach (1/2)

## Diffusive memristor characterisation

Use existing fabricated diffusive memristors to characterise device behaviour, with a particular focus on device-to-device, cycle-to-cycle and stochastic variability ("variability statistical model").

Implement variability model in software emulation of a single, simple neuron. Convert memristor variability into neuron behaviour variability.

Implement simulation of on-chip learning (STDP and VDSP) in software, for single, simple neurons (pre/post-synaptic), initially without variability. Introduce the variability statistical model created earlier.

Evaluate the impact of variability on learning speed and accuracy. 

Move to a larger network, where feature extraction and differentiation becomes important. Understand whether variability assists in feature / node differentiation is assisted/accelerated by variability, or whether there is a point at which excessive variability becomes catastrophic for network performance.

Define an allowable variability specification.

## Memdevice and circuit design

Use existing memdevice expertise to select, design and fabricate CMOS‑compatible memristor stacks with suitable characteristics (tuning, endurance, variability, and process compatibility).

Design hybrid synapse cells (e.g. 1S1R) and neuron circuits (e.g. LIF 1M1T1R neurons) that operate at realistic voltage ranges and support pulse‑based conductance updates implementing STDP/VDSP or supervised learning rules.

Use SPICE/Verilog‑A simulation to validate crossbar and neuron behaviour, including parasitic effects and sneak paths.

## Compact modelling and multi‑scale simulation

Characterise fabricated devices and arrays to obtain IV curves, switching behaviour, endurance, retention, and variability, then fit compact models suitable for both circuit and network‑level simulation.

Integrate these models into a multi‑scale simulation stack linking device‑level dynamics to spiking network behaviour, using Python SNN frameworks for training and analysis.

## On‑chip learning schemes

Implement unsupervised STDP/VDSP‑based learning using local timing and pulse protocols that update memristor conductances based on spike correlations and presynaptic potentials.

Explore supervised learning schemes adapted to hardware, such as approximate backpropagation in the spiking domain, where error signals are encoded as additional spike trains or weight‑update pulses orchestrated by the FPGA controller.

Compare ex‑situ training (software or FPGA SNN trained first, then weights programmed into crossbars) to in‑situ training (updates performed directly in hardware) under realistic device constraints.

# Proposed methods and research approach (2/2)

## FPGA co‑design and system integration

Develop FPGA‑based SNN implementations with equivalent neuron and learning rules, using Verilog and existing FPGA neuromorphic design practices.

Design the FPGA–analog interface: configuration bus, spike streaming, monitoring channels, and training control (write‑verify loops, error computation).

Integrate a suitable event source (e.g. existing time‑series dataset) to provide real inputs to both FPGA and analog SNNs for comparative evaluation.

## Evaluation and analysis

Evaluate accuracy, energy per event, latency, and robustness on chosen tasks; compare across analog SNN, FPGA SNN, and software baselines using consistent metrics and datasets.

Perform sensitivity analyses to quantify the impact of device variability, limited conductance precision, and learning rule parameters on long‑term performance and stability.

# Indicative timetable

## Year 1

Complete formal literature review on memristor–CMOS neuromorphic chips, on‑chip learning in SNNs, and FPGA SNN accelerators.

Design and implementation of simple (single, 2 synapse/ 1 neuron) and multilayer FPGA SNN prototypes; establishment of software + FPGA evaluation pipeline.

Architectural specification for the memristor–CMOS SNN core and initial simulation models.

## Year 2

Design and simulation of memristor synapse and CMOS neuron circuits; layout of small crossbar arrays.

Fabrication of test structures at Zepler; device and array‑level characterization; development of compact models.

## Year 3

Implementation of on‑chip learning schemes (STDP and supervised variants) in the memristor–CMOS core; demonstration of learning on small tasks.

Integration of FPGA platform and analog SNN core; end‑to‑end demonstrations with real inputs; comparative evaluation against FPGA‑only and software SNN baselines.

Sensitivity and robustness studies; derivation of design guidelines and preparation of main publications.

Consolidation of results into the thesis; further publications; optional exploratory work on AFeFET‑based synapse/neuron concepts as future extensions.
