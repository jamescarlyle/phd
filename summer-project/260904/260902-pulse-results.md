# Ag50/ZnO Memristor: DC and Pulse Characterisation Summary

## Objective

Characterise an Ag/ZnO memristor initially measured by bidirectional DC sweep, reset it to a high-resistance state (HRS), and explore operation in a volatile, threshold-switching regime using a Keysight B1500A with a B1530A waveform generator/fast measurement unit (WGFMU).

The desired signature is a weak Ag-based conductive filament that forms during a positive stimulus and decays spontaneously after the stimulus is removed, rather than remaining as a nonvolatile low-resistance state (LRS).

---

## Initial DC measurement

### Measurement conditions

- Device: Ag50/ZnO memristor
- DC sweep: 0 V to 10 V and back to 0 V
- Step size: 200 mV
- Current compliance: 100 µA
- Two consecutive runs were shown.

### Observed behaviour

**First run**

- Current remained extremely small up to approximately 5.7–6 V.
- Near 6 V, current rose abruptly to the 100 µA compliance limit.
- On the descending branch, current stayed high until approximately 3.5–3.8 V, then relaxed down a distinct hysteretic branch.

**Second run**

- The subsequent trace followed the descending/relaxed branch from the first run rather than remaining in the original virgin high-resistance branch until 6 V.

### Interpretation

The initial steep turn-on at approximately 6 V is consistent with a first electroforming or SET-like event in an Ag/ZnO electrochemical-metallisation (ECM) cell:

1. Ag oxidises at the active electrode to mobile Ag ions.
2. Ag ions migrate through ZnO under electric field.
3. Reduction and aggregation create an Ag-rich conductive path.
4. Current rises sharply when the path nearly bridges or bridges the electrodes.
5. The 100 µA compliance constrains further growth, but may still create a comparatively robust filament.

The hysteresis and altered second sweep imply that the first run changed the device. Residual Ag clusters, a partially dissolved filament, locally modified defects, or interfacial changes probably lowered the barrier for later conduction. The device did not fully recover to its virgin state on the same-polarity downward sweep.

Important caveat: a positive 0 → 10 → 0 V sweep demonstrates relaxation under decreasing same-polarity voltage, but does not by itself prove a conventional bipolar RESET. A reverse-polarity bias relative to Ag is normally needed to test electrochemical dissolution/reset directly.

---

## Reset and volatile-mode strategy

### Reset principle

Avoid repeatedly sweeping positively to high voltage, since this can reinforce Ag filament formation. Instead, if the device is persistently conductive, use cautious reverse-polarity RESET sweeps or pulses, with a conservative current limit, and increase reverse amplitude incrementally only as needed.

A successful reset is indicated by return to a very low low-bias read current.

### Volatile threshold-switching principle

Volatility needs a filament that is present only while the stimulus is sufficiently strong:

- Above threshold voltage, a narrow conductive path forms or nearly bridges the gap.
- When the field drops below a holding condition or returns to zero, the path destabilises, contracts, diffuses, or dissolves.
- The low-bias conductance returns toward the original HRS without a deliberate reverse RESET pulse.

The key experimental controls are:

- Low effective programming energy.
- Short pulses rather than long DC stress.
- Minimal number of pulses at each condition.
- No unnecessary continuation after switching is observed.
- Consistent low-bias post-pulse reads.

A current range on the WGFMU is a measurement range, not necessarily the same as an SMU current-compliance clamp. This is important when approaching a potential forming threshold.

---

## Low-bias read measurements

### Original read result

An early low-bias read was reported as:

- Read voltage: 100 mV
- Current: 4.4 pA

This corresponds nominally to:

\[
R = \frac{0.1\ \mathrm{V}}{4.4\times10^{-12}\ \mathrm{A}} \approx 23\ \mathrm{G\Omega}
\]

This was interpreted as a very high-resistance OFF state.

### Clarification of later read condition

A later one-point I–V setting was initially described as a 100 mV read, but the configured sweep was actually:

- Start: 1 V
- Stop: 1 V
- Compliance: 1 µA
- No hold or delay.

Thus, the resulting 610 fA value was measured at 1 V, not 100 mV. It cannot be directly compared to the earlier 100 mV measurement.

### 100 mV repeated reads

With corrected fixed-bias settings at 100 mV, 10 ms hold, and 10 ms delay, repeated measurements gave:

- 260 fA
- −80 fA
- 50 fA

After changing the integration configuration to HR ADC, Auto mode, factor 20, and autozero on, repeated reads gave:

- 891 fA
- 194 fA
- −109 fA

With probes lifted, repeated readings were:

- 199 fA
- −98 fA
- 48 fA

### Finding: the OFF current is below the practical system floor

The contacted and lifted-probe measurements have similar fA-scale scatter and change sign. Therefore, at 100 mV the true device leakage cannot be reliably separated from instrument, cable, probe, fixture, environmental, and offset current.

Use this practical definition going forward:

\[
|I_{\mathrm{read}}(100\ \mathrm{mV})| < 1\ \mathrm{pA}
\quad \Rightarrow \quad \text{OFF / HRS within the measurement floor}
\]

Do not attempt to distinguish device states from differences such as 50 fA, 260 fA, or −100 fA. These are not reliable evidence of state change in the current setup.

The important signal will be a post-pulse read current that is clearly and reproducibly above this approximately ±1 pA floor, followed by spontaneous return toward it.

---

## Keysight B1530A WGFMU setup

### Instrument role

The B1530A WGFMU was identified as the appropriate module for pulse and transient I–V measurements. It can generate programmed voltage waveforms and synchronously measure fast current/voltage responses.

The DC SMU remains preferable for slow pA/fA readout. The WGFMU is useful once the signal is in the nA/µA or larger transient regime.

### Software route

The user was at the EasyEXPERT Workspace main screen and selected the **WGFMU Pattern Editor** application test.

The execution mode options were:

- **Pattern Validation**: checks waveform/timing/range configuration without stimulating the DUT.
- **Run Vector**: outputs the waveform and acquires data.

Recommended use:

1. Build/edit a waveform.
2. Use Pattern Validation until no errors are reported.
3. Change to Run Vector.
4. Use Single for exactly one application of the waveform.
5. Avoid loops/repeats while mapping delicate switching behaviour.

### Two-channel physical configuration

A two-channel Fast I/V configuration was used:

| WGFMU channel | Connection | Operation mode | Main purpose |
|---|---|---|---|
| Channel 1 | Ag electrode / high side | Fast I/V Vmeas | Apply positive voltage waveform and monitor actual voltage at the Ag terminal |
| Channel 2 | Counter electrode / low side | Fast I/V Imeas | Hold return node at 0 V and measure device return current |

Channel 2 should be driven with a 0 V waveform covering the full duration of the Channel 1 waveform. This gives a defined return path instead of a floating lower electrode.

Suggested initial parameter settings were:

| Parameter | Channel 1 | Channel 2 |
|---|---|---|
| Channel | Physical Channel 1 | Physical Channel 2 |
| Operation mode | Fast I/V Vmeas | Fast I/V Imeas |
| Voltage force range | 0 to +10 V | 0 to +10 V initially |
| Initial measurement range | 5 V voltage range | 1 µA current range |

The Channel 2 current sign is determined by the low-side measurement convention. Negative current during a positive Ag pulse is expected in this wiring convention and should not be treated as physically anomalous.

---

## First pulse waveform and measurement events

### Initial 1 V verification waveform

The Pattern Editor waveform tables were interpreted as timestamp/voltage rows. Adjacent rows define linear segments; therefore, rise and fall times are determined directly by the timestamp spacing between voltage values.

Initial Channel 1 waveform:

| Time | Ch1 voltage |
|---:|---:|
| 0 | 0 V |
| 1 µs | 0 V |
| 2 µs | +1 V |
| 12 µs | +1 V |
| 13 µs | 0 V |
| 1.013 ms | 0 V |

This gives:

- 1 µs pre-pulse baseline
- 1 µs linear rise
- 10 µs +1 V plateau
- 1 µs linear fall
- 1 ms post-pulse baseline.

Channel 2 used the same timestamps, with 0 V in every voltage row.

### Measurement event

The separate `MeasurementEvent` table defines when samples are acquired, rather than defining the stimulus waveform. Its fields include start time, number of points, sample interval, averaging/integration duration, plus range-change fields for Ch1 and Ch2.

A higher-resolution event used:

| Start time | Points | Interval | Averaging time | Ch1 range | Ch2 range |
|---:|---:|---:|---:|---:|---:|
| 0 | 113 | 1 µs | 100 ns | 0 | 0 |

For the range fields, 0 was used to mean no change from the initial configured range during the measurement. Dynamic range changes were deliberately avoided during the initial waveform work.

Pattern Validation returned no errors.

---

## Capacitive baseline finding

### First observed pulse response

With the initial pulse, the blue voltage trace first showed only a single sampled peak because the event interval was too coarse. After changing to a 1 µs interval, the blue trace showed a defined voltage plateau.

At approximately +1 V with 1 µs edges, Channel 2 current showed:

- Negative spike on the rising voltage edge: about −57 nA.
- Flat/near-baseline current on the pulse plateau.
- Positive spike at the falling voltage edge: about +55 nA.

When the programmed Ch1 rise and fall were extended from 1 µs to 2 µs, using timestamp changes such as:

| Time | Ch1 voltage |
|---:|---:|
| 0 | 0 V |
| 1 µs | 0 V |
| 3 µs | +1 V |
| 13 µs | +1 V |
| 15 µs | 0 V |
| 1.015 ms | 0 V |

current-spike magnitudes reduced to approximately −40 nA and +40 nA.

### Interpretation

This behaviour is consistent with capacitive displacement current:

\[
I_C = C\frac{dV}{dt}
\]

A slower voltage ramp reduces \(dV/dt\), so the reduction in edge-current magnitude supports the interpretation that these spikes arise mainly from device, probe, cable, and fixture capacitance rather than filament conduction.

The exact current did not halve when the edge time doubled, which is expected because observed peaks also depend on sample timing, bandwidth, settling, parasitic inductance/capacitance, and waveform non-idealities.

This was a useful result because it verified:

- Channel wiring.
- Voltage waveform delivery.
- Correct interpretation of the fast current trace.
- An empirical background against which filament formation can be detected.

---

## How to recognise a filament event

### Capacitive/polarisation response

Likely characteristics:

- Largest current occurs immediately after a rising or falling voltage edge.
- Current decays smoothly during a constant-voltage plateau.
- Opposite-sign transient appears at turn-off.
- No sustained elevated current well into the voltage plateau.
- No robust post-pulse conductance increase beyond the low-bias system floor.

### Candidate conductive-filament response

More convincing features:

- A current increase occurs **during the constant-voltage plateau**, not only at its edge.
- The current may rise abruptly after a delay, indicating field-assisted Ag migration and bridge completion.
- After the increase, a sustained high-current interval appears during the flat top.
- The post-pulse low-bias read is clearly above the normal OFF floor.
- That post-pulse current then returns toward the OFF floor without a reverse-reset stimulus if the behaviour is volatile.

Focus on waveform shape and current magnitude rather than sign. With Channel 2 measuring low-side current, positive Ag bias can appear as negative plotted current.

---

## 3 V, 100 µs pulse result

A waveform condition was initially recalled as 5 V but corrected to:

- Pulse plateau: +3 V
- Plateau length: 100 µs
- Rise/fall: approximately 2 µs.

Observed Channel 2 response:

- Negative spike at pulse onset.
- Current approximately −350 nA early in the plateau.
- Smooth drift toward approximately −110 nA by the end of the plateau.
- Positive turn-off transient around +530 nA.
- Post-pulse WGFMU trace fluctuating approximately from +60 nA to −60 nA.

Interpretation:

- At 3 V, this looked primarily like sub-threshold field-induced leakage/polarisation relaxation plus capacitance.
- The largest negative current occurred early and decayed through the plateau, which is not the most persuasive signature of a bridging filament.
- The post-pulse WGFMU baseline is not suitable for judging pA-level retention because the WGFMU fast current floor/offset is in the nA-scale context here.
- The separate DC read should be used to assess residual low-bias conductance.

---

## More promising pulse result

Under a later pulse condition, not fully specified in the final exchange, the plateau current evolved from approximately:

\[
-1\ \mu\mathrm{A}\quad \text{early in the plateau}
\]

to approximately:

\[
-8\ \mu\mathrm{A}\quad \text{late in the plateau}
\]

The immediate post-plateau read at 0.5 V was:

\[
I_{\mathrm{read}}(0.5\ \mathrm{V}) \approx -124\ \mathrm{nA}
\]

### Interpretation

This is much more promising than the 3 V smooth-decay trace:

- Current becomes larger later in the constant-voltage plateau rather than simply decaying from its edge value.
- That temporal growth is consistent with a slow field-driven process, such as Ag-ion migration and progressive filament growth/narrowing of a remaining insulating gap.
- The −124 nA measurement at 0.5 V is vastly above the approximately ±1 pA 100 mV floor, showing a genuine post-pulse conductance increase.

However, the result is **not yet proof of volatility**. It establishes that the pulse caused a conductive state, but the next question is whether that state self-decays or persists.

A 0.5 V read may itself influence a marginal filament, so the preferred monitoring bias for the next experiment is 0.1 V, subject to the limitation that the OFF state at 0.1 V is below the measurement floor.

---

## Recommended next experiment

### Aim

Determine whether the more conductive post-pulse state decays spontaneously after a single pulse.

### Keep pulse parameters fixed

Use the exact pulse condition that gave the late-plateau transition from approximately −1 µA to −8 µA. Do not initially increase pulse amplitude, plateau length, or pulse count.

The first goal is to characterise relaxation at one condition, not to drive the device harder.

### Measurement sequence

1. Confirm baseline with the usual +100 mV DC read.
2. Apply **one** WGFMU pulse using the promising condition.
3. Record the fast waveform, especially the late flat-top current.
4. Turn off/return WGFMU outputs to 0 V.
5. Take a brief +100 mV DC read as soon as practicable.
6. Repeat the same fixed read after nominal delays such as:
   - 10 ms
   - 100 ms
   - 1 s
   - 10 s
   - 100 s
7. Optionally wait 1–5 minutes without intermediate reads, then take one last read.
8. Record real elapsed time from pulse end as well as nominal delay.

### Decision criteria

| Observation | Interpretation |
|---|---|
| Pulse plateau current becomes sustained at µA scale; low-bias current rises then returns to within ±1 pA without reverse bias | Strong evidence for volatile Ag-filament/threshold switching |
| Low-bias current stays elevated at nA scale for minutes | Persistent or partly persistent filament; nonvolatile/short-term-to-long-term transition |
| Only edge transients and a smoothly decaying plateau response appear; low-bias read remains within ±1 pA | Sub-threshold capacitive/polarisation response |
| Plateau current grows strongly or jumps abruptly and stays high | Approach to forming/SET; stop increasing pulse energy and assess post-pulse state |

---

## Practical cautions

- Do not confuse WGFMU measurement current range with a conventional SMU compliance clamp.
- Use one pulse per amplitude/condition while mapping the threshold region.
- Avoid long repeated high-voltage DC sweeps if the aim is volatile switching; they encourage a robust filament.
- Keep a clear convention for polarity: positive voltage should be explicitly defined relative to the Ag electrode.
- Use the Channel 2 current sign consistently; negative current for positive Ag pulsing is expected in the adopted low-side measurement configuration.
- Treat 100 mV fA-scale measurements as `OFF below system floor`, not as exact resistance values.
- If possible, save each raw waveform along with pulse amplitude, rise time, plateau width, fall time, current-range settings, and post-pulse read delay.

---

## Current overall conclusion

The work has progressed from a high-current DC forming-like event near 6 V to a validated pulsed measurement setup with a known capacitive baseline. At low-amplitude pulses, the response is dominated by displacement current and field-induced relaxation. At a later pulse condition, the plateau current increased from approximately −1 µA to −8 µA and produced a post-pulse −124 nA read at 0.5 V. This is the first observation consistent with a developing Ag conductive path.

The next critical experiment is a fixed-condition, single-pulse relaxation test using repeated low-bias reads versus time. That will distinguish a genuinely volatile, self-dissolving filament from a persistent nonvolatile conductive state.
