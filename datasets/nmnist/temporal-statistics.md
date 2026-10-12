# N-MNIST Temporal Statistics and Analog SNN Integration Summary

This document summarizes the quantitative properties of the Neuromorphic-MNIST (N-MNIST) dataset, theoretical integration horizons in spiking neural networks (SNNs), and hardware parameter considerations for fully connected analog implementations.

---

## 1. N-MNIST Dataset Properties and Spike Statistics

N-MNIST consists of 70,000 samples (60,000 train, 10,000 test) recorded using an Asynchronous Time-based Image Sensor (ATIS) mounted on an actuated pan-tilt unit executing a three-phase saccade trajectory over standard MNIST images.

- **Spatial and Channel Dimensions:** 34 × 34 pixels across 2 polarity channels (ON and OFF), yielding **2,312 discrete input lines**.
- **Recording Duration:** ~300 ms per sample (three consecutive ~100 ms saccadic movements).
- **Total Event Count:** Typically 4,000 to 5,000 events per digit sample (mean: ~4,100–4,600 events).
- **Global Event Rate:**
  - *Average:* 13.5 to 15.0 events/ms (13.5–15 kHz aggregate throughput).
  - *Peak:* 30.0 to 50.0 events/ms during mid-saccade maximum angular velocity.
- **Per-Pixel Event Rate:**
  - *Dataset-wide average:* ~6.0 × 10⁻³ events/pixel/ms (~6 Hz across inactive and active pixels).
  - *Active edge pixels:* 0.05 to 0.20 events/pixel/ms (50–200 Hz burst frequencies).
- **Inter-Spike Interval (ISI) Statistics:**
  - *Aggregate stream:* Mean ISI ($\mu$) ≈ 0.065–0.075 ms (65–75 µs); standard deviation ($\sigma$) ≈ 0.070–0.100 ms, consistent with an exponential/Poisson-like arrival distribution ($CV \approx 1.0\text{--}1.3$).
  - *Single active pixel:* Mean ISI ($\mu_{\text{pixel}}$) ≈ 5–20 ms during edge traversals; standard deviation ($\sigma_{\text{pixel}}$) ≈ 10–25 ms ($CV \ge 1.2$) due to saccade acceleration and deceleration profiles.

---

## 2. Theoretical Integration Horizons in SNNs

The required temporal duration of effective integration depends on the neural coding scheme, layer depth, and sensor dynamics:

- **Coding Paradigms:**
  - *Time-to-First-Spike (TTFS) / Latency Coding:* Requires only the initial wavefront of pulses (effective integration window of 1 to 5 ms, or 1 to 4 algorithmic time steps).
  - *Rate / Spike-Count Coding:* Governed by Poisson variance ($\sigma^2 = \mu = r \cdot T$); requires windows of 50 to 300 ms to achieve acceptable signal-to-noise ratios.
- **Dynamic Regime by Time Constant ($\tau_m$):**
  - *$\tau_m \le 1\text{--}5\text{ ms}$:* Coincidence detection mode; past input outside narrow windows is rapidly discarded.
  - *$\tau_m \approx 10\text{--}30\text{ ms}$:* Leaky integrator regime; temporal summation occurs across correlated bursts.
  - *$\tau_m > 50\text{--}100\text{ ms}$:* Evidence accumulation and working-memory timescales.
- **Event-Camera Saccade Windows:**
  - Classifying N-MNIST does not require processing all 300 ms; integrating a single saccade phase or a transient window of **10 to 30 ms** during peak edge contrast yields over 95% classification accuracy.

---

## 3. Parameter Sizing for a 2,312 $\rightarrow$ 100 $\rightarrow$ 10 Analog SNN

For an analog Leaky Integrate-and-Fire (LIF) network handling real-time N-MNIST inputs, membrane time constants ($\tau_m = R_m C_m$) must balance biological timescale alignment and analog hardware constraints.

### Layer-Wise Recommendations

| Parameter / Feature | Hidden Layer (100 Neurons) | Output Layer (10 Neurons) |
| :--- | :--- | :--- |
| **Target Time Constant ($\tau_m$)** | **10 ms to 30 ms** | **50 ms to 100 ms** |
| **Computational Function** | Spatio-temporal edge/stroke integration within a saccade | Class evidence accumulation over multiple saccades |
| **Risk if $\tau_m$ is Too Short** | Leaks away 5–20 ms pixel burst intervals; fails to summate | Fires prematurely on transient early noise spikes |
| **Risk if $\tau_m$ is Too Long** | Directional motion blur across successive saccade phases | Output saturation, DC drift, and delayed decision latency |

### Analog and Device Implementation Factors

- **Large Synaptic Fan-In (2,312 Inputs):**
  - High aggregate presynaptic conductance requires small input coupling weights, current attenuators, or subthreshold operation to prevent premature membrane saturation.
- **Volatile / Diffusive Memristive Neurons:**
  - Native threshold-switching relaxation times (e.g., in Ag/SiO₂ or NbOₓ devices) often sit in the sub-millisecond regime (10 µs to 1 ms).
  - Using such devices directly requires either augmenting membrane capacitance or **time-scaling (accelerating) event playback** by 10× to 100× to match device relaxation physics.
- **Subthreshold CMOS LIF Circuits:**
  - Realizing $\tau_m \approx 20\text{ ms}$ natively in silicon is achieved using compact integration capacitors ($C_{\text{mem}} \approx 0.5\text{--}2\text{ pF}$) paired with nano/pico-ampere subthreshold leak transistors ($I_{\text{leak}} \approx 10\text{--}50\text{ pA}$).
