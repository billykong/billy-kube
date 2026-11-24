# K1 - Research compute grid

**Goal:** share one batch grid between several research teams so that idle capacity gets used, urgent work gets through, and no team can starve the others, and *measure* that it does. Kueue does the queueing; KWOK simulates a grid of hundreds of nodes on a laptop; a real kind worker runs actual jobs.

This is the first of the "Kubernetes for trading firms" projects (billy-notes `career/low-latency-trading-roadmap.md`). Trading firms mostly keep the hot path off Kubernetes, but research compute (backtests, simulations, training) is a common Kubernetes workload there, and researcher turnaround is what the platform is judged on.

Implementation and findings: [projects/k1-research-grid/](../../../projects/k1-research-grid/README.md).

## Hypothesis

On a grid shared by three teams with uneven, bursty demand:

1. Per-team quotas with **borrowing** inside a cohort raise utilisation over strict per-team quotas, without raising the owning team's queue wait, *provided* lent capacity can be reclaimed by preemption.
2. **Priority tiers** (a "pre-open urgent" class above ordinary research) get urgent jobs admitted within seconds, at a measurable cost in preempted work.
3. **Fair sharing** keeps a team that submits 10x more jobs from taking more than its weighted share over time; usage-decay admission (Slurm-style fair share) does this better than instantaneous fair sharing for teams with long-running jobs.
4. **All-or-nothing admission** prevents the partial-allocation deadlock that the default scheduler produces with multi-worker jobs.
5. With no queueing layer (the default scheduler alone), the loudest team wins: its share tracks its submission rate, not its entitlement.

## Model

| Thing | In K1 |
| --- | --- |
| Teams | `equities`, `futures`, `options`: one namespace and one LocalQueue each |
| Grid | One cohort, `research`, with one ClusterQueue per team |
| Capacity | ResourceFlavors: `sim-cpu` and `sim-gpu` (KWOK nodes, the scale grid) and `real` (kind worker, runs real containers) |
| Jobs | Kubernetes Jobs (Indexed for sweeps) and JobSets for multi-worker jobs; simulated jobs carry their run time as a KWOK annotation |
| Priority | WorkloadPriorityClasses: `pre-open-urgent` > `research` > `backfill` |

## User stories

- As a **researcher**, I submit to my team's queue and my job either runs or waits with a reason I can see; it never fails just because the grid is busy.
- As a **team lead**, my team always gets its nominal share back within a bounded time, even if another team has borrowed it.
- As a **platform engineer**, I can show per-team queue wait, utilisation, fairness over time and work lost to preemption, from recorded runs, and compare policies one change at a time.
- As a **reviewer**, every claim in the README has a check that the policy really applied (quota, borrowing, preemption, admission) next to it.

## Functional requirements

### Grid and queues (M1)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-01 | `make k1-up` creates a kind cluster (`cluster/kind/grid.yaml`) and installs pinned Kueue and KWOK; `make k1-down` deletes it. | Must | **Done**: `scripts/up.sh`, about 1.5-3.5 min from scratch; validated 2026-11-24 by `make k1-verify` (17/17, three runs on a rebuilt cluster, WSL2), checks `kueue-ready`, `kwok-ready` |
| K1-02 | KWOK simulates a configurable grid (`K1_CPU_NODES`, `K1_GPU_NODES`; default 200 CPU nodes and 16 GPU nodes), labelled and tainted so only grid workloads land on them. | Must | **Done**: `scripts/nodes.sh`; check `kwok-nodes`, plus `no-daemonsets-on-fake-nodes` |
| K1-03 | Simulated pods complete after the duration in their `pod-complete.stage.kwok.x-k8s.io/delay` annotation, so jobs have run times without using CPU. | Must | **Done**: `manifests/kwok-stages.yaml`; check `sim-run-time` (15 s asked, 15 s run) |
| K1-04 | Three team namespaces, each with a LocalQueue pointing at its team's ClusterQueue; the three ClusterQueues share the `research` cohort, with nominal quotas for `cpu`, `memory` and `nvidia.com/gpu`. | Must | **Done**: `manifests/cluster-queues.yaml`, `teams.yaml`; checks `queues-active`, `team-job-admitted` x3 |
| K1-05 | A team can borrow idle quota from the cohort up to a `borrowingLimit`; a job that would exceed it waits. | Must | **Done**: checks `borrow-idle-quota` (800 CPU borrowed), `owner-uses-own-quota`, `borrowing-limit-holds` (Kueue: 128 more CPU needed) |
| K1-06 | A Job in a team namespace without a queue name is rejected at admission (ValidatingAdmissionPolicy), so nothing bypasses the quotas. Negative and positive control. | Must | **Done**: `manifests/queue-policy.yaml`; checks `policy-rejects-unqueued-job`, `policy-rejects-bare-pod` (as cluster admin), `policy-ignores-other-namespaces` |
| K1-07 | `make k1-verify` checks the above on a running cluster and prints one `check=... result=pass/fail` line per check. | Must | **Done**: `scripts/verify.sh`, output in `results/verify-*.txt` |
| K1-08 | The `real` flavor maps to a kind worker, so a small job runs a real container through the same queues. | Should | **Done**: check `real-job-on-real-flavor` (busybox on the kind worker through the `futures` queue) |

### Priority and preemption (M2)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-10 | WorkloadPriorityClasses `pre-open-urgent`, `research` and `backfill`. | Must | Planned |
| K1-11 | A team reclaims lent quota by preempting the borrower (`reclaimWithinCohort`), and the reclaim time is measured. | Must | Planned |
| K1-12 | Within a team, `pre-open-urgent` preempts lower-priority work (`withinClusterQueue: LowerPriority`). | Must | Planned |
| K1-13 | Work lost to preemption (CPU-seconds run before eviction) is recorded per run. | Must | Planned |
| K1-14 | Preempted jobs requeue and complete; none are lost. | Must | Planned |

### Fair sharing and gang admission (M3)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-20 | Fair sharing across the cohort with per-team weights. | Must | Planned |
| K1-21 | Usage-decay admission fair sharing (`admissionFairSharing`, Slurm-style), compared with K1-20. | Should | Planned |
| K1-22 | Multi-worker jobs (JobSet) are admitted all-or-nothing (`waitForPodsReady`); a demonstration shows the default scheduler deadlocking two partially started jobs, and Kueue not. | Must | Planned |

### Load and measurement (M4)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-30 | A load generator submits jobs per team from a seeded trace (arrival rate, size and run-time distributions), with one team deliberately "loud". The trace file is kept with the results. | Must | Planned |
| K1-31 | Per run: queue wait p50/p99/max per team and priority, utilisation over time, fairness over time (share vs entitlement, and Jain's index), preempted CPU-seconds, jobs completed. Derived from the API objects' timestamps by script, not read from dashboards. | Must | Planned |
| K1-32 | The same trace is run against: default scheduler (no Kueue), strict quotas (no borrowing), cohort borrowing, borrowing + fair sharing, borrowing + admission fair sharing. One change at a time (NFR-13). | Must | Planned |
| K1-33 | Each configuration is run 3 or more times with different seeds; results are medians with spread (NFR-11). | Must | Planned |
| K1-34 | A run fails if the policy it claims to test did not apply (e.g. no workload borrowed in a borrowing run), per LAB-15. | Should | Planned |

### Real workload (M5)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-40 | A parameter-sweep backtest (Indexed Job) over a slice of the public Nasdaq ITCH 5.0 sample file runs on the `real` flavor through a team queue. | Should | Planned |
| K1-41 | When the C++ order book exists, the backtest uses it. | Could | Planned |

### Writeup (M6)

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| K1-50 | Project README with hypothesis, setup, method, results, caveats and takeaways (NFR-60). | Must | Planned |
| K1-51 | Blog post answering "how would you share a research grid between 20 teams without the loudest one winning, and how would you know it's working?" | Should | Planned |

## Acceptance criteria

K1 is done when every **Must** above is *Done*, and the README shows, from recorded runs of the same trace: queue wait per team, utilisation and fairness for each configuration in K1-32, with the check that each policy applied.

## Environment

Queue wait, fairness and utilisation here are *logical* measures: KWOK pods use no CPU, so these numbers depend on the policies and the trace, not on the host. Results from WSL2 are therefore valid for K1 core, labelled with their environment (NFR-10). Control-plane throughput is host-dependent and belongs to K1a, which publishes from bare metal.

## Depth projects (after the core)

| Project | Scope |
| --- | --- |
| K1a Scheduling at scale | 100k short jobs: scheduler throughput, API server and etcd load, Job controller lag; one pod per task vs Indexed Jobs vs JobSet vs batching inside long-lived workers. Bare metal for published numbers. |
| K1b Scheduler plugin (Go) | Score nodes by cached tick-data partitions, or bin-pack large jobs; measured on KWOK against the default scorer. |
| K1c Data path | Tick data as Parquet in MinIO, a node-local cache, backtest throughput cold vs warm, interaction with K1b. |
| K1d Elastic capacity | Cluster autoscaler with its KWOK provider; a preemptible tier with checkpoint and resume; wasted work measured. |

Each gets its own requirements here when it starts.

## Out of scope

- Real market data beyond the public ITCH sample, and any trading logic beyond a toy backtest.
- MultiKueue and multi-cluster dispatch: that's K2.
- Topology-aware scheduling: noted for K1a if node count makes it relevant.
