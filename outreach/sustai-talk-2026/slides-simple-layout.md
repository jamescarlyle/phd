---
marp: true
theme: default
header: ''
headingDivider: 1
footer: 'James Carlyle Neuromorphic Research Update October 2026'
style: |
  section {
    background-image: 
      url('../images/sustai-logo.png'),
      url('../images/uos-logo.png'),
      url('../images/ukri-logo.png');
    background-position: 
      20px 20px, 
      220px 20px, 
      420px 20px;
    background-size: 
      auto 30px, 
      auto 30px, 
      auto 30px;
    background-repeat: no-repeat;
  }
  section {
    font-size: 1.3em;
  }
  /* --- LAYOUT 1: Text on Top, Horizontal Images Row --- */
  section.layout-top {
    display: flex;
    flex-direction: column;
    padding: 40px;
    box-sizing: border-box;
  }
  section.layout-top h1, 
  section.layout-top h2, 
  section.layout-top p:not(:has(img)) {
    flex: 0 0 auto;
    margin-bottom: 20px;
  }
  /* Container for horizontal images taking up remaining whitespace */
  section.layout-top p:has(img) {
    display: flex;
    gap: 20px;
    flex: 1;
    justify-content: center;
    align-items: center;
    margin: 0;
    min-height: 0; /* Prevents flex overflow */
  }
  section.layout-top img[alt*="horizontal"] {
    height: 100%;
    max-height: 100%;
    width: auto;
    object-fit: contain;
    flex: 1;
  }

  /* --- LAYOUT 2: Text on Left, Vertical Stack on Right --- */
  section.layout-split {
    display: grid;
    grid-template-columns: 350px 1fr;
    gap: 40px;
    padding: 40px;
    box-sizing: border-box;
    align-items: center;
  }
  /* Left column: text elements */
  section.layout-split h1, 
  section.layout-split h2, 
  section.layout-split p:not(:has(img)), 
  section.layout-split ul, 
  section.layout-split ol {
    grid-column: 1;
  }
  /* Right column wrapper for vertical images */
  section.layout-split p:has(img) {
    grid-column: 2;
    grid-row: 1 / span 10;
    display: flex;
    flex-direction: column;
    gap: 15px;
    justify-content: center;
    align-items: center;
    height: 100%;
    margin: 0;
    min-height: 0;
  }
  section.layout-split img[alt*="vertical"] {
    width: 100%;
    max-width: 100%;
    height: auto;
    max-height: 100%;
    object-fit: contain;
    flex: 1;
  }
---

# Research: Hardware-aware in-situ learning in an analog spiking neural network.
James Carlyle, AI for Sustainability CDT, Sustainable Electronic Technologies, University of Southampton.
Supervised by Dr. Firman Simanjuntak and Prof. Mark Zwolinski, University of Southampton.

# Topics

## My goal

## What is a spiking neural network?

## What is a spiking neuron?

## What is a memristor?

## What is in-situ learning?

## What do we need hardware-awareness?

## Initial results

# My goal

The human brain is amazingly energy-efficient. It can perform an exaflop (10e18) with just 20 watts of power [1]. 

In traditional digital "Von-Neumann" architecture, data transfer between CPU and memory consumes 10-100x more energy than the logic operation [2]. In-memory computing (IMC) minimises data movement to improve efficiency. 

My research goal is to 

- **simulate** a multi-layer spiking neural network,
- **fabricate** it using all-analog electronic devices,
- then **train** it using on-chip learning methods, 
- and understand whether **variability** enables or hinders performance.

<!-- _footer: "1. https://www.nist.gov/blogs/taking-measure/brain-inspired-computing-can-help-us-create-faster-more-energy-efficient. 

2. https://arxiv.org/abs/2401.14428" -->

# What is a spiking neural network?

Similar to artificial neural network : weights -> **synapses**, nodes -> **neurons**. Information is encoded by spike frequency or timing, not by amplitude.

![horizontal](./images/ribeiro-spiking-network.png)

<!-- _footer: "1. https://www.sciencedirect.com/science/article/pii/S0167865524002344" -->

# What is a spiking neuron?

The spiking behaviour of a neuron is a **non-linear activation function**, equivalent to sigmoid or ReLU in ANN.

![horizontal](./images/spiking-neuron-animation.gif)

<!-- _footer: "1. https://medium.com/thedeephub/understand-spiking-neural-network-through-code-implementation-8b48fc7f096b" -->

# Biological neurons exhibit 6 main behaviours:

1. integration 
2. threshold firing
3. cascading spikes
4. homeostastis (firing reduces sensitivity)
5. refactory period
6. stochasticity

![bg right:60% height:500px](./images/zhao-spiking.png)

<!-- _footer: "1. https://www.nature.com/articles/s41928-025-01488-x" -->

# What is a memristor?

Leon Chua predicted the memristor, the missing 4th fundamental passive device, in 1971. 

- Flux is the integral of voltage; charge is the integral of current.
- Resistor relates voltage and current.
- Inductor relates flux and current.
- Capacitor relates charge and voltage.
- **Memristor** relates flux and charge.

Researchers at HP Labs built the first working memristor in 2008.

![bg right:40% height:400px](./images/chua-4th-device.png)

<!-- _footer: "1. https://www.nature.com/articles/s41928-018-0074-4" -->

# What roles can memristors play in neuromorphic computing?

- As a **synapse**, with a programmable weight. 
- This requires **non-volatile** behaviour.
- A memristor array can create a summable current based on known applied voltages at known conductances.

![bg right:50% h:400](./images/dias-memristors-a-journey.png)

<!-- _footer: "1. https://www.nature.com/articles/s41928-018-0074-4" -->

# What roles can memristors play in neuromorphic computing?

- As a **neuron**, with a highly non-linear voltage-dependent conductance. 
- A sudden increase in conductance generates an output spike.
- This requires repeatable, consistent **volatile** behaviour.

![bg right:50% vertical contain](./images/deepthi-adaptive-memristor.png)
![bg contain](./images/xia-memristive-crossbar.png)

<!-- _footer: "1. https://www.nature.com/articles/s41928-018-0074-4" -->

# What types of memristor exist? 

4 types of memristor (even the taxonomy is debated):

- **Resistive switching**, notably **metal-cation filaments** through oxygen-vacancy defects.
- Phase change.
- Spintronics.
- Ferroelectric.

![bg right:70% height:700px](./images/in-hyuk-im-4-types.png)

<!-- _footer: "1. https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aisy.202000105" -->

# How do filaments integrate voltage and current?

- Memristance behaves like a resistance which depends on the history of charge that has flowed through the device.
- Typical memristor: Ag electrode | ZnO insulator layer | Pt electrode.  
- Applying a voltage across electrodes, the Ag (silver) is oxidised to form Ag+ ions + electrons.
- Ag+ ions migrate through ZnO defects, reduced at the anode to Ag, and form a cluster which begins to bridge the electrodes.
- The reduced gap increases the local electric field and accelerates migration.
- A complete bridge moves the memristor from high resistive state (HRS) to low resistive state (LRS).

![horizontal h:300](./images/minika-ozga-filamentary-resistive.png)

<!-- _footer: "1. https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/aisy.202000105" -->

# Variability in memristors as synapses

- Memristors exhibit Cycle-to-Cycle (C2C) and Device-to-Device (D2D) variability.
- Often used in research as a source of entropy in random number generation. 
- For synapses, we can accept C2C and D2D variability during training (e.g. more or fewer potentiation pulses) as long as we can continue to modify conductance in the right direction. 
- We need stable conductance during inference.

![horizontal h:350](./images/aidan-taox-c2c.png)

<!-- _footer: "1. Aidan Graham, TaOx memristor potentiation and depression response, 2026." -->

# Variability in memristors as neurons

![bg right:50% vertical w:350px](./images/D131-SA10-D29-IV-sweep-5V-10uA.png)
![bg w:600px](./images/D131-SA10-D29-3pulse-4V-2uS.png)
![bg w:350px](./images/D133-SA10-D29-IV-4V-10uA.png)
![bg w:600px](./images/D131-SA10-H25-24-pulse-1_2V-20uS-3-runs.png)

- For neurons, low C2C variability and consistent threshold firing is needed.
- First device characterisation results of 2022 ZnO/Ag fabricated wafers were promising.
- Further tests demonstrated a high-resistance-state (HRS) to low-resistance-state (LRS) transition voltage between 1V and 3.5V.
- Research is needed into the effects of variability on accuracy.

<!-- _footer: "1. James Carlyle, ZnO/Ag, I/V sweep 5V 10uA compliance.

2. James Carlyle, ZnO/Ag, 3 pulse 4V 5uS.

3. James Carlyle, ZnO/Ag, I/V sweep 5V 5uA compliance.

4. James Carlyle, ZnO/Ag, 20 pulse 1.2V 10uS." -->

# What is in-situ (on-chip) learning?

- Spiking Neural Networks cannot use standard back-propagation, as the spikes cannot be differentiated. 
- Surrogate gradient descent is one work-around, normally used off-chip. 
- Spike Timing-Dependent Plasticity (STDP) depends on the relative timing of spikes of pre-synaptic and post-synaptic neurons. An example of Hebbian learning: "Neurons which fire together wire together."
![bg right:60% height:400px](./images/prezioso-stdp.png)

<!-- _footer: "1. https://www.nature.com/articles/s41467-018-07757-y" -->

# What is in-situ (on-chip) learning?

- STDP relies on the spike timing difference of neighbouring neurons.
- A variant, Voltage Dependent Synaptic Plasticity (VDSP) relies on voltage difference between the "pre-synaptic neuron" and the "post-synaptic" neuron at its firing point.
- VDSP relies on a negative reset voltage and an observable decay to a resting voltage.
- Weight update is proportional to the voltage difference.
![bg right:50% h:400px](./images/garg-vdsp.png)

<!-- _footer: "1. https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2022.983950/full" -->

# Early spiking neural network simulations

- The simulation model from the canonical paper on STDP (Diehl et al., 2015) running on Brian2 (C/Python) is used to provide a baseline.
- Spiking threshold variability is introduced to see the impact on feature detections (SD 5mV, threshold mean 50mV)

![horizontal h:350](./images/diehl-brian2-60K-no-modification.png)
![horizontal h:350](./images/diehl-brian2-60K-no-modification.png)

<!-- _footer: "1. https://brian2.readthedocs.io/en/stable/examples/frompapers.Diehl_Cook_2015.html

2. Same model, but spike-to-spike 5mV threshold standard deviation applied."-->

# Thank you

James Carlyle
james.carlyle@soton.ac.uk
