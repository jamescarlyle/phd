appendices.md

# Appendices

## Appendix A. Characterisation Detail.
### Synaptic Behavior of Drift Memristors.
| Test | Protocol | Extract for the model                                                                      |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| 1. Read linearity and state range | Read multiple programmed states using a low, non-disturbing voltage | Gmin_G_{\\min}Gmin_, Gmax_G_{\\max}Gmax_, read noise, read disturb, usable number of levels |
| 2. Incremental potentiation | Start from a defined low-conductance state; apply identical SET or potentiation pulses, reading after every pulse | GGG-versus-pulse-number curve, update granularity, saturation, stochasticity |
| 3. Incremental depression | Start from a defined high-conductance state; apply RESET or depression pulses, reading after every pulse | Depression curve, asymmetry relative to potentiation, saturation, stochasticity |
| 4. Pulse-amplitude/width dependence | Repeat selected updates for several amplitudes and widths | Update rule dG(G,V,tau)\\Delta G(G,V,\\tau)dG(G,V,tau), programming threshold, energy per update |
| 5. Retention/drift | Program representative low, middle, and high conductance states; read over logarithmically spaced delays with no programming bias | Drift law, retention distribution, state-dependent drift, effective weight lifetime |
| 6. Cycle-to-cycle and device-variation test | Repeat potentiation/depression cycles on several devices | Parameter distributions, update covariance, stuck states, device mismatch |
| 7. Endurance subset | Repeatedly alternate potentiation and depression while periodically checking the conductance window | Cycle-induced degradation, failure probability, changing update curves |

#### Core Static Electrical Behaviour.

- I/V curves over expected read and write voltage ranges, including nonlinear conductance.
- Hysteresis under voltage sweeps.
- High-resistance and low-resistance limits.
- Conductance dynamic range and usable analogue levels.
- SET and RESET polarity.
- Threshold voltage or threshold field.
- Read disturbance caused by sub-threshold read pulses.
- Current compliance effects.
- Series resistance and parasitic capacitance because the device is to be simulated in a circuit-level setting.

#### Pulse Behaviour.
Single-pulse response:

- Peak conductance.
- Conductance decay.
- Delay between excitation and conductance change.
- Pulse-amplitude and pulse-width dependence.

Pulse-pair response:

- Paired-pulse facilitation.
- Paired-pulse depression.
- Dependence on pulse order.
- Dependence on positive and negative delta-t.
- Effective STDP window.

Pulse trains:

- Temporal summation.
- Short-term facilitation and depression.
- Frequency-dependent potentiation.
- Frequency-dependent depression.
- Transition from volatile to persistent conductance change.
- Dependence on inter-pulse interval.
- Rate-to-conductance transfer function.

Drift:

- Conductance drift rate.
- Dependence of drift on the programmed state.
- Relaxation after SET and RESET separately.
- Temperature dependence.
- Retention distribution, not just mean retention.
- History dependence.
- Drift after repeated programming.
- Cycling-induced change in the drift law.

### Neuronal Behaviour of Diffusion Memristors.
| Test | Protocol | Extract for the model |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. DC or slow voltage sweep | Sweep voltage from 0 through the positive excitation range, then return to 0; repeat for several amplitudes and compliance limits | Threshold voltage, threshold current, hysteresis, ON-state conductance, switching polarity |
| 2. Single-pulse spike test | Apply isolated voltage pulses with a grid of amplitudes and widths; return to zero after each pulse | Spike/no-spike probability, spike latency, peak current, spike width, energy, threshold surface Pspike(V,tau)P_{\\mathrm{spike}}(V,\\tau)Pspike_(V,tau) |
| 3. Relaxation test | After a pulse that produces a conductive state, measure conductance/current at logarithmically spaced delays with zero bias   | Volatile decay law, relaxation time, residual conductance, dependence on pulse amplitude and width |
| 4. Pulse-pair interval test | Apply two identical pulses with inter-pulse interval dt\\Delta tdt, varying dt\\Delta tdt over the intended SNN range | Temporal summation, paired-pulse facilitation/depression, effective memory kernel |
| 5. Repeated-pulse train test | Apply trains at several frequencies and amplitudes | Frequency-dependent firing, accumulation, burst threshold, spike-rate response, transition between isolated and sustained spiking |
| 6. Repetition and device-variation test | Repeat tests 2-5 over many cycles and multiple devices | Cycle-to-cycle and device-to-device distributions of threshold, latency, spike width, relaxation, and failure modes |

#### Core Electrical Behaviour.

- The magnitude of conductance change per pulse.
- Dependence on pulse amplitude, width, and polarity.
- Nonlinear potentiation and depression.
- Saturation near conductance boundaries.
- State-dependent update sensitivity.
- Incremental versus abrupt switching.
- Update asymmetry.
- Dependence on pulse history and pulse spacing.
- Dependence on compliance current.
- Recovery or relaxation between programming pulses.

- Conductance relaxation after a pulse.
- Relaxation time constant or distribution.
- Whether relaxation is exponential, stretched exponential, power-law, or multi-timescale.
- Dependence of relaxation on the peak conductance reached.
- Dependence on pulse duration and amplitude.
- Residual conductance after partial relaxation.
- Facilitation from closely spaced pulses.
- Transition from volatile to effectively nonvolatile behaviour at high excitation.

#### Diffusive Characteristics:

- Threshold for spike initiation.
- Spike latency versus input amplitude.
- Spike latency versus pulse number.
- Temporal integration window.
- Firing-rate versus input-current relationship.
- Interspike interval distribution.
- Refractory period or refractory-like suppression.
- Adaptation after repeated spikes.
- Burst firing.
- Oscillation regimes.
- Noise-induced spiking.
- Spike amplitude, width, and energy.
- Reset dynamics.
- Dependence on temperature and bias history.

#### Variability

- Device-to-device variation.
- Cycle-to-cycle variation.
- Initial-state variation.
- Variation in conductance min and max.
- Variation in threshold voltage.
- Variation in switching delay.
- Variation in relaxation time.
- Variation in potentiation/depression slopes.
- Correlation between parameters within one device.
- Spatial correlation across an array.
- Temporal ageing and drift.
- Stuck-ON and stuck-OFF failure modes.
- Read noise and programming noise.

#### Stochastic behaviour.
Stochastic behaviour is not likely to be simple Gaussian noise on conductance. Instead, it may depend upon:

- Switching delay.
- Filament nucleation probability.
- Filament rupture probability.
- Dwell time in metastable states.
- Cycle-to-cycle variation.
- Random telegraph switching (can be a major source of temporal variability and read/write uncertainty).
- Noise-mediated threshold crossing.
- Correlation between successive updates.
