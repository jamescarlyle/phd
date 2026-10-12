# Filament Decay Time Constant

The filament decay time constant cannot be reliably extracted from this measurement because the read current at 0.1V drops directly into the instrument's noise floor and settling artifacts.

## Measurement Breakdown

- Voltage profile (blue trace, left axis, 200 mV/div):
Baseline read voltage sits at V_read = 0.1V (99 mV), pulses to 2.0V for ~82 uS (rising edge near 18 uS, falling edge at 100 uS), then steps back to 0.1V.
- Switching variability (orange traces, right axis, 200 nA/div):
Across the 5 runs, the threshold switching delay varies widely from ~25 uS to 92 uS.
- On-state current and conductance:
Under the 2V pulse, the on-state current reaches -1.0 uA to -2.6 uA. This corresponds to an effective conductance G_on = 0.5 uS to 1.3 uS (equivalent to R_on = 770 kOhm to 2 MOhm).
- Pulse turn-off behavior:
At t = 100 uS, the voltage drops from 2.0V to 0.1V, and the measured current returns to near 0 nA within 2 to 4 uS.


## Why Filament Decay Is Obscured

- Ohmic current collapse below the noise floor:
Even if the Ag conductive filament remained fully intact immediately after the pulse, Ohmic scaling dictates:
I_read = G_on * V_read = 0.5 uS * 0.1V = 50 nA (up to 130 nA for the 2.6 uA run).
On a 200 nA/div scale designed to capture microamp currents, 50 to 130 nA is less than half a major division and sits squarely within the baseline digitisation noise.
- Parasitic RC and slew artifacts:
The rapid transition back to baseline between 100 uS and 104 uS tracks the voltage generator slew rate and displacement current (I = C * dV/dt) from cable and fixture capacitance. This settling artifact masks any genuine physical Ag dissolution occurring on single-microsecond timescales.

```
Voltage Profile:
2.0V |          +-------------------------+
     |          |                         |
0.1V |----------+                         +------------------
     0         18uS                     100uS              150uS

Expected vs Visible Current:
     0nA  --------------------------------\   /--------------
          |                                \ /  <-- I_read = 50-130 nA (buried in noise)
-1uA |    |              +----------------+
          |              | (switches at 25-92 uS)
-2uA |    +--------------+
```


## Recommended Test Protocols

- Two-pulse paired-pulse facilitation / depression (PPF/PPD):
Apply a 2V, 100 uS pulse to form the filament, pause for a variable delay delta_t (e.g. 2 uS, 5 uS, 10 uS, 20 uS, 50 uS, 100 uS, 1 ms), and apply a second 2V pulse. Measure the switching delay (incubation time) of the second pulse as a function of delta_t. Because residual Ag clusters lower the barrier to re-formation, the switching delay increases with delta_t, allowing fitting of the characteristic decay time constant tau.
- Higher read voltage:
Increase V_read from 0.1V to 0.3V - 0.5V (ensuring it stays below the device threshold voltage V_th ~ 1.5V to prevent re-triggering). At 0.4V, the intact LRS current will be 200 to 520 nA, placing it cleanly above the 200 nA/div noise threshold.
- Dynamic autoranging / external TIA:
If supported by the Keysight B1530A WGFMU setup, configure dual-range measurement or feed the output into a low-noise transimpedance amplifier so that the nanoamp decay tail can be resolved without clipping the 2.6 uA programming peak.

Cycle-to-cycle variability of this magnitude is entirely normal and expected for Ag/ZnO electrochemical metallisation memory (ECM) and diffusive threshold switching devices .

## Physical Origin of Delay Stochasticity

The primary source of variability is the stochastic nucleation and drift of silver species. The delay time (incubation period) before an abrupt conductance jump comprises three sequential microscopic phases: [d-nb](https://d-nb.info/1197524274/34)

- **Electrochemical oxidation and detachment:** Silver atoms at the active electrode oxidise into Ag+ cations ($Ag \rightarrow Ag^+ + e^-$), which must overcome interfacial energy barriers to detach into the dielectric matrix. [d-nb](https://d-nb.info/1197524274/34)
- **Hopping transport and drift:** Ag+ cations migrate across the switching layer under the electric field . Polycrystalline ZnO features grain boundaries and native point defects (such as oxygen vacancies and zinc interstitials) that create spatially non-uniform, tortuous low-resistance percolation pathways .
- **Cluster nucleation and percolation:** At the counter electrode, migrating cations reduce ($Ag^+ + e^- \rightarrow Ag$) and aggregate into metallic nanoclusters until a continuous bridge spans the gap .

Because nucleation at the nanoscale is an activated Poisson-like process governed by thermal fluctuations, the required time to close the gap varies from pulse to pulse, causing switching delays spanning from 25 uS to over 90 uS under identical electrical bias. [d-nb](https://d-nb.info/1197524274/34)

```
Cycle A (Fast Percolation ~25 uS):
[ Ag Electrode ]
    \   /        Pre-existing cluster remnants or aligned 
     \ /         grain boundaries form a fast percolation bridge
  [ Bridge ]     --> Early turn-on
[ Pt/Counter   ]

Cycle B (Delayed Percolation ~92 uS):
[ Ag Electrode ]
    *     *      Fragmented nanoclusters require prolonged 
      *          field-driven migration and re-nucleation
    *     *      --> Late turn-on
[ Pt/Counter   ]
```

## Morphological and State Variations

Cycle-to-cycle dispersion also affects the low-resistance state (LRS) current, visible in the spread between -1.0 uA and -2.6 uA:

- **Filament constriction size:** The final cross-sectional diameter of the Ag bridge depends heavily on the remaining duration of the electrical pulse after percolation occurs . A device that fires early (e.g. at 25 uS) experiences prolonged electric field and Joule heating, accumulating more silver mass and yielding a lower resistance state . A device switching late (near 92 uS) forms only a tenuous, weakly conducting filament before the pulse terminates .
- **Incomplete filament dissolution:** Following pulse turn-off, Rayleigh instability and interfacial surface energy dissolve the metallic filament into isolated nanoclusters . The random spatial distribution and size of these residual clusters define the initial state for the subsequent cycle, directly shifting the next switching delay .

## Comparison of Variability Mitigation Strategies

Technological solutions frequently applied to mitigate cycle-to-cycle variations involve restricting cation migration paths or modulating the active field:

| Strategy | Mechanism | Effect on Variability | Trade-off |
| :--- | :--- | :--- | :--- |
| **Bilayer dielectric insertion** (e.g. ZnO/Al2O3 or ZnO/HfO2)  [ieeexplore.ieee](https://ieeexplore.ieee.org/abstract/document/11497312) | High-k sub-layer concentrates electric field and confines percolation paths  [ieeexplore.ieee](https://ieeexplore.ieee.org/abstract/document/11497312). | Drastically reduces switching delay spread and off-current leakage  [ieeexplore.ieee](https://ieeexplore.ieee.org/abstract/document/11497312). | Increases required set voltage  [ieeexplore.ieee](https://ieeexplore.ieee.org/abstract/document/11497312). |
| **Active Ag-layer thickness tuning**  [advanced.onlinelibrary.wiley](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aelm.202200549) | Optimises cation reservoir availability to maintain controlled dissolution  [advanced.onlinelibrary.wiley](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aelm.202200549). | Improves cycle endurance and stabilises LRS/HRS separation  [advanced.onlinelibrary.wiley](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aelm.202200549). | Excessive thickness promotes non-volatile retention  [advanced.onlinelibrary.wiley](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aelm.202200549). |
| **Series compliance / resistor integration**  | Limits self-accelerating current and runaway Joule heating . | Standardises on-state conductance and stabilizes relaxation time . | Lowers overall read margin . |
| **Increased programming amplitude**  | Exponentially accelerates cation hopping velocity under stronger field . | Compresses switching delay into sub-microsecond regimes  [eprints.soton.ac](https://eprints.soton.ac.uk/475252/1/2022_Electrode_Engineering_in_Memristors_Development_20220723.pdf). | Accelerates device fatigue and dielectric breakdown  [eprints.soton.ac](https://eprints.soton.ac.uk/475252/1/2022_Electrode_Engineering_in_Memristors_Development_20220723.pdf). |
