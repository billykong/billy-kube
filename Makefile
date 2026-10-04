CLUSTER ?= billy-kube
KIND_CONFIG ?= cluster/kind/base.yaml
HUGEPAGES ?= 512
BENCH_IMAGE ?= billy-kube/bench:dev
P01 := projects/01-cpu-isolation-hugepages

.PHONY: cluster-up cluster-down cluster-up-tuned hugepages-on hugepages-off \
	bench-image bench-load bench-baseline bench-tuned check-latency-node

cluster-up:
	kind create cluster --name $(CLUSTER) --config $(KIND_CONFIG)

cluster-down:
	kind delete cluster --name $(CLUSTER)

# Project 01: reserve huge pages first, the kubelet reads them at startup.
cluster-up-tuned: hugepages-on
	kind create cluster --name $(CLUSTER) --config cluster/kind/isolated-cpu.yaml

hugepages-on:
	scripts/hugepages.sh on $(HUGEPAGES)

hugepages-off:
	scripts/hugepages.sh off

bench-image:
	docker build -t $(BENCH_IMAGE) $(P01)/bench

bench-load: bench-image
	kind load docker-image $(BENCH_IMAGE) --name $(CLUSTER)

bench-baseline:
	$(P01)/bench/run.sh baseline

bench-tuned:
	$(P01)/bench/run.sh tuned

# Shows the latency node's taint, huge page capacity and CPU manager state.
check-latency-node:
	kubectl get node $(CLUSTER)-worker2 -o jsonpath='{.spec.taints}{"\n"}{.status.allocatable}{"\n"}'
	docker exec $(CLUSTER)-worker2 cat /var/lib/kubelet/cpu_manager_state; echo
