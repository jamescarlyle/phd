# Diffusive Memristor Characterisation Plan

## Device Specification

Marked Ag50 ZnO TiN60. Likely to be:
1. SiO₂/Si substrate.
2. Ti (5 nm) / TiN (60 nm) as bottom electrode. Deposition: DC or RF sputtering from a Ti target in Ar + N₂ (or reactive Ti + N₂/O₂). Example conditions (similar systems) Power: ~100–300 W (RF/DC). Pressure: ~0.02–0.05 mbar. Gas: Ar (+ N₂ for nitridation) at ~30 sccm scale. Optional adhesion layer: 5 nm Ti by sputter or e-beam. Patterning: photolithography + reactive ion beam etching (RIBE) or lift-off.
3. ZnO (10–30 nm) as switching layer. Deposition: pulsed DC or RF magnetron sputtering from a Zn target in Ar + O₂, or from a ZnO ceramic target. Example (Ag/ZnO/TiN device): Thickness: 10 nm. Power: 0.1 kW, pulsed DC, 50 kHz. Pressure: ~1 mTorr. Gases: Ar 6 sccm + O₂ 14 sccm. Oxygen partial pressure and power control the vacancy concentration, which strongly affects whether the device is volatile (diffusive) or non-volatile. Patterning: Lift-off to avoid etch damage to ZnO.
4. Ag (50 nm) / Pt (10–20 nm) as top electrode. Deposition: thermal or e-beam evaporation, or off-axis sputtering. Example: Thickness: 100 nm Ag in one Ag/ZnO/TiN study; 20 nm Ag in diffusive HfO₂ devices. 50 nm Ag is within this range and would give a robust filament source while still allowing diffusion-dominated dynamics if the ZnO is thin and defective enough. Patterning: Lift-off through a shadow mask or standard lithography; typical lateral sizes 2.5–100 µm.
5. Capping: 10–20 nm Pt or Au by evaporation or sputter to limit oxidation.

## Volatile Behaviour Confirmation
Ag/ZnO is a plausible and well-established platform for diffusive memristive dynamics, especially when operated at low compliance current with a thin, unstable Ag filament. It should be possible to push the same device into conventional nonvolatile filamentary switching by increasing the available current or stimulation energy.

- Relaxation after a set pulse: apply a pulse, remove the bias, and measure conductance at low read voltage. A diffusive device should show a decay such as stretched-exponential/power-law relaxation.
- Pulse-interval dependence: repeat identical pulses with increasing inter-pulse intervals. Potentiation should weaken as the interval becomes longer because the residual filament has more time to dissolve.
- Compliance-current dependence: increasing compliance should lengthen the retention time and eventually produce nonvolatile switching.
- Threshold and hold voltage: determine whether the device has a clear set threshold, followed by a lower hold or quench voltage.
- Temperature dependence: ionic diffusion and filament relaxation should generally become faster at higher temperature.
- Distinguish volatility from charge trapping: volatile behaviour alone does not prove Ag-filament diffusion. ZnO oxygen vacancies, interface traps, Schottky barriers, and Joule heating can also produce transient or threshold-like responses. The strongest evidence is the combination of Ag-electrode dependence, compliance-controlled volatility, pulse accumulation, and direct filamentary signatures.

## Volatile Filament Characterisation

For studying volatile filament formation in an Ag/ZnO/TiN diffusive memristor, pulse parameters should:
- Drive Ag⁺ migration and filament nucleation/growth, but
- Stay below the energy/duration regime that produces a stable, non-volatile filament.

Literature on Ag-based diffusive and threshold-switching devices suggests the following set of parameters.

### Voltage Amplitudes
For Ag/ZnO and related Ag-based volatile devices:
- SET (filament formation) voltages:
  - DC sweeps: ~0.3–0.5 V threshold for volatile threshold switching in Ag/Ag:ZnO/Pt.
- RESET (filament dissolution) voltages:
  - Often −0.2 to −0.5 V in DC for Ag/ZnO systems.
  - For pulse-driven RESET, similar magnitudes but sometimes higher (e.g. −2 to −3 V) if the layer is thicker or more resistive.

For a thin ZnO (10–30 nm) diffusive device, a good starting range is:
- V_SET pulse: +0.4 to +1.5 V
- V_RESET pulse: −0.3 to −1.0 V (or more negative if needed)

### DC Sweep

Step 1: Measure the relaxation time once with a simple pulse test on one device.
- Apply a short set pulse just enough to turn it on (e.g. 1 V, 50 µs, with 10uA current compliance).
- Switch to a small read voltage (e.g. 0.1 V) and record conductance vs time; sample every 10us for ~10ms..
- Fit an approximate decay time constant tau (time to drop to ~37% of peak).

Step 2: Choose sweep time relative to tau.
- If sweep time ≪ tau (much faster than relaxation), the device doesn’t have time to relax during the sweep.
  - Should see a large hysteresis loop, but not due to volatility, but because voltage drops faster than the filament can diffusively relax.
- If sweep time ~ tau (comparable to relaxation):
  - The filament forms near the peak and starts to dissolve as the sweep drops.
  - A moderate hysteresis loop that shows tension between formation and rupture.
- If sweep time ≫ tau (much slower than relaxation):
  - The filament can form and then fully or mostly relax before the down-sweep is finished.
  - Hysteresis shrinks; the I–V looks more single‑valued.

However, because a long time is spent at high field, the device can gradually strengthen filaments over repeated sweeps, pushing it toward more non‑volatile behaviour.

Define a voltage sweep:
- Start: 0 V.
- End: +1 to +2 V (or until compliance is hit).
- Step size: 1–10 mV.
- Dwell time per step: 10–100 ms (slow enough to be quasi-static, fast enough to avoid excessive stress). 1–20 ms is usually “fast enough” to keep filaments thin and volatile.
- Set a compliance current (e.g. 10 µA – 1 mA) to prevent hard breakdown.

### Pulse widths and timing
Key findings from diffusive/volatile devices:
- Filament formation can occur on sub-µs to ms timescales, depending on voltage and material.
- Volatile/short-term behavior is strongly controlled by pulse width (t_p) and inter-pulse interval (t_i) relative to the device’s intrinsic relaxation time.

### SET pulses (filament formation)
- Amplitude: +0.4 to +1.5 V
- Width (t_p):
  - Start: 100 ns – 10µs
  - Extend up to 0.1–10ms if more cumulative ion migration at lower voltage needed.
  - Rise/fall time: as fast as setup allows (≤10–50 ns ideal) to separate field-driven migration from thermal effects.

For purely volatile filament nucleation (no hard “latch” to LRS):
- Use lower amplitudes (e.g. +0.4 to +0.8 V) with wider pulses (1–100 µs) or pulse trains, so the filament forms partially and then relaxes when the bias is removed.

### RESET pulses (filament dissolution)
For active rupture of the filament rather than spontaneous relaxation:
- Amplitude: −0.3 to −1.0 V (start modest, increase if needed)
- Width: 100 ns – 10 µs, similar to SET.
- In some systems, stronger negative pulses (−2 to −3V, 100ns – 1µs) are used to ensure reliable RESET.

## Single Pulse
Apply a single positive pulse to form the filament, then monitor current decay at 0 V or low read bias to observe spontaneous relaxation (no explicit RESET pulse).

To map out volatile filament formation and relaxation:

### Single-Pulse Response
Apply a single SET pulse:
- V_p = +0.4, +0.6, +0.8, +1.0, +1.2, +1.5 V
- t_p = 100 ns, 500 ns, 1 µs, 5 µs, 10 µs, 100 µs
- Read current at a small bias (e.g. +0.1 V) immediately after, then at intervals (1 ms, 10 ms, 100 ms, 1 s, 10 s) to capture relaxation.

### Pulse-train (Cumulative) Stimulation
Use repeated identical pulses to emulate paired-pulse facilitation / short-term plasticity:
- V_p = +0.4 to +0.8 V
- t_p = 1–10 µs
- Inter-pulse interval t_i = 10 ms – 1 s (match desired synaptic timescale).

Track conductance vs pulse number; volatile devices show transient potentiation that decays when stimulation stops.

### Pulse width–voltage mapping
Sweep (V_p, t_p) pairs to identify and map regimes of:
- No switching
- Volatile (transient) switching
- Non-volatile (stable) switching

Typical grid:
- V_p: 0.2–1.5 V in 0.1–0.2 V steps
- t_p: 100 ns, 500 ns, 1 µs, 5 µs, 10 µs, 50 µs, 100 µs, 1 ms

Classify each point by post-pulse retention time.

### Compliance current and read conditions
Compliance current (I_CC) during SET:
- For volatile filaments, keep I_CC low: 100 nA – 10 µA is common.
- Lower I_CC tends to produce thinner, more volatile filaments that relax faster.

Read voltage:
- Small enough not to perturb the filament: 50–200 mV is typical.

## Starting Parameter Set
For  Ag(50 nm)/ZnO(10–30 nm)/TiN(60 nm) stack:

SET pulse:
- V_p = +0.6 V
- t_p = 1 µs
- I_CC = 1 µA

RESET (if used):
- V_p = −0.5 V
- t_p = 1 µs

Read:
- V_read = +0.1 V, I limited to ≤100 nA

Systematically vary V_p from +0.4 to +1.2 V and t_p from 100 ns to 100 µs to locate the boundary between volatile and non-volatile filament formation.
