# P02 - SR-IOV + Multus writeup

**Goal:** explain how a latency-sensitive pod gets a dedicated hardware NIC function alongside its normal cluster network, and demonstrate the Multus half on kind even without SR-IOV hardware. Covers goal G4 in [../01-overview.md](../01-overview.md).

Implementation and writeup: [projects/02-sriov-multus/](../../../projects/02-sriov-multus/README.md).

The writeup is the main deliverable. The SR-IOV part is expected to be a mock, since consumer NICs rarely expose virtual functions (VFs).

## Hypothesis

A pod can keep its cluster network (`eth0`) for control traffic while sending latency-sensitive traffic through a secondary interface (`net1`) that bypasses the CNI datapath. With SR-IOV, that interface is a VF handed straight to the pod, aligned with the pod's pinned CPUs on the same NUMA node.

## User stories

- As a **learner**, I can attach a second network interface to a pod on kind and see traffic flow over it.
- As a **reader**, I understand the parts (PF/VF, IOMMU, VFIO, device plugin, SR-IOV CNI, Multus, topology manager) and how they fit together, even if I've never had the hardware.

## Functional requirements

### Hardware check

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P02-01 | Check the bare-metal laptop for SR-IOV support (`/sys/class/net/*/device/sriov_totalvfs`, IOMMU enabled) and record the result in the README. | Must | Planned |

### Multus on kind

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P02-10 | Multus (pinned version) installed on a kind cluster alongside the default CNI. | Must | Planned |
| P02-11 | A `NetworkAttachmentDefinition` using macvlan or ipvlan as the stand-in secondary network. | Must | Planned |
| P02-12 | A pod with `eth0` (cluster network) and `net1` (secondary); traffic between two such pods over `net1` is shown, and its route avoids the CNI. | Must | Planned |
| P02-13 | Latency over `net1` vs `eth0`, measured with the P03 bench image. | Could | Planned |

### SR-IOV

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P02-20 | SR-IOV network device plugin config (resource list) and an SR-IOV `NetworkAttachmentDefinition`, schema-validated and marked "not runnable without VFs" if the NIC check fails. | Must | Planned |
| P02-21 | A pod spec requesting a VF resource plus Guaranteed CPUs, with the topology manager aligning both to one NUMA node (ties to P01). | Must | Planned |
| P02-22 | If the NIC supports it: VFs created, the device plugin advertising them, and a pod using one. | Could | Planned; depends on P02-01 |
| P02-23 | A DPDK-in-a-pod sketch (VFIO-bound VF, huge pages, pinned CPUs) in writing. | Could | Planned |

### Writeup

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P02-30 | A diagram of the full path: PF → VF → device plugin → kubelet → Multus → SR-IOV CNI → pod `net1`. | Must | Planned |
| P02-31 | An explanation of what each part does, what was run and what was mocked, stated plainly. | Must | Planned |
| P02-32 | Trade-offs: VF count limits, live-migration and scheduling constraints, loss of CNI features (NetworkPolicy, Service IPs) on `net1`. | Should | Planned |

## Acceptance criteria

P02 is done when every **Must** is *Done*: the NIC check is recorded, Multus with a secondary interface works on kind, SR-IOV manifests are validated, and the writeup clearly separates what ran from what was mocked.

## Out of scope

- Buying SR-IOV hardware for this project.
- SR-IOV operator and bonded/RDMA configurations.
