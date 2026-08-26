# Screening Protocol Template  
## Spiking Neural Networks Literature Review  
*(Neuromorphic Hardware, Memristors, On‑Chip Learning)*

---

## 1. Review Question and Scope

**Primary question:**  
What are the state-of-the-art approaches for implementing on-chip learning in spiking neural networks using memristive and/or ferroelectric devices, and how do they trade off accuracy, energy, area, and robustness?

**Scope boundaries:**

- **Included topics:**
  - Spiking neural networks (SNNs) with biologically plausible or hardware-oriented neuron/synapse models.
  - On-chip / in-situ learning (analog, mixed-signal, or low-digital-overhead).
  - Device-level implementations or detailed simulations of memristors, FeFETs, or related non-volatile memories as synapses.
  - Learning rules: STDP, three-factor learning, e-prop, local Hebbian/Oja-style rules, surrogate-gradient methods with hardware considerations.

- **Excluded topics:**
  - Purely software SNNs with no hardware relevance or constraints.
  - ANN→SNN conversion without discussion of native SNN training or hardware implications.
  - Papers without quantitative results (accuracy, energy, latency, area, or equivalent).

---

## 2. Search Strategy

### 2.1 Databases

- IEEE Xplore  
- ScienceDirect / Scopus  
- Web of Science  
- arXiv (cs.NE, cs.ET, eess.SP)  
- PubMed (for biologically grounded SNN work, if relevant)  
- ACM Digital Library (for neuromorphic architectures)

### 2.2 Example Search Strings

Adapt syntax per database.

**String A – Core hardware + learning:**

```text
("spiking neural network" OR SNN) 
AND ("memristor" OR "memristive" OR "crossbar" OR "FeFET" OR "ferroelectric") 
AND ("on-chip learning" OR "in-situ learning" OR STDP OR "three-factor learning" OR "e-prop") 
AND ("hardware" OR "neuromorphic" OR "analog" OR "mixed-signal" OR ASIC OR FPGA)
```

**String B – Device-focused:**

```text
(memristor OR "resistive RAM" OR "RRAM" OR "FeFET" OR "ferroelectric FET") 
AND (synapse OR "synaptic plasticity" OR "long-term potentiation" OR "long-term depression") 
AND ("spiking" OR SNN OR "neuromorphic")
```

**String C – On-chip learning architectures:**

```text
("on-chip learning" OR "in-situ learning" OR "hardware learning") 
AND ("spiking neural network" OR SNN) 
AND ("low-power" OR "edge AI" OR "neuromorphic processor")
```

Apply filters:  
- Publication years: **2015–2026** (with emphasis on 2019–2026 for hardware).  
- Document types: journal articles, conference papers, arXiv preprints with substantial technical content.  
- Language: English.

---

## 3. Study Selection Process

Use a **two-stage screening**:

### 3.1 Title/Abstract Screening (Level 1)

For each record, answer:

1. **Does the work involve spiking neural networks or neuromorphic spiking systems?**  
   - Yes / No / Unclear

2. **Does it address hardware implementation or hardware-relevant simulation (device/circuit/architecture level)?**  
   - Yes / No / Unclear

3. **Does it involve learning/plasticity (on-chip, in-situ, or hardware-aware training)?**  
   - Yes / No / Unclear

**Decision rule:**  
- Include if **all three** are “Yes”.  
- Mark as “Maybe” if any are “Unclear”.  
- Exclude if any are definitively “No” and the others are not strong enough to compensate.

Record reason for exclusion in one line (e.g., “No SNN”, “Pure software ANN”, “No learning”).

### 3.2 Full-Text Screening (Level 2)

For records passing Level 1, assess:

4. **Does the paper provide quantitative performance metrics?**  
   (e.g., accuracy, energy/inference, latency, area, spikes/op, J/classification)  
   - Yes / No

5. **Is the learning rule clearly specified and relevant to on-chip implementation?**  
   (STDP, three-factor, e-prop, local rules, surrogate gradient with hardware constraints)  
   - Yes / No / Partial

6. **Are device or circuit details sufficient to judge hardware feasibility?**  
   (technology node, device model, variability, endurance, analog/digital partitioning)  
   - Yes / No / Partial

7. **Is the work sufficiently distinct from other included papers?**  
   (Not just incremental parameter tuning of an already-covered architecture, unless it adds new insight.)  
   - Yes / No

**Decision rule:**  
- Include if: Q4 = Yes **and** at least two of Q5–Q7 are “Yes” or “Partial” with clear relevance.  
- Exclude otherwise, with a short reason.

---

## 4. Data Extraction Form

For each included study, extract:

### 4.1 Bibliographic Information

- Authors:  
- Year:  
- Title:  
- Venue (journal/conference/arXiv):  
- DOI / URL:  
- Open access / code available (Y/N + link):

### 4.2 Network Architecture

- Neuron model (LIF, Izhikevich, HH, custom):  
- Number of layers:  
- Coding scheme (rate, temporal, hybrid):  
- Network size (neurons, synapses):  
- Dataset(s) used:  
- Task type (classification, detection, control, etc.):

### 4.3 Learning Rule and Training

- Learning rule (STDP, three-factor, e-prop, surrogate gradient, other):  
- Supervision level (unsupervised, supervised, reinforcement, self-supervised):  
- Presence of third factor (reward, error signal, global modulatory signal):  
- Training method (online, offline, in-situ, ex-situ then deployed):  
- Key hyperparameters (time constants, learning rates, eligibility trace decay, etc.):

### 4.4 Hardware Implementation

- Implementation type:  
  - [ ] Full silicon (ASIC)  
  - [ ] FPGA  
  - [ ] Mixed-signal prototype  
  - [ ] Analog-only block  
  - [ ] Detailed circuit simulation (SPICE/Cadence)  
  - [ ] High-level simulation with hardware constraints

- Technology node (if applicable):  
- Memory/synapse technology:  
  - [ ] SRAM  
  - [ ] DRAM  
  - [ ] Memristor / RRAM  
  - [ ] FeFET / ferroelectric  
  - [ ] Other NVM: _______

- Analog/digital partitioning (brief description):  
- Area (mm² or µm² per synapse/neuron, if reported):  
- Power/energy metrics (static, dynamic, energy/inference, energy/spike):  

### 4.5 Performance and Robustness

- Accuracy / performance metric(s):  
- Energy per inference / per spike / per operation:  
- Latency / throughput:  
- Robustness analysis (variability, noise, device non-idealities, temperature):  
- Comparison baseline (ANN, other SNN, prior hardware):

### 4.6 Limitations and Notes

- Main limitations acknowledged by authors:  
- Limitations you observe (e.g., small datasets, idealised devices, no variability):  
- Relevance to  project (1–3 sentences):  

---

## 5. Quality Assessment Criteria

Rate each included paper on a simple scale (Low / Medium / High) for:

1. **Hardware realism**  
   - High: Silicon or detailed circuit/device simulation with non-idealities.  
   - Medium: High-level simulation with some hardware constraints.  
   - Low: Pure algorithmic work with minimal hardware consideration.

2. **Learning relevance**  
   - High: Native on-chip learning rule with clear hardware mapping.  
   - Medium: Ex-situ training but with hardware-aware constraints.  
   - Low: Standard deep learning methods with little hardware discussion.

3. **Reproducibility**  
   - High: Code and/or detailed models provided.  
   - Medium: Sufficient detail to re-implement with effort.  
   - Low: Insufficient detail.

Use these ratings to weight evidence in  synthesis (e.g., emphasise High/High/High papers when drawing conclusions about feasibility).

---

## 6. Workflow and Tools

- **Reference manager:** Zotero  
  - Use collections: `SNN_Review_Included`, `SNN_Review_Excluded`, `SNN_Review_Maybe`.  
  - Tags: `device:memristor`, `device:FeFET`, `learning:STDP`, `learning:three-factor`, `hw:analog`, `hw:mixed-signal`, etc.

- **Screening spreadsheet / database:**  
  Columns:  
  - `ID` (Zotero key)  
  - `Title`  
  - `Year`  
  - `Level1_decision` (Include/Exclude/Maybe)  
  - `Level2_decision` (Include/Exclude)  
  - `Reason_exclude`  
  - `Quality_hardware` (L/M/H)  
  - `Quality_learning` (L/M/H)  
  - `Quality_repro` (L/M/H)  
  - `Notes`

- **PRISMA-style flow:**  
  Keep counts for:  
  - Records identified  
  - After duplicates removed  
  - Title/abstract screened  
  - Full texts assessed  
  - Studies included in review  

---

## 7. Inclusion/Exclusion Decision Log Template

For each excluded paper, log:

- **ID:**  
- **Title:**  
- **Stage:** Level 1 / Level 2  
- **Reason:** (choose from predefined list + free text)  
  - No SNN  
  - No hardware relevance  
  - No learning/plasticity  
  - No quantitative results  
  - Pure ANN / SNN conversion without hardware discussion  
  - Insufficient detail on devices/circuits  
  - Duplicate / superseded by later work  
  - Other: _______

---

## 8. Synthesis Plan (Brief)

Once screening is complete:

1. Group included papers by:
   - Device technology (memristor, FeFET, other).
   - Learning rule (STDP, three-factor, e-prop, surrogate gradient).
   - Implementation style (analog, mixed-signal, FPGA, full custom).

2. For each group, summarise:
   - Typical architectures and scales.
   - Reported energy/accuracy/area trade-offs.
   - Handling of device non-idealities and variability.
   - Gaps relative to  target system (e.g., multi-layer analog SNN with on-chip STDP/VDSP).

3. Identify:
   - Best-performing approaches for  metrics of interest.
   - Under-explored combinations (e.g., ferroelectric devices + three-factor learning in multi-layer analog SNNs).
   - Open challenges (variability, endurance, scaling, training stability).
