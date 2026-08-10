# Summer Transition Project for SustAI CDT 2025/26

**Student:** James Carlyle

**Student ID:** 

**Supervisory Team:** Dr. Firman Simanjuntak, Prof. Mark Zwolinski

**Primary PhD Topic / Working Title:** Multilayer memristor–CMOS spiking neural networks with on‑chip learning: FPGA co-designed architectures for low power event‑based processing.

**Project Period:** 8 June 2026 to 11 September 2026

**Programme:** UKRI AI Centre for Doctoral Training in AI for Sustainability, University of Southampton

## Document purpose

This report covers the summer project undertaken. It covers the core elements specified in the brief: introduction, literature review, proposed methodology, impact assessment, plan of future work, references, and a timeline.

## Suggested word budget

| Section | Suggested words | Notes |
|---|---:|---|
| Introduction | 400–700 | Topic framing, motivation, scope. |
| Literature Review | 1,500–2,000 | Critical review, gap identification, research objectives. |
| Proposed Methodology | 800–1,200 | Methods, data, tools, feasibility, training needs. |
| Impact Assessment | 600–900 | RRI, sustainability, SDGs, ethics, stakeholders. |
| Plan of Future Work | 700–1,000 | 3-year PhD plan and first 9 months in detail. |
| References | Variable | Not usually counted in the main word limit unless instructed otherwise. |

## 1. Introduction

### 1.1 Research context

Neuromorphic computing seeks to emulate the brain’s event‑driven, massively parallel processing using energy‑efficient hardware models such as spiking neural networks (SNNs). Hybrid memristor–CMOS architectures are promising for this purpose because drift memristors naturally implement analog synaptic weights and local plasticity, while diffusive memristors provides robust neuron firing dynamics.

### 1.2 Problem statement

The Internet of Things (IOT) requires intelligent information processing in the field, away from powerful and energy-consuming cloud and datacentre-based AI capabilities. Without low-power local AI inference, very large amounts of data need to be transitted for central processing, requiring energy, reliable bandwidth and connectivity, latency, and the provision of land, energy grid and water supplies.

IOT devices are often disconnected from energy grids, and then have a limited energy budget, constrained by energy harvesting and battery capacity. This in turn leads to a requirement for ongoing human involvement in maintenance and replacement.

### 1.3 Motivation and significance

Although the field of machine learning (ML) is considered mature, most of the work achieved so far assumes ever-larger and more powerful models running on centralised hardware, with the primary aim of improving accuracy against well-established benchmark datasets and problems. Power demands of frontier models (especially for training) are rising exponentially and will become the limiting factor for further adoption; datacentres cannot be built because of the lack of energy grid and cooling water availability. 

The human brain is often quoted for its extraordinary efficiency, with consumption of 20w compared with the kilo- or mega-watts of power needed to operate a traditional computer of equivalent capability, and this has made it the inspiration for a new field of computing, Neuromorphic, which aims to circumvent the energy consumption needed to move data from memory to CPU in the traditional Von-Neumann architecture. 

Recent work has demonstrated memristor‑CMOS neuromorphic chips with online spike-timing-dependent-plasticity (STDP) learning at the synapse level and small‑scale SNNs with on‑chip adaptation, but most systems either remain shallow, rely on ex‑situ weight programming, or lack tight integration with digital neuromorphic platforms such as FPGAs.

Power consumption per inference in extremely constrained environments is measured, but often only for single devices (synapses, neurons), not for complete systems.

This project aims to bridge these developments by designing, fabricating, and evaluating a multilayer memristor–CMOS SNN core with genuine on‑chip learning, co‑designed with an FPGA‑based SNN platform that serves as both a high‑speed prototype and a training controller. The focus will be on event‑based vision or time‑series tasks relevant to ultra‑low‑power, DVS‑free neuromorphic hardware.

### 1.4 Scope of the summer transition project

[Clarify what this summer project covers, and what it does not yet attempt to solve.]

### 1.5 Chapter overview

[Provide a short map of the remaining sections.]

## 2. Literature Review

### 2.1 Search strategy

[Document how the literature search was performed: databases, keywords, time windows, inclusion/exclusion criteria, and any review logic used.]

### 2.2 Background and foundational concepts

#### Memristor–CMOS neuromorphic architectures

Hybrid memristor–CMOS systems use memristive devices (e.g. ReRAM cells) to store synaptic weights in crossbar arrays and CMOS neuron circuits to implement spiking dynamics.

Published memristor–CMOS neuromorphic chips have demonstrated on‑chip STDP learning in synapses, basic pattern recognition, and small‑scale neural cores, often in 130 nm CMOS with sub‑micrometre memristor devices.

Reviews of CMOS‑compatible memristors emphasise analog tunability, endurance, and integration challenges, and point to neuromorphic computing as a key application area.

#### On‑chip learning in memristive neural networks

Work on memristor‑based neural networks has explored both ex‑situ training (ANN/SNN training in software followed by weight programming into crossbars) and in‑situ training using local learning rules.

On‑chip training schemes for SNNs include STDP variants and supervised approximations to backprop adapted to hardware, where timing and pulse‑based updates are critical to realising learning in physical synapses.

Recent studies argue that robust on‑chip learning in memristor‑based networks requires careful handling of device variability, limited conductance precision, and non‑linear update dynamics.

#### FPGA‑based neuromorphic and SNN systems

FPGAs have been widely used to implement SNNs because they offer reconfigurable logic, DSP blocks, and custom spike routing, enabling real‑time neuromorphic processing at the edge.

FPGA‑based neuromorphic vision accelerators demonstrate event‑driven processing pipelines where SNNs classify or track objects using spike trains derived from image sensors.

These systems provide an excellent platform for rapid architectural exploration, precise timing control, and integration with conventional cameras and other sensors, but they do not typically exploit analog synaptic computation.

#### Gaps and originality

There is a clear gap in scalable multilayer memristor–CMOS SNNs with on‑chip learning, particularly where analog synapses are tightly co‑designed with a digital neuromorphic platform that can both emulate and train them.

Existing memristor–CMOS chips tend to focus on single‑layer cores or small networks and rarely provide systematic comparisons against FPGA‑based SNN implementations under identical tasks and metrics.

Conversely, FPGA SNN accelerators rarely interface to trainable analog cores, meaning that the potential energy and latency advantages of memristive crossbars are not exploited in end‑to‑end systems.

This project will address these gaps by designing a multilayer memristor–CMOS SNN core with on‑chip learning and integrating it with an FPGA platform for experimentation, training, and system‑level evaluation on event‑based tasks.



### 2.3 Current state of the art

[Review the most relevant studies, methods, systems, datasets, benchmarks, policies, or theoretical approaches. Organise by theme rather than paper-by-paper where possible.]

### 2.4 Critical analysis of existing work

[Evaluate strengths, limitations, assumptions, methodological weaknesses, contradictory findings, and open issues.]

### 2.5 Identified research gap(s)

[State clearly what is missing in the literature. Be explicit about the unresolved technical, scientific, methodological, or application-level gaps.]

### 2.6 Research objectives and questions

[Translate the identified gaps into clear objectives, hypotheses, and/or research questions.]

### 2.7 Novelty and significance

[Explain what is novel about the proposed direction and why it would matter if successful.]

## 3. Proposed Methodology

### 3.1 Methodological overview

[Describe the overall research design and justify why it is suitable for addressing the identified gaps.]

### 3.2 Proposed methods

[Detail the methods, models, experiments, analytical techniques, simulations, fieldwork, datasets, case studies, or design processes you expect to use.]

### 3.3 Data, resources, and infrastructure

[Identify expected data sources, software, hardware, facilities, lab access, compute requirements, and any external dependencies.]

### 3.4 Evaluation strategy

[Explain how success will be measured: metrics, baselines, validation strategy, comparison methods, robustness checks, or qualitative evaluation.]

### 3.5 Risks, assumptions, and limitations

[Identify key risks and assumptions, then explain mitigation plans and fallback options.]

### 3.6 Skills audit and training needs

[Identify technical or professional skills gaps. Link these to a training plan for the PhD phase.]

| Skill / capability gap | Why it matters | Planned training or action | Indicative timing |
|---|---|---|---|
| [Example] | [Reason] | [Course / reading / supervision / practice] | [When] |

## 4. Impact Assessment

### 4.1 Overview of anticipated impact

[Describe the potential academic, environmental, industrial, societal, and policy relevance of the proposed research.]

### 4.2 Responsible Research and Innovation

[Assess the project using the RRI ideas taught in SUST6001.]

#### 4.2.1 4Ps framework

[Discuss the relevant 4Ps dimensions as taught in your programme, and explain how they apply to this project.]

#### 4.2.2 AREA framework

[Structure the discussion under Anticipate, Reflect, Engage, and Act/Respond, as appropriate to your course framing.]

| AREA element | Project-specific considerations | Proposed actions |
|---|---|---|
| Anticipate | [Potential impacts, risks, uncertainties] | [Actions] |
| Reflect | [Assumptions, values, blind spots] | [Actions] |
| Engage | [Stakeholders to involve] | [Actions] |
| Act / Respond | [How project design may adapt] | [Actions] |

### 4.3 Sustainability considerations

[Explain how sustainability is embedded in the project, including lifecycle, energy, materials, deployment, accessibility, social sustainability, or systems-level effects where relevant.]

### 4.4 Relevant Sustainable Development Goals

[Identify and justify the SDGs most relevant to the project.]

| SDG | Relevance to project | Evidence / rationale |
|---|---|---|
| [SDG number and title] | [Why relevant] | [Short justification] |

### 4.5 Ethics and governance

[Note any ethical issues, regulatory requirements, governance concerns, data protection issues, safety implications, or approvals that may be needed.]

### 4.6 Stakeholders and beneficiaries

[Identify who may benefit, who may be affected, and how stakeholder perspectives may shape the research.]

## 5. Plan of Future Work

### 5.1 Overview of PhD direction

[Summarise the intended overall trajectory of the PhD over the 3-year research phase.]

### 5.2 Detailed plan for the first 9 months

[Provide a detailed plan leading up to the first progression report, including literature work, technical setup, pilot studies, methods development, supervisory engagement, and early outputs.]

| Month | Planned activities | Deliverables / milestones |
|---|---|---|
| 1 | [Activities] | [Outputs] |
| 2 | [Activities] | [Outputs] |
| 3 | [Activities] | [Outputs] |
| 4 | [Activities] | [Outputs] |
| 5 | [Activities] | [Outputs] |
| 6 | [Activities] | [Outputs] |
| 7 | [Activities] | [Outputs] |
| 8 | [Activities] | [Outputs] |
| 9 | [Activities] | [Outputs] |

### 5.3 Milestones for years 1 to 3

[Set out major milestones across the full PhD period, including formal progression points and research outputs.]

| Period | Milestones | Notes |
|---|---|---|
| Year 1 | [First progression review, pilot results, initial publication target] | [Notes] |
| Year 2 | [Confirmation review and major study completion] | [Notes] |
| Year 3 | [Third progression review, thesis writing, publications, completion planning] | [Notes] |

### 5.4 Gantt chart notes

[Insert or link the Gantt chart here, or explain where it is provided. The chart should cover the 3-year PhD period, include detailed planning for the first 9 months, and show key milestones such as progression reviews, publications, and major research stages.][1]

### 5.5 Meeting and supervision plan

[Summarise how weekly supervisory meetings and additional meetings with other supervisory team members will be organised during the project and early PhD phase.][1]

### 5.6 Contingency planning

[Describe fallback plans if the original research route, data access, technical platform, or experimental setup changes.]

## 6. References

[Insert references in your required citation style, for example IEEE, APA, Harvard, or a department-approved alternative.]

***

## Appendices

### Appendix A. Summer project timeline

- Start date: w/c 8 June 2026.[1]
- Submission deadline: 11 September 2026.[1]
- Duration: 12 weeks plus 2 weeks of holiday to be agreed with supervisors.[1]
- Possible extensions: typically 1–2 weeks where justified by September exam resits or extenuating circumstances, subject to supervisory approval.[1]

### Appendix B. Submission and assessment notes

- The report is submitted through the SustAI CDT summer project submission form.[1]
- The supervisory team assesses the report first and should provide formative feedback within one month of submission.[1]
- The CDT director checks whether the report and Gantt chart meet minimum requirements.[1]
- The summer project report should later be attached alongside the first progression review submission in the PGR Manager System, where both are considered at the progression review viva.[1]

### Appendix C. Optional paper-style submission variant

[Use this appendix only if the supervisory team agrees that the summer project will be written in paper form rather than thesis-style report form.]

- Proposed paper title.
- Target venue or paper format.
- Abstract.
- Introduction.
- Related work.
- Method / proposed approach.
- Early results or planned evaluation.
- Added impact assessment section.
- Added future work / PhD plan section.

## Checklist before submission

- [ ] Introduction drafted.
- [ ] Literature review includes a clear gap analysis.
- [ ] Research objectives are explicit and justified.
- [ ] Methodology is feasible and well matched to the research gap.
- [ ] Skills gaps and training needs are identified.
- [ ] RRI discussion includes 4Ps and AREA.
- [ ] Sustainability and SDGs are addressed.
- [ ] First 9 months of the PhD are planned in detail.
- [ ] 3-year Gantt chart is included or attached.
- [ ] Key progression milestones are shown.
- [ ] References are complete and consistently formatted.
- [ ] Supervisor feedback has been incorporated where available.
