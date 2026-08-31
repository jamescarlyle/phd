Treat as a device-characterisation experiment driven by an event stream, not simply as applying a conventional SNN waveform. 
The key outputs are the conditional probability and latency of filament formation, the emitted current spike, and the subsequent volatile reset as functions of pulse amplitude, pulse width, inter-event interval, polarity, and recent stimulation history.

N-MNIST events contain x, y, polarity, and timestamps in microseconds; each recording is approximately 360 ms long, and the binary format assigns 23 bits to the timestamp and one bit to polarity [@see_st-mnist_2020]. 

For a target first-layer neuron, collapse the spatial events into one time-ordered stream and map each event to a pulse amplitude representing its synaptic weight.

## Hardware Abstraction Definition

For target neuron $j$, the event stream used is:

$$
\mathcal{E}_j = \bigl\{ (t_k, p_k, w_{j,x_k,y_k,p_k}) \bigr\}_{k=1}^{N_j},
$$

where:

- $t_k$ is the original N-MNIST timestamp.
- $p_k\in\{-1,+1\}$ is OFF or ON polarity.
- $w_{j,x_k,y_k}$ is the trained synaptic weight from that pixel and polarity channel.
- $N_j$ is the number of events delivered to the target neuron.

ON and OFF are separate input channels, so separate weights are used.

## Pulse Sequence Applied

Each N-MNIST event becomes a rectangular voltage pulse:

$$
V(t)=
\begin{cases}
V_k,&t_k\le t<t_k+t_\mathrm{pw}\\
0,&\text{otherwise}.
\end{cases}
$$

The pulse width is chosen carefully. If the original event spacing is shorter than the pulse width, pulses are merged or a pulse generator capable of overlapping-event handling is used.

## Test Sequence

### Phase A: electrical safety and baseline

Before injecting dataset activity:

1. Measure the device at a low read voltage $V_\mathrm{read}$, well below threshold.
2. Record the off-state resistance and leakage current.
3. Apply no stimulus for a fixed recovery interval.
4. Verify that the conductance has returned to its baseline.
5. Repeat this baseline measurement before every trial or sample.

For a diffusive Ag-based device, published examples show volatile threshold switching and self-relaxation: the device enters a low-resistance state when a conducting path forms, then returns toward its high-resistance state after stimulus removal. For example, one particular Pt/SiO$_x$:Ag/Ag/Pt device switched near 0.25–0.3 V under quasi-DC sweeps and used a 10 µA compliance current, while its pulse threshold depended strongly on pulse width [@yoon TODO]. But the numerical voltages in that work are not directly transferable to a ZnO device. 

### Phase B: single-pulse map

First characterise isolated events, with enough recovery time that pulses do not interact.

Sweep:
| Parameter | Suggested initial values |
| :-- | --: |
| Pulse width | 1 µs, 10 µs, 100 µs, 1 ms |
| Amplitude | 8–12 logarithmically or linearly spaced values |
| Recovery interval | At least $5\tau_\mathrm{relax}$, initially |
| Repetitions | 20–100 per condition |
| Compliance | Conservative hardware limit |

For each pulse, record:

- Applied voltage.
- Device current.
- Peak current.
- Time to current threshold.
- Pulse energy:

$$
E_k=\\int V(t)I(t),dt.
$$
- Whether a filamentary ON event occurred.
- Time taken to return below the chosen OFF threshold.

Define an experimentally measured firing event, for example, as

$$
I(t)>I_\mathrm{fire}
$$

for at least a specified minimum duration, rather than relying only on a voltage transition. The threshold should be several times larger than the baseline noise; Otieno et al. used a criterion based on oscillations exceeding the OFF-period noise by 10% in a diffusive-memristor study, although  criterion shall be based on instrument noise and device dynamics [@otieno TODO].

The main output is a single-pulse firing probability:

$$
P_\mathrm{fire}(V,t_\mathrm{pw})
=
\frac{\text{number of firing trials}}
{\text{number of trials}}.
$$

This is more informative than a single “threshold voltage”, because diffusive filament formation is stochastic.

### Phase C: frequency/amplitude accumulation map

Then periodic pulse trains are applied:

$$
V(t)=\sum_{n=0}^{N-1}V_\mathrm{pulse}
\left[
u(t-nT)-u(t-nT-t_\mathrm{pw})
\right],
$$

with frequency $f=1/T$.

With the following starting grid:

| Parameter | Initial sweep |
| :-- | --: |
| Pulse amplitude | 0.5, 0.6, 0.7, …, 1.2 times the isolated-pulse threshold |
| Pulse width | 1–3 selected widths from Phase B |
| Frequency | 10 Hz to 100 kHz, logarithmically spaced |
| Number of pulses | 10–1000 |
| Trials | 10–30 per condition |

The device responds to the competition between filament accumulation and relaxation. A simple model is

$$
x_{n+1}
=
x_n e^{-\Delta t_n/\tau(V)}
+
A(V_k,t_\mathrm{pw}),
$$

where $x$ is an internal filament-proximity or ionic-concentration state. Fire when

$$
x_n\ge x_\mathrm{th}.
$$

This separates:

- **Amplitude effect:** how much state is added by each event.
- **Frequency effect:** how much state decays before the next event.
- **Pulse-width effect:** how long ions experience the electric field and current.
- **History effect:** whether preceding subthreshold pulses leave a partially formed filament.

The literature gives direct experimental support for this interpretation. In one diffusive memristor study by Zhang et al, 100 µs pulse trains required fewer pulses to switch at higher amplitudes; subthreshold pulses could accumulate toward conducting paths, while longer intervals allowed relaxation [@zhang_experimental_2019]. A separate volatile-memristor neuron implementation by Yoon et al. demonstrated that high-frequency input could fire the neuron whereas lower-frequency input did not, because the leaky state decayed between pulses [@yoon TODO].

## 3. Injecting actual N-MNIST spikes

Once the device envelope is established, the real event stream is used.

### Event preprocessing

For each N-MNIST sample:

1. Decode each event as $(x,y,t,p)$.
2. Select the target neuron’s synaptic weights.
3. Remove events whose mapped amplitude is below the chosen hardware floor, or retain them explicitly as subthreshold stimuli.
4. Convert timestamps from microseconds to the probe-station timebase.
5. Preserve event order.
6. Apply a fixed sample preamble and postamble.
7. Ensure that the device is reset or fully relaxed before the next sample.

The event stream is not binned, as it destroys the temporal information that determines whether pulses arrive before the volatile state has decayed. N-MNIST timestamps are provided at microsecond resolution [@see_st-mnist_2020].

### Weight-to-amplitude mapping

An explicit mapping from neural weight to voltage is required. Three options:

#### Linear mapping

$$
V_k=V_\mathrm{min}
+
\frac{w_k-w_\mathrm{min}}
{w_\mathrm{max}-w_\mathrm{min}}
\left(V_\mathrm{max}-V_\mathrm{min}\right).
$$

This is easy to interpret but can waste amplitude resolution if the weight distribution is heavy-tailed.

#### Quantile mapping

Weight percentiles to pulse amplitudes are mapped. For example:

- 0–10th percentile: $V_1$.
- 10–25th percentile: $V_2$.
- …
- 90–100th percentile: $V_8$.

This gives better experimental coverage of the weight distribution.

#### Energy-preserving mapping

If weight magnitude should represent synaptic charge or energy, use

$$
V_k \propto \sqrt{|w_k|}
$$

for approximately constant pulse width and resistive loading, since pulse energy scales approximately as $V^2t/R$. This is less directly equivalent to a conventional weighted voltage input but can be useful when the physical device responds primarily to energy.

Begin with with quantile mapping, then repeat the experiment with linear mapping once the device’s dynamic range is established.

## Measurements and event labels

For every applied pulse and every detected current response, output a row with:

```text
sample_id
target_neuron
event_index
timestamp_us
x
y
polarity
weight
pulse_voltage
pulse_width_s
inter_event_interval_s
current_peak
current_baseline
time_to_fire_s
fired
filament_state_after_pulse
reset_time_s
energy_j
temperature_c
compliance_active
```

Use three event labels:

### No response

The current remains below $I_\mathrm{fire}$, and there is no measurable post-pulse conductance change.

### Partial accumulation

The device does not fire, but one or more of the following changes:

- Off-state leakage rises.
- The next pulse produces a larger current.
- The threshold shifts lower.
- Recovery takes longer.

This state is important: it is the physical equivalent of a leaky membrane potential.

### Firing event

The current rises abruptly above $I_\mathrm{fire}$. Measure:

$$
t_\mathrm{fire}=t(I>I_\mathrm{fire})-t_\mathrm{pulse}
$$

and

$$
Q_\mathrm{fire}=\int_{\mathrm{fire}} I(t)\,dt.
$$

Filament formation cannot be identified solely from a large current spike. It is confirmed using a low-voltage non-disturbing read immediately after the event.

## Reset characterisation

For a diffusive device, reset should be passive: once the stimulus is removed, the filament dissolves through diffusion. The decay can often be fitted with one or more exponentials:

$$
R(t)=R_\infty-\Delta R
\exp\left[-\left(\frac{t}{\tau}\right)^\beta\right],
$$

where $\beta=1$ is a simple exponential and $\beta\ne1$ permits a broader distribution of relaxation times.

Measure reset in three separate ways:

1. **Passive reset:** remove the stimulus and monitor current at a non-disturbing read bias.
2. **Inter-pulse reset:** apply a second subthreshold pulse at controlled delays after firing.
3. **Active reset:** apply a reverse or reset pulse only if the device stack supports it (TBC for Ag/ZnO).

For passive reset, record

$$
\tau_\mathrm{reset}
$$

at several temperatures and after several firing energies. For active reset, sweep reset amplitude and width conservatively. An excessively large “forming” pulse can change the device permanently rather than produce a reversible volatile filament. In the cited oxide/Ag example, moderate high-voltage stress produced partially electroformed states that could relax, whereas sufficiently strong stress produced an overly strong filament and permanent damage [@yoon TODO].

A particularly useful test is the paired-pulse response:

$$
I_2(\Delta t)
$$

for a fixed second pulse and variable delay $\Delta t$. This directly measures the device’s residual excitability. In [@yoon TODO], a normally subthreshold pulse produced a significant response when delivered before full relaxation but not after a sufficiently long delay.

## Probe-station waveform architecture

A practical setup is:

```text
Arbitrary waveform generator
        |
        | voltage pulse
        v
Series protection resistor / current limiter
        |
        v
Memristor device
        |
       GND
```

Current is measured using Keysight B1500A WGFMU / B1530A, EasyExpert PC software.

Use a separate low-voltage read path if possible. Do not rely on the waveform-generator output voltage as the device voltage during the ON state: once the device switches, the source impedance, series resistor, cables, and probe parasitics can substantially alter the actual device voltage.

The following data are acquired:

$$
V_\mathrm{device}(t),\qquad I_\mathrm{device}(t)
$$

at a sample rate much faster than the expected filament-formation time. Include the actual voltage at the device terminals, not merely the programmed waveform.

Also monitor:

- compliance activation,
- probe contact resistance,
- device temperature,
- voltage overshoot,
- ringing,
- and the baseline current before each pulse.


## Experiment matrix

| Stage | Input | Main result |
| :-- | :-- | :-- |
| 1 | Low-voltage reads | Baseline resistance and noise |
| 2 | Isolated pulses | $P_\mathrm{fire}(V,t_\mathrm{pw})$ |
| 3 | Periodic trains | Frequency–amplitude firing boundary |
| 4 | Paired pulses | Residual excitability versus delay |
| 5 | Pulse trains near boundary | Accumulation and stochasticity |
| 6 | Real N-MNIST events with constant amplitude | Dataset timing effect |
| 7 | Real events with weight-coded amplitude | SNN-like operation |
| 8 | Repeated identical samples | Cycle-to-cycle variability |
| 9 | Active reset sweep | Reversible versus damaging reset |

Each condition is repeated enough times to estimate distributions, not just means. Report median, interquartile range, firing probability, and failure modes.
