# P03 - Cilium/eBPF vs default CNI latency

**Goal:** quantify what Cilium's eBPF datapath changes for pod-to-pod latency and throughput compared with the default CNI, and explain where the difference comes from. Covers goals G1, G2 and G4 in [../01-overview.md](../01-overview.md).

Implementation and findings: [projects/03-cilium-ebpf-vs-default-cni/](../../../projects/03-cilium-ebpf-vs-default-cni/README.md).

## Hypothesis

1. For pod IP to pod IP traffic, Cilium eBPF and kindnet differ little on request/response latency, since both use the kernel stack and the routing paths are similar.
2. For Service IP traffic, Cilium's eBPF service load balancing (kube-proxy replacement) has lower and flatter latency than kube-proxy iptables, and the gap grows with the number of Services.
3. Cross-node traffic shows a larger difference than same-node traffic, depending on encapsulation and host routing mode.

## User stories

- As a **learner**, I can run the same network benchmark on two clusters that differ only in CNI and get comparable tables.
- As a **reviewer**, I can see which datapath was actually active for each run.

## Functional requirements

### Clusters

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P03-01 | A kind config with the default CNI (kindnet) and kube-proxy in iptables mode. | Must | Planned |
| P03-02 | A kind config with `disableDefaultCNI: true` and `kubeProxyMode: none`, plus a pinned Cilium install with kube-proxy replacement and BPF masquerading. | Must | Planned |
| P03-03 | Both clusters have the same node count, node image, kernel and MTU; differences are listed in the README. | Must | Planned |
| P03-04 | A Calico (iptables) cluster as a second "default" baseline. | Could | Open question |

### Benchmarks

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P03-10 | Request/response latency (netperf `TCP_RR` and `UDP_RR`, or sockperf ping-pong), reported as p50/p99/p99.9/max. | Must | Planned |
| P03-11 | Throughput (netperf `TCP_STREAM`). | Must | Planned |
| P03-12 | Scenarios: same-node and cross-node, each to pod IP and to a ClusterIP Service. | Must | Planned |
| P03-13 | Client and server pods are Guaranteed QoS on dedicated nodes, reusing P01's latency node pattern, so CPU noise doesn't swamp network differences. | Should | Planned |
| P03-14 | Service-scale variant: repeat the Service IP test with 1, 1000 and 5000 extra Services to show iptables rule-chain growth vs eBPF map lookups. | Should | Planned |
| P03-15 | NetworkPolicy overhead: the same test with an allow policy applied. | Could | Planned |
| P03-16 | Cilium tuning variants: eBPF host routing, BIG TCP, netkit. | Could | Planned; depends on kernel support |

### Datapath evidence

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P03-20 | Each Cilium run records `cilium status` (kube-proxy replacement, routing and masquerading modes) and confirms kube-proxy isn't running. | Must | Planned |
| P03-21 | Each kindnet run records the kube-proxy mode and the iptables rule count. | Must | Planned |
| P03-22 | A Hubble or `bpftool` capture shows the eBPF programs in the path for one flow. | Should | Planned |

### Writeup

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P03-30 | README with hypothesis, setup, method, results per scenario, caveats and takeaways. | Must | Planned |
| P03-31 | Explain the packet path for each CNI and scenario with a diagram. | Should | Planned |
| P03-32 | Note the WSL2 kernel gaps (billy-notes `kubernetes/cilium-on-wsl2-explained.md`) and run published numbers on bare metal. | Must | Planned |

## Acceptance criteria

P03 is done when every **Must** is *Done*, and the README has a bare-metal table for each scenario (same/cross node × pod/Service IP) for both CNIs, with datapath evidence attached to each run.

## Out of scope

- Encryption (WireGuard/IPsec) overhead, Cilium service mesh and L7 policy.
- Multi-cluster networking.
