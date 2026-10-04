# 01 - CPU isolation + huge pages + taints/tolerations

Benchmark a latency-sensitive workload on kind with and without CPU pinning, huge pages and dedicated tainted nodes.

## Hypothesis

On a node shared with a noisy neighbour:

1. **CPU pinning** (static CPU manager + Guaranteed QoS with integer CPUs) cuts wake-up tail latency (cyclictest p99/p99.9/max), because the neighbour is moved off the benchmark's cores.
2. **2 MiB huge pages** cut dependent-load memory latency (memlat ns/load) on a buffer much larger than TLB reach, because fewer page walks are needed.
3. **Taints/tolerations + a node label** keep general workloads off the latency node, so only pods placed there on purpose share it.

## Setup

`cluster/kind/isolated-cpu.yaml` creates three nodes:

| Node | Kubelet | Role |
| --- | --- | --- |
| `billy-kube-control-plane` | default | control plane |
| `billy-kube-worker` | default (CPU manager `none`) | general workloads |
| `billy-kube-worker2` | `cpu-manager-policy=static`, `reserved-cpus=0`, `topology-manager-policy=best-effort`; label `billy-kube/pool=latency`; taint `billy-kube/latency=true:NoSchedule` | latency node |

Both benchmark variants and the noise pod run on `worker2`, so the only differences between them are the QoS class (and therefore the cpuset) and huge pages.

| | `bench-baseline` | `bench-tuned` |
| --- | --- | --- |
| QoS | Burstable (`cpu: 2` request, no limit) | Guaranteed (`cpu: 2` request = limit) |
| CPUs | Shared pool, alongside `noise` and the reserved CPU | 2 exclusive CPUs |
| Huge pages | none | `hugepages-2Mi: 512Mi` |

The bench image (`bench/Dockerfile`) contains:

- `cyclictest` (rt-tests): timer wake-up latency on the first allowed CPU. SCHED_OTHER by default; set `RT_PRIORITY=80` in the Job for SCHED_FIFO.
- `memlat` (`bench/memlat`, Go): random pointer chase over a 256 MiB buffer, one cache line per hop. It runs once with 4 KiB pages (THP disabled via `MADV_NOHUGEPAGE`) and once with `MAP_HUGETLB` 2 MiB pages.
- `stress-ng`: the `noise` Deployment applies CPU, memory-bandwidth and cache pressure to the shared pool.

`bench/bench.sh` prints one `key=value` line per measurement (`cyclictest ... p50_us p99_us p999_us max_us`, `memlat ... p50_ns p99_ns p999_ns max_ns`) plus the CPUs the pod was allowed to use.

## Method

Needs Docker, kind (v0.20 - v0.27; the config uses the kubeadm v1beta3 `kubeletExtraArgs` map form), kubectl and >= 4 host CPUs.

```bash
make cluster-up-tuned        # reserves 512 x 2 MiB huge pages on the host, then creates the cluster
make check-latency-node      # taint, allocatable hugepages-2Mi, cpu_manager_state (policy "static")
make bench-load              # builds billy-kube/bench:dev and loads it into kind
make bench-baseline          # writes results/baseline-<timestamp>.txt
make bench-tuned             # writes results/tuned-<timestamp>.txt
make cluster-down hugepages-off
```

Run each variant at least 3 times and compare medians: single runs on a laptop are noisy.

Things to check while it runs:

- The tuned pod's `cpus=` line is two CPUs, not CPU 0. The baseline pod's line is the whole shared pool.
- `kubectl -n latency-bench exec deploy/noise -- grep Cpus_allowed_list /proc/self/status` while `bench-tuned` runs: the noise pod's cpuset should exclude the tuned pod's CPUs.
- `kubectl run probe --image=busybox -- sleep 3600` lands on `worker`, never `worker2` (taint).

## Caveats

- **kind nodes share the host kernel and CPUs.** The static CPU manager only isolates within `worker2`: anything on `worker`, the control plane, or the host can still run on the "exclusive" CPUs. Real isolation needs `isolcpus`/`nohz_full`/`irqaffinity` boot parameters on bare metal, with the kubelet's reserved CPUs matching the housekeeping set.
- **Huge pages are a host resource.** Every kind node reports the same host huge page pool as capacity, so the kubelets can over-commit it between them.
- **WSL2**: pinning is to vCPUs and Windows scheduling noise leaks in. Use WSL2 to validate the manifests; use bare-metal Linux for the numbers (see `billy-notes/kubernetes/wsl2-vs-bare-metal-for-learning-track.md`).
- Bare-metal extras for the real runs: `performance` CPU governor, SMT and turbo off (or the `full-pcpus-only` CPU manager policy option), IRQs steered off the benchmark CPUs.

## Results

Not run on a cluster yet. A smoke run of `bench.sh` directly on a 4-vCPU cloud VM (no cluster, no noise, 128 MiB buffer) showed the hugepages effect:

```
memlat hugepages=false size_mb=128 cpus=2-3 ... p50_ns=165.6 p99_ns=397.1
memlat hugepages=true  size_mb=128 cpus=2-3 ... p50_ns=120.0 p99_ns=320.9
```

TODO: baseline vs tuned on WSL2 (manifest validation), then on bare metal.

## Takeaways

TODO
