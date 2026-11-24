# K1 - Research compute grid

Share one batch grid between research teams so that idle capacity gets used, urgent work gets through and no team starves the others, and measure that it does. Kueue does the queueing; KWOK simulates a grid of hundreds of nodes on a laptop; a real kind worker runs actual containers.

Requirements and status: [docs/prd/projects/k1-research-compute-grid.md](../../docs/prd/projects/k1-research-compute-grid.md).

**Status:** milestone 1 (grid and queues) done. Priority and preemption (M2), fair sharing and gang admission (M3) and the measured comparison (M4) are next.

## Hypothesis

On a grid shared by three teams with uneven, bursty demand:

1. **Borrowing** inside a cohort raises utilisation over strict per-team quotas, without raising the owning team's queue wait, provided lent capacity can be reclaimed by preemption.
2. **Priority tiers** get urgent ("pre-open") jobs admitted within seconds, at a measurable cost in preempted work.
3. **Fair sharing** keeps a team that submits 10x more jobs to its weighted share; usage-decay admission (Slurm-style fair share) does better for teams with long jobs.
4. **All-or-nothing admission** prevents the deadlock the default scheduler produces with multi-worker jobs.
5. With no queueing layer, the loudest team wins.

## Setup

| Piece | What | Where |
| --- | --- | --- |
| Cluster | kind, control plane + one worker, `kindest/node:v1.37.0` pinned by digest | `cluster/kind/grid.yaml` |
| Queueing | Kueue v0.20.7; manages Jobs only in team namespaces | `manifests/kueue-config.yaml` |
| Simulated grid | KWOK v0.8.0: 200 CPU nodes (32 CPU, 128 GiB) and 16 GPU nodes (32 CPU, 256 GiB, 8 GPUs) | `scripts/nodes.sh` |
| Simulated run time | A Job pod on a KWOK node succeeds after the duration in its `pod-complete.stage.kwok.x-k8s.io/delay` annotation | `manifests/kwok-stages.yaml` |
| Flavors | `sim-cpu`, `sim-gpu` (KWOK nodes; Kueue adds the KWOK toleration) and `real` (the kind worker) | `manifests/flavors.yaml` |
| Teams | `equities`, `futures`, `options`: a namespace, a LocalQueue and a ClusterQueue each, all in cohort `research` | `manifests/teams.yaml`, `manifests/cluster-queues.yaml` |
| Guard | A ValidatingAdmissionPolicy: in team namespaces, Jobs must name a queue and Pods may only come from the Job controller | `manifests/queue-policy.yaml` |

Kueue and KWOK release files are downloaded once to `~/.cache/billy-kube` and checked against the SHA-256 sums in `install/versions.env` before they are applied.

### Quotas (`sim-cpu`)

| Team | Nominal CPU | Borrowing limit | Most it can hold |
| --- | --- | --- | --- |
| equities | 2400 | 1600 | 4000 |
| futures | 2000 | 1600 | 3600 |
| options | 2000 | 1600 | 3600 |

The three nominal quotas add up to the 6400 CPUs of the simulated CPU nodes; memory is 4 GiB per CPU. GPU quotas (`sim-gpu`) are 32, 32 and 64 GPUs, each able to borrow 32. Flavors are tried in order, so CPU-only jobs land on `sim-cpu` and GPU jobs on `sim-gpu`; only pods that select `billy-kube/pool=grid-real` can use the `real` flavor. No preemption yet: a team can't take back what it lent until M2.

## Running it

```bash
make k1-up        # cluster, Kueue, KWOK, 216 fake nodes, queues (about 1.5-3.5 min)
make k1-verify    # milestone 1 checks, saved to results/verify-<timestamp>.txt
make k1-down
```

`K1_CPU_NODES` and `K1_GPU_NODES` resize the simulated grid (`make k1-nodes`); the quotas assume the defaults. `K1_CLUSTER` changes the cluster name. The scripts use a kubeconfig holding only the grid cluster, so they can't act on another cluster by accident.

**Resources:** the grid uses about 2 GB of memory with 216 fake nodes. On a 16 GB WSL2 machine, stop other kind clusters first.

## Milestone 1 checks

`make k1-verify` runs these on the live cluster, as cluster admin, and prints one line per check:

| Check | What it shows |
| --- | --- |
| `kueue-ready`, `kwok-ready` | Both controllers are available, at the pinned images |
| `kwok-nodes` | 200 CPU and 16 GPU fake nodes are Ready |
| `no-daemonsets-on-fake-nodes` | kindnet and kube-proxy were kept off the fake nodes |
| `queues-active` | Three active ClusterQueues in cohort `research`, each with a LocalQueue |
| `policy-rejects-unqueued-job`, `policy-rejects-bare-pod` | Nothing bypasses the queues, even for a cluster admin (server-side dry run) |
| `policy-ignores-other-namespaces` | The policy is scoped to team namespaces |
| `team-job-admitted` (x3) | Each team's queued job is admitted on `sim-cpu` |
| `sim-run-time` | A simulated pod ran for the 15 s its annotation asked for |
| `borrow-idle-quota` | Equities gets 3200 CPU against a 2400 quota; the ClusterQueue records 800 borrowed |
| `owner-uses-own-quota` | Futures still gets 1920 CPU of its own quota while equities borrows |
| `borrowing-limit-holds` | A further 928 CPU for equities would reach 4128, past its 4000 ceiling; it waits, and Kueue's message says 128 more CPU are needed |
| `gpu-job-on-gpu-flavor` | A GPU job is assigned `sim-gpu` and lands on GPU nodes |
| `real-job-on-real-flavor` | A busybox job runs on the kind worker through the `futures` queue |

All 17 passed on three consecutive runs against a cluster rebuilt from scratch on WSL2 (`results/verify-*.txt`, each starting with its environment record).

## Findings so far

- **A Workload is found by its Job's UID, not its name.** Kueue labels each Workload `kueue.x-k8s.io/job-uid`; there is no job-name label.
- **kindnet and kube-proxy tolerate every taint** (`operator: Exists`), so without the node-affinity patch in `scripts/up.sh` they would put a pod on every KWOK node: 432 extra pods at the default grid size.
- **Admission policies apply to cluster admins too.** The queue-name guard needs no RBAC changes and can't be skipped by the person running the tests, so the negative controls are real.
- **Neither of KWOK's ready-made pod-complete stages fits a trace.** The "fast" one completes pods at once; the "general" one reads a delay annotation but adds up to 5 s of random jitter. K1's stage reads the annotation with no jitter, so run times are exact.

## Caveats

- KWOK pods use no CPU or memory. Queue wait, fairness and utilisation are logical measures that depend on the policies and the trace, not on the host. Control-plane throughput does depend on the host, and belongs to K1a.
- The pod guard trusts the Job controller's identity (`system:serviceaccount:kube-system:job-controller`). JobSet and other integrations (M3) will need their controllers added.
- When `sim-cpu` is full, a CPU-only job can spill onto `sim-gpu` nodes (Kueue tries the next flavor). Realistic, but worth controlling in M4.

## Pinned versions

| Component | Version |
| --- | --- |
| kind | v0.33.0 (tested) |
| Kubernetes (`kindest/node`) | v1.37.0, `sha256:a1ed56cf...` |
| Kueue | v0.20.7 (`install/versions.env`) |
| KWOK | v0.8.0 (`install/versions.env`) |
| CRD schemas for lint | Kueue: datreeio/CRDs-catalog at `04af58d`; KWOK: generated into `schemas/` by `scripts/crd-to-schema.py` |
