# 03 - Non-functional requirements

These apply to every project and to the shared lab. A project file may tighten them, but not loosen them.

## Reproducibility

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-01 | From a fresh clone on a supported host, every project reaches a recorded result using only documented `make` targets and the documented host setup. | Must | Planned |
| NFR-02 | Tool and component versions are pinned: kind, the `kindest/node` image, Cilium, Multus, the bench base images and Go. The pinned versions are listed in the project README. | Must | **Partial**: Go and base image tags pinned in P01; kind node image and digests not yet pinned |
| NFR-03 | Base images are pinned by digest. | Should | Planned |
| NFR-04 | Teardown returns the host to its starting state: clusters deleted, huge pages released, sysctls reverted. Boot-parameter changes on the bare-metal host are documented with their revert. | Must | **Partial**: `make cluster-down hugepages-off` exists; boot-parameter docs pending (P01 M4) |
| NFR-05 | Scripts that change the host are idempotent and say when they use `sudo`. | Must | **Done**: `scripts/hugepages.sh` (run repeatedly in the cloud sandbox) |

## Measurement validity

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-10 | Every result records its environment: host name, environment type (WSL2 / bare metal), kernel version, CPU model and count, SMT and governor state, kind and Kubernetes versions, CNI, variant, git commit and UTC timestamp. | Must | Planned (LAB-13) |
| NFR-11 | Each variant is run at least 3 times; published figures are medians with the min-max spread. | Must | Planned |
| NFR-12 | Latency is reported as p50, p99, p99.9 and max, plus sample count. Averages alone are never published. | Must | **Done**: `bench/bench.sh` output format (P01) |
| NFR-13 | A comparison changes one variable at a time; everything else (node, kernel, image, duration, noise) is held constant and stated. | Must | **Partial**: P01 variants differ only in QoS and huge pages; not yet run |
| NFR-14 | Each run includes a check that the tuning applied (cpuset, CPU manager state, huge page usage, active datapath). A run where the check fails is discarded, not published. | Must | **Partial**: P01 records allowed CPUs per run; automated assertion pending (LAB-15) |
| NFR-15 | Numbers from WSL2 are labelled as non-authoritative and are never compared directly with bare-metal numbers. | Must | **Done**: stated in the P01 README caveats |
| NFR-16 | Raw tool output is kept in `results/`; summaries are generated from it by script. | Must | **Partial**: raw output kept by `bench/run.sh`; summariser pending (LAB-14) |
| NFR-17 | The noise source in a "noisy neighbour" comparison is defined in a manifest and identical across variants. | Must | **Partial**: `manifests/noise.yaml` (P01) |

## Portability

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-20 | The same configs and scripts run on WSL2 and on bare-metal Linux; environment differences are `make` variables. | Must | **Partial**: designed this way; not yet run on either |
| NFR-21 | x86_64 Linux with cgroup v2 is the supported platform. Other platforms aren't blocked, but aren't tested. | Must | **Partial**: documented; preflight check pending (LAB-04) |
| NFR-22 | arm64 hosts work. | Could | Planned |

## Resources and time

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-30 | Every project runs on a laptop with 4 or more CPUs and 16 GB RAM. Projects needing more say so up front. | Must | **Partial**: P01 sized for 4 CPUs and 1 GiB of huge pages |
| NFR-31 | A single benchmark run finishes within 15 minutes; a full project result set (all variants, 3 runs each) within 2 hours. | Should | **Partial**: P01 run is about 1.5 minutes by default |
| NFR-32 | A cluster is created from scratch in under 5 minutes on the bare-metal host. | Should | Planned |

## Code quality and maintainability

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-40 | `make lint` runs shellcheck on scripts, kubeconform (strict) on manifests, and `gofmt` + `go vet` on Go code. | Must | **Partial**: all pass on P01 when run by hand; `make lint` target pending |
| NFR-41 | CI runs `make lint` and Go unit tests on every pull request. | Should | Planned |
| NFR-42 | Code stays small and readable: plain manifests, POSIX/bash scripts, Go standard library. A new dependency needs a stated reason in the project README. | Should | **Done**: P01 memlat is stdlib-only |
| NFR-43 | This PRD is updated in the same commit as a change that alters a requirement's status. | Must | Ongoing |

## Security and safety

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-50 | Benchmark pods get only the capabilities they need (e.g. `SYS_NICE`, `IPC_LOCK`), stated in the manifest. Privileged pods are used only where a project needs them, and the reason is written down. | Must | **Done**: P01 manifests (`SYS_NICE`, `IPC_LOCK` only) |
| NFR-51 | No secrets, tokens or credentials in the repo. | Must | **Done**: none used |
| NFR-52 | Host-level changes are scoped to the lab host and are reversible (NFR-04). | Must | **Partial**: huge pages reversible; boot parameters pending |

## Documentation and publishing

| ID | Requirement | Priority | Status |
| --- | --- | --- | --- |
| NFR-60 | Each project README has Hypothesis, Setup/Method, Results, Caveats and Takeaways sections, and links back to its PRD file. | Must | **Partial**: P01 has all but Results/Takeaways (pending runs) |
| NFR-61 | Writing is plain and short: explain the mechanism, show the commands, state the limits. | Should | Ongoing |
| NFR-62 | Reusable lessons graduate to billy-notes as standalone notes; this repo links to them. | Should | Ongoing |
| NFR-63 | Nothing published contains employer names, code, configs, logs, metrics or architecture details. | Must | Ongoing |
