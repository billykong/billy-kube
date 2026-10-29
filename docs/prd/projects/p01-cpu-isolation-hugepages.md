# P01 - CPU isolation + huge pages + taints/tolerations

**Goal:** show, with measurements, what CPU pinning, huge pages and a dedicated tainted node do for a latency-sensitive workload on Kubernetes, and where the benefit stops. Covers goals G1-G3 in [../01-overview.md](../01-overview.md).

Implementation and findings: [projects/01-cpu-isolation-hugepages/](../../../projects/01-cpu-isolation-hugepages/README.md).

## Hypothesis

On a node shared with a noisy neighbour:

1. Static CPU manager + Guaranteed QoS with integer CPUs cuts wake-up tail latency (cyclictest p99/p99.9/max).
2. 2 MiB huge pages cut dependent-load memory latency on a buffer much larger than TLB reach.
3. A taint plus node label keeps general workloads off the latency node.
4. On kind, (1) is limited by the shared host kernel; host boot parameters on bare metal add a further, measurable improvement.

## User stories

- As a **learner**, I can bring up a cluster with a tuned latency node, run baseline and tuned variants, and see the difference in numbers.
- As a **reviewer**, I can see proof that the tuning applied (cpusets, CPU manager state, huge page allocation) next to each result.
- As a **reader**, I can see which effect came from pinning, which from huge pages and which from host tuning.

## Functional requirements

### Cluster and node

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P01-01 | A latency node runs the kubelet with `cpu-manager-policy=static` and a reserved CPU set for system and kube daemons. | Must | **Done**: `cluster/kind/isolated-cpu.yaml`; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-02 | The latency node carries label `billy-kube/pool=latency` and taint `billy-kube/latency=true:NoSchedule`. | Must | **Done**: same config; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-03 | A pod without the toleration never lands on the latency node; one with the toleration and node selector does (negative and positive control). | Must | **Done**: a `busybox` probe without the toleration landed on `worker`; the bench Jobs (toleration + selector) land on `worker2`; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-04 | 2 MiB huge pages are reserved on the host before the cluster starts and appear in the latency node's allocatable resources. | Must | **Done**: `make cluster-up-tuned` reserves them; `worker2` allocatable shows `hugepages-2Mi: 1Gi`. Host reservation does not survive a reboot: re-run `make hugepages-on` and restart the node's kubelet |
| P01-05 | The topology manager policy is set and recorded with results. | Should | **Done**: `best-effort` in config; recorded in each result's `node` line; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-06 | `make check-latency-node` prints the taint, allocatable resources and CPU manager state. | Should | **Done**: validated 2026-10-29 (M2, bare-metal laptop) |

### Workloads

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P01-10 | A noisy-neighbour Deployment (stress-ng: CPU, memory bandwidth, cache) runs on the latency node with Burstable QoS. | Must | **Done**: `manifests/noise.yaml`; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-11 | A baseline variant runs the benchmark on the latency node with Burstable QoS and no huge pages. | Must | **Done**: `manifests/bench-baseline.yaml`; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-12 | A tuned variant runs the same benchmark with Guaranteed QoS, integer CPUs and a `hugepages-2Mi` request. | Must | **Done**: `manifests/bench-tuned.yaml`; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-13 | While the tuned variant runs, its CPUs are exclusive: the noise pod's cpuset excludes them. | Must | **Done**: asserted on every tuned run by `bench/check-tuning.sh` (bench `1,5`, noise `0,2-4,6-7`); validated 2026-10-29 (M2, bare-metal laptop) |
| P01-14 | The benchmark can run cyclictest under `SCHED_FIFO` (`RT_PRIORITY`) as well as `SCHED_OTHER`. | Should | **Done**: `bench/bench.sh` smoke run with `RT_PRIORITY=80` |
| P01-15 | A third variant isolates huge pages from pinning: Guaranteed QoS without huge pages, or huge pages without pinning. | Could | Planned (tuned already runs memlat with both page sizes) |

### Measurement

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P01-20 | cyclictest wake-up latency on one allowed CPU, reported as p50/p99/p99.9/max in µs with sample and overflow counts. | Must | **Done**: `bench/bench.sh` smoke run, output in the P01 README |
| P01-21 | memlat measures pointer-chase latency with 4 KiB pages (THP disabled) and with 2 MiB huge pages, reported as p50/p99/p99.9/max in ns. | Must | **Done**: `memlat` smoke run with both page sizes, output in the P01 README |
| P01-22 | Each result shows the variant, node and the CPUs the pod was allowed to use. | Must | **Done**: `bench/bench.sh` header line |
| P01-23 | Each variant is run 3 or more times on WSL2 (validation) and on bare metal (published numbers). | Must | **Partial**: 3 runs per variant on a bare-metal laptop without host tuning (M2 validation, replacing WSL2); host-tuned runs pending (M4) |
| P01-24 | On bare metal, a further run adds host tuning: `isolcpus`/`nohz_full`/`irqaffinity` matching the kubelet's reserved CPUs, performance governor, SMT and turbo off. Documented with revert steps. | Must | Planned (M4) |
| P01-25 | A run fails if the tuned pod didn't get exclusive CPUs or huge pages (see LAB-15). | Should | **Done**: `bench/run.sh` + `bench/check-tuning.sh`; huge pages enforced by `memlat -hugepages` failing the Job; validated 2026-10-29 (M2, bare-metal laptop) |
| P01-26 | The `full-pcpus-only` CPU manager policy option is compared on an SMT host. | Could | Planned |
| P01-27 | CFS quota throttling is shown: a pod with a CPU limit but no pinning, under load, with `cpu.stat` throttling counts next to its latency (links to LF-21). | Could | Planned |

### Writeup

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| P01-30 | The project README covers hypothesis, setup, method, results, caveats and takeaways. | Must | **Partial**: M2 validation results and caveats in; bare-metal tuned results and takeaways pending |
| P01-31 | Caveats cover the shared kernel, the shared huge page pool and WSL2 vCPUs. | Must | **Done**: P01 README |
| P01-32 | A blog post with the results table and the mechanism behind each effect. | Should | Planned |

## Acceptance criteria

P01 is done when every **Must** above is *Done* and the README results table shows, from bare-metal runs with environment records: baseline vs tuned cyclictest tails, memlat 4 KiB vs 2 MiB, and the added effect of host tuning, each with the check that the tuning applied.

## Out of scope

- Memory manager (`Static` policy) and NUMA-aligned memory: noted as future work unless the bare-metal host has more than one NUMA node.
- Real-time kernels (`PREEMPT_RT`): open question in [../04-roadmap.md](../04-roadmap.md).
- Node Tuning Operator / performance profiles: mentioned in P04, not built.
