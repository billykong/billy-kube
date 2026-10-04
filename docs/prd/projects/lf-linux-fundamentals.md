# LF - Linux performance fundamentals

**Goal:** understand the kernel mechanisms underneath the Kubernetes knobs, outside Kubernetes first, so P01 and P03 results can be explained rather than just reported. Covers goal G1 in [../01-overview.md](../01-overview.md).

Implementation: [linux-fundamentals/](../../../linux-fundamentals/).

## User stories

- As a **learner**, I can reproduce each effect with a few shell commands on a plain Linux host, then point to where Kubernetes sets the same thing.
- As a **reader**, I can see the mapping from a pod spec field to the kernel setting it becomes.

## Functional requirements

### CPU affinity (`linux-fundamentals/cpu-affinity/`)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| LF-01 | Run the same latency benchmark (cyclictest) free-floating and pinned with `taskset`, with and without background noise, and record the difference. | Must | Planned |
| LF-02 | Show where a process's allowed CPUs come from (`sched_getaffinity`, `/proc/<pid>/status`, the cpuset cgroup) and how the kubelet's CPU manager writes them. | Must | Planned |
| LF-03 | Show IRQ placement (`/proc/interrupts`, `/proc/irq/*/smp_affinity_list`) and move IRQs off a CPU. | Should | Planned (bare metal) |

### cgroups v2 (`linux-fundamentals/cgroups-v2/`)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| LF-20 | Create a cgroup by hand, set `cpuset.cpus` and `cpu.max`, move a process in and observe the effect. | Must | Planned |
| LF-21 | Demonstrate CFS quota throttling: a bursty workload under `cpu.max`, with `cpu.stat` `nr_throttled`/`throttled_usec` next to its latency tail. Relate to pod CPU limits. | Must | Planned |
| LF-22 | Map a pod's QoS class and resources to its cgroup path and files on a kind node (`kubepods.slice/...`). | Should | Planned |
| LF-23 | Read PSI (`cpu.pressure`, `memory.pressure`) under noise. | Could | Planned |

### Huge pages (`linux-fundamentals/hugepages/`)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| LF-40 | Reserve and release 2 MiB huge pages; show `/proc/meminfo` and per-node counts under `/sys/devices/system/node/`. | Must | **Partial**: `scripts/hugepages.sh` does reserve/release/status |
| LF-41 | Compare 4 KiB, THP and explicit 2 MiB pages on the same pointer chase (memlat), and explain the gap with TLB reach. | Must | **Partial**: memlat covers 4 KiB and 2 MiB; THP mode not yet a flag |
| LF-42 | Use hugetlbfs (mounted) as well as anonymous `MAP_HUGETLB`, and relate both to a pod's `hugepages-2Mi` request and `HugePages` emptyDir. | Should | Planned |
| LF-43 | 1 GiB huge pages, if the bare-metal CPU supports them. | Could | Planned |

### NUMA (`linux-fundamentals/numa/`)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| LF-60 | Show the topology (`numactl --hardware`, `lscpu`) and measure local vs remote memory latency with memlat under `numactl --membind`. | Should | Planned; needs a multi-node host, else documented as not applicable |

### Notes

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| LF-80 | Each folder's README states the commands, the observed result and the Kubernetes equivalent. | Must | Planned |
| LF-81 | Reusable takeaways graduate to billy-notes `linux/`. | Should | Planned |
