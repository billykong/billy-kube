# 01 - Overview

## Problem

Trading firms and other latency-sensitive shops run a mix of Kubernetes and bare metal. The valuable skill is not "can configure Kubernetes" but **knowing where the boundary sits**: which workloads can live on a tuned Kubernetes node, which need bare metal or kernel bypass, and what each tuning knob actually buys.

That judgment is hard to learn from documentation alone, for three reasons:

1. **The knobs interact with the kernel, not just the API.** CPU manager, huge pages and CNI choice only make sense once you've seen the cgroups, cpusets, TLB behaviour and packet paths underneath.
2. **Claims are rarely measured.** "Pinning reduces tail latency" or "eBPF beats iptables" is usually repeated, not demonstrated, and the size of the effect depends on the environment.
3. **Managed clusters hide the plumbing.** A cloud cluster won't let you change kubelet flags, reserve huge pages or swap the CNI datapath and watch what happens.

## Product

**A hands-on lab and portfolio that measures what low-latency Kubernetes tuning does, and uses those measurements to argue where Kubernetes stops.** It consists of:

- a local cluster setup (kind, optionally k3s) with the plumbing visible;
- small Linux performance experiments that explain the mechanisms;
- four portfolio projects (P01-P04), each with a hypothesis, a reproducible method, recorded results and takeaways;
- a design doc that turns the measurements into placement decisions for a toy trading-adjacent system.

It is the Kubernetes half of a hybrid hardware + infra skill set. The FPGA half lives in billy-notes (`fpga/learning-plan-and-projects.md`).

## Audience

| Who | What they need from it |
| --- | --- |
| The author | A structured way to build and demonstrate boundary judgment, with evidence |
| Interviewers and hiring managers at trading firms and platform teams | Proof of depth: measured results, honest caveats, and a reasoned design doc |
| Platform and SRE engineers | Reusable configs and benchmark harnesses for CPU pinning, huge pages and CNI comparisons |
| Readers of the blog posts | Plain explanations of what each knob does, with numbers |

## Goals

1. **G1 - Understand the mechanisms.** Explain, from the kernel up, what CPU affinity, cpusets, CFS quota, huge pages and the CNI datapath do to latency.
2. **G2 - Measure, don't assert.** Every hypothesis gets a reproducible benchmark that compares with and without the change, reporting tail latency, not just averages.
3. **G3 - Show isolation on Kubernetes.** Demonstrate CPU pinning, huge pages and dedicated tainted nodes working on a real kubelet, with checks that the tuning actually applied (P01).
4. **G4 - Compare network datapaths.** Quantify Cilium/eBPF against the default CNI for pod-to-pod latency and throughput (P03), and explain SR-IOV + Multus even where the hardware is missing (P02).
5. **G5 - Exercise boundary judgment.** Produce a design doc that places each component of a toy trading-adjacent system on Kubernetes, tuned Kubernetes, bare metal or kernel bypass, citing the lab's own evidence (P04).
6. **G6 - Be reproducible and publishable.** Anyone with a Linux machine can rerun the lab from the README; results and writeups are public and free of employer IP.

## Non-goals

- **Production-grade low-latency infrastructure.** This is a laptop lab. The aim is understanding and evidence, not a deployable platform.
- **Absolute latency numbers.** Laptops, WSL2 and nested containers make absolute numbers meaningless outside this setup. The lab reports relative effects under stated conditions.
- **Kernel-bypass implementation.** DPDK, AF_XDP, Onload and RDMA are covered in writing (P02, P04), not built, unless hardware makes it cheap.
- **Real market data or trading logic.** The P04 workload is a toy.
- **Managed cloud Kubernetes.** Out of scope by design: the plumbing must stay visible.
- **Agent sandboxing and agent safety.** That's the sister track, in the `safe-ops-agent-k8s` repo.

## Design principles

1. **One variable at a time.** Each comparison changes exactly one thing (QoS class, page size, CNI) on the same node, kernel and image.
2. **Prove the tuning applied before trusting the number.** A benchmark run must show the pod's cpuset, the CPU manager state or the datapath in use. "Faster" without that is not evidence.
3. **Tails over averages.** Report p50, p99, p99.9 and max. Latency-sensitive systems live in the tail.
4. **Validate on WSL2, measure on bare metal.** WSL2 is for getting configs right; numbers that matter come from a bare-metal Linux host.
5. **Keep it small and visible.** Plain manifests, short scripts, stdlib code. No operators or frameworks unless the project is about them.
6. **Write the caveats down.** A stated limitation is defensible; an unstated one looks like a mistake.

## Constraints and assumptions

- **Time:** hobby hours. Per billy-notes, the agentic-systems track (projects 1-4) has priority; this track's P01 and P03 follow it, and P02 is likely a mock.
- **Hardware:** a WSL2 machine for development, and a spare x86_64 laptop running plain Ubuntu/Debian for benchmarks. No SR-IOV NIC is assumed.
- **Kernel:** kind nodes share the host kernel. CPU and huge-page isolation is therefore bounded by the host (see [02-lab-architecture.md](02-lab-architecture.md)).
- **cgroups:** recent kubelets need cgroup v2. Stock WSL2 boots in hybrid mode and needs `cgroup_no_v1=all` (billy-notes `linux/cgroup-v1-vs-v2.md`).

## Success measures

| Measure | Target |
| --- | --- |
| Requirement coverage | Every **Must** requirement in the project files and [03-non-functional-requirements.md](03-non-functional-requirements.md) is *Done*, or has a written reason it can't be |
| Hypotheses tested | Each project's hypothesis is confirmed or refuted with recorded data; a refuted hypothesis is a valid outcome and is written up as such |
| Reproducibility | From a fresh clone on a supported host, the documented `make` targets reach a recorded result for each project with no undocumented steps |
| Evidence quality | Every published result has an environment record, at least 3 runs, tail percentiles and a check that the tuning applied |
| Boundary judgment | The P04 design doc cites at least one measured result from P01 and one from P03 for its placement decisions |
| Publication | One blog post per project (P01, P03, P02 writeup, P04 design doc), plus reusable notes graduated to billy-notes |
