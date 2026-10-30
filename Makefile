CLUSTER ?= billy-kube
KIND_CONFIG ?= cluster/kind/base.yaml
HUGEPAGES ?= 512
BENCH_IMAGE ?= billy-kube/bench:dev
P01 := projects/01-cpu-isolation-hugepages
RESULTS ?= $(P01)/results
KUBECONFORM ?= go run github.com/yannh/kubeconform/cmd/kubeconform@v0.6.7
K8S_VERSION ?= 1.31.0

SH_FILES := $(shell find scripts projects -name '*.sh')
SH_TESTS := $(shell find scripts projects -name '*_test.sh')
MANIFESTS := $(shell find projects -path '*/manifests/*.yaml')
GO_MODULES := $(patsubst %/go.mod,%,$(shell find projects -name go.mod))

.PHONY: cluster-up cluster-down cluster-up-tuned hugepages-on hugepages-off \
	bench-image bench-load bench-baseline bench-tuned check-latency-node \
	summarise lint test host-status host-tuning-runtime host-revert-runtime \
	host-tuning-boot host-revert-boot

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

# Project 01 milestone 4: host tuning stages (see scripts/host-tuning.sh).
host-status:
	scripts/host-tuning.sh status

host-tuning-runtime:
	sudo scripts/host-tuning.sh apply-runtime

host-revert-runtime:
	sudo scripts/host-tuning.sh revert-runtime

host-tuning-boot:
	sudo scripts/host-tuning.sh apply-boot

host-revert-boot:
	sudo scripts/host-tuning.sh revert-boot

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

# Median (min-max) table per environment and variant from saved results.
summarise:
	python3 scripts/summarise.py $(RESULTS)

lint:
	shellcheck -x $(SH_FILES)
	$(KUBECONFORM) -strict -summary -kubernetes-version $(K8S_VERSION) $(MANIFESTS)
	@unformatted=$$(gofmt -l $(GO_MODULES)); \
	  if [ -n "$$unformatted" ]; then echo "gofmt needed: $$unformatted"; exit 1; fi
	for m in $(GO_MODULES); do (cd $$m && go vet ./...) || exit 1; done
	python3 -m py_compile scripts/*.py

test:
	for m in $(GO_MODULES); do (cd $$m && go test ./...) || exit 1; done
	for t in $(SH_TESTS); do $$t || exit 1; done
	cd scripts && python3 summarise_test.py
