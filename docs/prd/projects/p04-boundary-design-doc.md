# P04 - Boundary design doc

**Goal:** design a toy trading-adjacent system and argue, component by component, what runs on Kubernetes, what runs on tuned Kubernetes, and what needs bare metal, kernel bypass or FPGA, using the lab's own measurements as evidence. Covers goal G5 in [../01-overview.md](../01-overview.md).

Document: [projects/04-boundary-design-doc/design-doc.md](../../../projects/04-boundary-design-doc/design-doc.md).

## User stories

- As an **interviewer**, I can read one document and see how the author reasons about latency budgets, isolation and operational cost.
- As a **platform engineer**, I can reuse the decision criteria for my own placement decisions.

## Functional requirements

### Content

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P04-01 | Define the toy workload: market-data feed handler, strategy engine, order gateway, pre-trade risk, reference data, post-trade/analytics and monitoring. | Must | Planned |
| P04-02 | Give each component a latency budget (order of magnitude), throughput, state, and availability need. | Must | Planned |
| P04-03 | Place each component on one of: plain Kubernetes, tuned Kubernetes (pinned, huge pages, dedicated nodes), bare metal with kernel bypass, or FPGA. Give the reason for each. | Must | Planned |
| P04-04 | Cite at least one measured result from P01 and one from P03 for the placements they inform. | Must | Planned |
| P04-05 | Trade-offs for each placement: determinism, operational cost, deployment speed, observability, failure domains, staffing. | Must | Planned |
| P04-06 | Failure modes: the hot path must not depend on the Kubernetes control plane (API server, scheduler) being available. Explain how that's guaranteed. | Must | Planned |
| P04-07 | Alternatives considered for at least two components, and why they were rejected. | Should | Planned |
| P04-08 | A hybrid option: Kubernetes managing bare-metal nodes with performance profiles (e.g. Node Tuning Operator), and where it fits. | Should | Planned |
| P04-09 | Relate the FPGA placement to the PS/PL split in billy-notes `fpga/learning-plan-and-projects.md`. | Could | Planned |

### Form

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P04-20 | A system diagram showing components, placement and data flow. | Must | Planned |
| P04-21 | Structured as a real design doc: context, goals/non-goals, proposal, alternatives, risks, open questions. | Must | Planned |
| P04-22 | Reviewed once against the evidence (does each claim trace to a result or a cited source?) before publishing. | Should | Planned |

## Acceptance criteria

P04 is done when every **Must** is *Done*, and every placement decision traces to either a lab result or a cited external source.

## Out of scope

- Real exchange protocols, market data or strategy logic.
- Cost modelling in money terms.
