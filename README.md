# billy-kube

Hands-on Kubernetes / low-latency infra learning track, run on a local cluster (kind, optionally k3s) so the plumbing stays visible. The plan lives in `billy-notes/kubernetes/low-latency-infra-learning-track.md`.

## Layout

| Path | Purpose |
| --- | --- |
| `cluster/` | Shared local-cluster configs (kind, k3s) |
| `linux-fundamentals/` | Small experiments: CPU affinity, cgroups v2, huge pages |
| `projects/01-cpu-isolation-hugepages/` | CPU isolation + huge pages + taints/tolerations, benchmarked with and without tuning |
| `projects/02-sriov-multus/` | SR-IOV + Multus home-lab writeup (may be simulated) |
| `projects/03-cilium-ebpf-vs-default-cni/` | Cilium/eBPF vs default CNI latency comparison |
| `projects/04-boundary-design-doc/` | Design doc: what stays on K8s vs bare-metal/kernel-bypass |
| `scripts/` | Shared helpers (bench runners, result collectors) |
| `docs/` | Lab logs and short notes; reusable ones go to billy-notes |

## Conventions

Each project has a `README.md` (hypothesis, method, results), `manifests/`, `bench/` and `results/` where applicable.
