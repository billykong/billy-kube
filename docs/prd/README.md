# Product requirements: billy-kube

This folder is the product requirements document (PRD) for the low-latency Kubernetes learning track: what we're building, why, the requirements each project must meet, and how we'll know it's done.

The high-level plan and its reasoning live in billy-notes ([low-latency-infra-learning-track.md](https://github.com/billykong/billy-notes/blob/main/kubernetes/low-latency-infra-learning-track.md), [wsl2-vs-bare-metal-for-learning-track.md](https://github.com/billykong/billy-notes/blob/main/kubernetes/wsl2-vs-bare-metal-for-learning-track.md)). This PRD is the concrete, versioned version: requirement IDs, priorities and evidence-backed status.

## Documents

| Document | Contents |
| --- | --- |
| [01-overview.md](01-overview.md) | Problem, goals and non-goals, audience, principles, constraints, success measures |
| [02-lab-architecture.md](02-lab-architecture.md) | Lab topology, environments, benchmark pipeline, shared lab functional requirements (`LAB-`) |
| [03-non-functional-requirements.md](03-non-functional-requirements.md) | Non-functional requirements (`NFR-`): reproducibility, measurement validity, portability, resources, quality, safety, publishing |
| [04-roadmap.md](04-roadmap.md) | Phases, milestones, dependencies, deliverables, risks, open questions |
| [projects/lf-linux-fundamentals.md](projects/lf-linux-fundamentals.md) | LF: Linux performance fundamentals (affinity, NUMA, cgroups v2, huge pages) |
| [projects/p01-cpu-isolation-hugepages.md](projects/p01-cpu-isolation-hugepages.md) | P01: CPU isolation + huge pages + taints/tolerations |
| [projects/p02-sriov-multus.md](projects/p02-sriov-multus.md) | P02: SR-IOV + Multus writeup |
| [projects/p03-cilium-vs-default-cni.md](projects/p03-cilium-vs-default-cni.md) | P03: Cilium/eBPF vs default CNI latency |
| [projects/p04-boundary-design-doc.md](projects/p04-boundary-design-doc.md) | P04: boundary design doc (Kubernetes vs bare metal / kernel bypass) |

Functional requirements are in [02-lab-architecture.md](02-lab-architecture.md) (shared lab) and in each project file. Non-functional requirements apply to every project and are in [03-non-functional-requirements.md](03-non-functional-requirements.md).

## Status at a glance

| Project | Status |
| --- | --- |
| LF Linux fundamentals | Not started (memlat from P01 is reusable for huge pages) |
| P01 CPU isolation + huge pages | Milestone 1 (build) done; not yet run on a cluster. Next: validate on WSL2 |
| P02 SR-IOV + Multus | Not started; waits on the NIC check |
| P03 Cilium vs default CNI | Not started |
| P04 Boundary design doc | Not started; needs evidence from P01 and P03 |

## Conventions

- **Requirement IDs** take the form `<area>-<n>`, e.g. `P01-03`, `LAB-02` or `NFR-11`. IDs are stable: a dropped requirement is marked *Dropped*, never renumbered. Each section starts a new block of numbers (e.g. `P01-01`, `P01-10`, `P01-20`), leaving room to add.
- **Priority:** **Must** (the project isn't done without it), **Should** (expected; omission needs a stated reason) or **Could** (nice to have).
- **Status:** *Done*, *Partial*, *Planned* or *Open question*.
  - *Done* means demonstrated by a named command (a `make` target or script) with its output recorded in `results/` or the project README.
  - *Partial* means built but not yet demonstrated, or demonstrated only in part. A requirement met by configuration that nothing has checked on a running cluster is *Partial*.
- Update this PRD in the same commit as the change that alters a requirement's status.
