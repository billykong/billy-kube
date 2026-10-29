# 01 - CPU isolation + huge pages + taints/tolerations

Benchmark a latency-sensitive workload on kind with and without CPU pinning, huge pages and dedicated tainted nodes.

Requirements and status: [docs/prd/projects/p01-cpu-isolation-hugepages.md](../../docs/prd/projects/p01-cpu-isolation-hugepages.md).

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
make summarise               # median (min-max) table per environment and variant
make cluster-down hugepages-off
```

Run each variant at least 3 times and compare medians: single runs on a laptop are noisy. `make summarise` flags any group with fewer than 3 runs.

### What a run checks and records

`bench/run.sh` writes a result file only if every step passes, so `results/` never holds a run whose tuning didn't apply:

1. `scripts/env-record.sh` writes an `env` line: host, WSL2 or bare metal, kernel, CPU model and count, SMT, governor, turbo, host huge pages, kind and Kubernetes versions, CNI, git commit (and whether the tree was dirty) and a UTC timestamp.
2. While the Job runs, `bench/check-tuning.sh` reads the latency node's kubelet config (`node` line: CPU manager and topology manager policies, reserved CPUs) and compares the bench pod's cpuset with the noise pod's (`check` line):
   - `tuned` must have exactly its CPU limit in CPUs, none shared with the noise pod, on a node with the static policy. The kubelet moves shared-pool pods off newly exclusive CPUs on its reconcile loop (10s by default), so the check retries for up to 30s.
   - `baseline` must share CPUs with the noise pod, which proves the baseline really is noisy.
3. The Job must succeed. `memlat -hugepages` exits non-zero if the huge pages aren't there, which fails the Job.

The check only uses `kubectl` (pod cpusets and the kubelet's `configz` endpoint), so it works the same on kind and k3s.

Also check by hand once per cluster: `kubectl run probe --image=busybox -- sleep 3600` lands on `worker`, never `worker2` (taint).

### Tests

`make lint` (shellcheck, kubeconform, gofmt, go vet) and `make test` (memlat Go tests, `bench/*_test.sh` against a stub `kubectl`, summariser tests) run without a cluster, and in CI on every pull request.

## Caveats

- **kind nodes share the host kernel and CPUs.** The static CPU manager only isolates within `worker2`: anything on `worker`, the control plane, or the host can still run on the "exclusive" CPUs. Real isolation needs `isolcpus`/`nohz_full`/`irqaffinity` boot parameters on bare metal, with the kubelet's reserved CPUs matching the housekeeping set.
- **Huge pages are a host resource.** Every kind node reports the same host huge page pool as capacity, so the kubelets can over-commit it between them.
- **WSL2**: pinning is to vCPUs and Windows scheduling noise leaks in. Use WSL2 to validate the manifests; use bare-metal Linux for the numbers (see `billy-notes/kubernetes/wsl2-vs-bare-metal-for-learning-track.md`).
- Bare-metal extras for the real runs: `performance` CPU governor, C-state limits, SMT and turbo off (or the `full-pcpus-only` CPU manager policy option), IRQs steered off the benchmark CPUs.
- **C-states.** Without host tuning, an exclusive CPU with nothing else on it goes idle between cyclictest wake-ups and drops into deep C-states, so pinning can make the wake-up tail *worse* (see Results). cyclictest normally prevents this by holding `/dev/cpu_dma_latency` at 0, but the device isn't in the container (`WARN: stat /dev/cpu_dma_latency failed`).
- **The baseline runs on CPU 0**, the kubelet's reserved CPU: cyclictest pins to the first allowed CPU, and the shared pool includes the reserved set.
- **Huge pages after a reboot.** The host reservation is not persistent. After a reboot, run `make hugepages-on`, then `docker exec billy-kube-worker2 systemctl restart kubelet` so the node reports them again.

## Results

### Milestone 2: validation on a bare-metal laptop, no host tuning

2026-10-29, `billykong-x1`: i7-1165G7 (4 cores / 8 threads, one NUMA node), kernel 6.8.0-138-generic, `powersave` governor, turbo on, SMT on; kind v0.27.0, Kubernetes v1.32.2, kindnet. Commit `aa3e5e6`, clean tree. Every run passed its tuning check: tuned got CPUs `1,5` (both threads of one core) with the noise pod moved off them; baseline shared CPUs with the noise pod. Median (min-max) of 3 runs, from `make summarise` over `results/`:

| Variant | Tool | Mode | p50 | p99 | p99.9 | max |
| --- | --- | --- | --- | --- | --- | --- |
| baseline | cyclictest | SCHED_OTHER | 58 µs | 64 (63-68) µs | 94 (93-1645) µs | 5161 (4753-8408) µs |
| tuned | cyclictest | SCHED_OTHER | 55 µs | 164 (142-220) µs | 1522 (981-1688) µs | 6425 (3872-6660) µs |
| baseline | memlat | 4 KiB pages, 256 MiB | 173 (173-173) ns | 281 (269-289) ns | 579 (448-620) ns | 22755 (12228-23689) ns |
| tuned | memlat | 4 KiB pages, 256 MiB | 151 (146-151) ns | 209 (206-218) ns | 405 (377-440) ns | 19776 (13400-21164) ns |
| tuned | memlat | 2 MiB pages, 256 MiB | 126 (122-127) ns | 174 (172-178) ns | 340 (320-341) ns | 19743 (15813-31621) ns |

- **Huge pages (hypothesis 2) hold.** On the same pinned CPUs, 2 MiB pages cut memlat p50 by 17% and p99 by 17% against 4 KiB pages.
- **Pinning (hypothesis 1) does not hold without host tuning.** Tuned p99 is about 2.5× the baseline's, and its p99.9 is about 16× higher. The per-CPU idle counters explain it. In an earlier 60 s tuned run, the bench's CPU 1 entered C1 298,251 times, C2 2,891 times and C3 523 times. CPU 0, shared with stress-ng, entered C2 and C3 12 times each. Exit latencies on this CPU are 253 µs for C2 and 1048 µs for C3, which matches the tuned p99 and p99.9. The busy neighbour keeps the baseline's core awake. Commands and numbers: `billy-notes/kubernetes/c-states-defeat-cpu-pinning.md`.
- **One baseline outlier.** The second baseline run (`baseline-20261029T103252Z`, p99.9 1645 µs) started right after a tuned run, before the kubelet had put CPUs `1,5` back in the shared pool (its check line shows `noise_cpus=0,2-4,6-7`). It is kept, since its check passed, but it inflates the baseline p99.9 range.

The cyclictest histogram goes to 20 ms (`HIST_MAX_US`), so none of these runs overflowed.

Next (M4): the same runs with host tuning (performance governor, C-state limits, `isolcpus`/`nohz_full`/`irqaffinity`), to see whether pinning beats the baseline once the core can't sleep.

## Takeaways

TODO
