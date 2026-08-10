---
marp: true
theme: default
header: 'James Carlyle Neuromorphic Research Update 2026/07/27'
headingDivider: 1
footer: ''
style: |
  footer {
    font-size: 0.6em;
  }
  section {font-size: 1.1em}
---
# Two routes for PhD research

James Carlyle 
2026-2029
University of Southampton
AI for Sustainability CDT
Supervisors: Dr. Firman Simanjuntak, Prof. Mark Zwolinski

# DVS-free spiking camera: Goal
**What?** : Develop a low-cost, low-power event-based camera using memdiodes and threshold memristors that generates sparse spike streams from brightness changes, giving sparse data with low latency.
**How?** : Fabricate nanodevice-based memdiodes / threshold memristors; characterise their electrical and material properties; develop temporal signal encodings; simulate device-to-system behaviour; and implement real-time event processing and AI inference on an FPGA-based spiking neural network.
**Why, and why now?** : Frame-based cameras transmit unchanged pixels, imposing compute costs in dynamic scenes. Event-driven vision is valuable for latency-critical motion perception, robotics, industrial inspection, and autonomous systems. Existing DVS cameras e.g. Sony/Prophesee are expensive, power-hungry. Makes use of world-class Zepler cleanrooms.
**Measure** : Device yield, variability, endurance, and switching characteristics. Quantify event-encoding quality: event rate, temporal precision, noise, dynamic range, reconstruction fidelity, and robustness to illumination and motion.
- Benchmark against a conventional frame-based baseline and a DVS-based baseline: end-to-end latency, energy, bandwidth reduction, accuracy, and system cost for a real-world task such as gesture recognition or anomaly detection.

# DVS-free spiking camera: Timeline
## Year 1
- Design and fabricate camera memdiode / threshold memristor arrays using thin-film deposition, lithography, and cleanroom processing.
- Use microscopy and spectroscopy to assess film quality, interfaces, morphology, and device uniformity.
- Electrically characterise individual devices and arrays: threshold behaviour, switching speed, retention, endurance, variability, and power consumption.
- Develop compact device and circuit models that connect measured nanodevice behaviour to system-level simulation.
# DVS-free spiking camera: Timeline
## Year 2
- Develop spike encoding protocols for conventional camera image signals.
- Simulate the sensing-to-event pipeline, including device non-idealities, noise, mismatch, bandwidth limits, and illumination variation.
- Design event representation and downstream AI processing to minimise data movement while preserving task-relevant information.
- **Paper** Benchmark encoding quality and predicted system performance against frame-based processing and DVS-like event representations.
## Year 3
- Integrate a conventional camera, event encoder, FPGA, and event-based AI algorithm into an end-to-end demonstrator.
- Implement real-time processing, event encoding, inference, and output on FPGA hardware.
- Test reliability under real-world conditions: variable lighting, rapid motion, clutter, sensor noise, temperature variation, and long-duration operation.
- Measure end-to-end latency, power, bandwidth, accuracy, throughput, device stability, and fabrication costs.
- **Paper** A real-time DVS-free spiking-camera demonstrator with quantified performance against appropriate frame-based and DVS benchmarks.

# DVS-free spiking camera: Risks / challenges
- Switching thresholds may vary across a wafer, reducing uniformity of event generation; mitigate through process control, array-level calibration, redundancy, and variation-aware encoding.
- Memdiodes may exhibit cycle-to-cycle variation, temperature sensitivity, ageing, or stochastic switching; quantify these effects early and incorporate compensation into circuit and FPGA logic.
- Spike encoding may not properly preserve task-relevant motion information; co-optimise the encoder, event representation, and AI model against end-task metrics.
- A dynamic scene can create event bursts that overwhelm FPGA resources; use adaptive thresholds, local filtering, event-rate control, and hardware-efficient sparse processing.
- Peripheral operation e.g. ADCs, memory access, FPGA may dominate the sensor energy consumption.
- Compare matched tasks, lighting conditions, resolutions, latency budgets, and accuracy targets.
- Cleanroom fabrication can be slow and expensive; maintain simulation and FPGA workstreams in parallel so system progress does not depend solely on each fabrication cycle.

# DVS-free spiking camera: Sustainability use-cases
- **Battery-powered edge sensing:** Sparse, event-driven processing can reduce unnecessary data capture and communication for remote cameras, enabling longer-lived battery or solar-powered deployments. Event-based vision is inherently suited to low-latency, resource-constrained edge applications.
- **Industrial predictive maintenance:** Detect abnormal motion, vibration-correlated visual changes, conveyor faults, or machine-state transitions locally, avoiding continuous high-bandwidth video transmission.
- **Smart buildings and cities:** Support occupancy, flow, safety, and traffic monitoring with change-focused processing, reducing compute and network load compared with continuously streaming full video.
- **Robotics and autonomous platforms:** Improve reaction speed for mobile robots, drones, and automated vehicles operating under tight power and latency budgets.
- **Agriculture and environmental monitoring:** Low-power detection of animal movement, crop activity, pests, or environmental change in remote locations where connectivity and energy are limited.

# End to end analog perceptron: Goal
**What?** : Produce a working low-energy spiking neural network perceptron based on event-based sensors and analog nano-scale devices.
**How?** : Utilise memristive crossbar arrays to represent synapses, and either 1) Threshold memristor+capacitor or 2) anti-ferroelectric FET (AFeFET) devices for leaky integrate-and-fire behaviour. Characterise their electrical and material properties, simulate device-to-system behaviour; 
**Why, and why now?** : Hasn't been done before. New materials offer nano-scale, CMOS-friendly, high-endurance (10^12), ultra low-energy (27fJ) analog-only opportunity. Makes use of world-class Zepler cleanrooms.
**Measure** : Achieve nn% accuracy on benchmark spiking datasets, e.g. N-MNIST digits, DVS-Gesture. Preferably use natural environment data - later section.

NB Memristor-based neuron requires additional capacitance: 1S1R diodes have ~1fF, while AFeFET have ~10fF.

# End to end analog perceptron: Timeline 
## Year 1
- Confirm project feasibility, especially Zepler fabrication capabilities and cost.
- Confirm network training approach in software e.g. reward-modulated spike timing dependency plasticity on Spyx. Benchmark performance.
- Characterise threshold-memristor+capacitor / AFeFET and memristor devices using physical devices loaned to Southampton. Measure device non-ideality: transfer curves, update symmetry, retention, endurance, temperature sensitivity, and device-to-device variance. Good outcome: Response captured by a compact model that remains usable across runs.
- Produce Spyx custom neuron model using obtained characteristics e.g. membrane, threshold dynamics, refractory behaviour.
- **Paper** Simulate Spyx perceptron 3-layer network using device characteristics and variability, benchmark performance and energy consumption.
# End to end analog perceptron: Timeline 
## Year 2
- Export NIR network model or construct Verilog model.
- **Paper** Implement perceptron on FPGA, measure performance and energy consumption.
- (Maybe) Fabricate single-device neurons, measure performance.
## Year 3
- Design multi-layer analog hardware model of perceptron network.
- Commission fabrication of analog hardware model. 
- **Paper** Measure performance and energy consumption, compare with software and FPGA benchmarks.

# End to end analog perceptron: Risks / challenges (particularly for AFeFET approach)
- For AFeFET: No prior experience of anti-ferroelectric materials in Zepler cleanroom. Devices produced to date in China, Asia, US. Is it even possible to borrow a device for characterisation?
- Phase and stack sensitivity: AFeFET behavior depends on the HfZrO phase, thickness, electrode choice, and anneal. A small deviation can shift from useful anti-ferroelectric response to inconsistent switching, or hysteretic behavior that is too abrupt, too noisy, or too asymmetric.
- Analog learning is strict. A multi-layer analog perceptron needs repeatable states, making the system more vulnerable to variation and nonlinearity.
- Integration introduces additional failure modes and calibration work.
- Cleanroom fabrication can be slow and expensive.
**De-risk Approach**
- Start with a single-device and small-array characterization phase before committing to a full multilayer network.
- Defer fabrication, borrow before build. Measure most significant properties: state count, symmetry, update linearity, retention, endurance, and cycle-to-cycle noise.
- Ensure algorithm can absorb measured nonidealities rather than assuming ideal weights.
- Benchmark using low-cost simulation approach first.
- Reuse existing fabrication recipes.
- Treat the first output as process-validation, not a final results.
- Maintain simulation and FPGA workstreams in parallel so progress does not depend solely on each fabrication cycle.

# End to end analog perceptron: Sustainability use-cases
- Acoustic biodiversity monitoring.
- Rain / wind / storm onset detection.
- Event-camera monitoring of wildlife, waves, fire, or vegetation motion.
- Seismic or microseismic event detection.
- Threshold-based sensor networks for distributed environmental monitoring.
