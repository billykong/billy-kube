CLUSTER ?= billy-kube
KIND_CONFIG ?= cluster/kind/base.yaml

.PHONY: cluster-up cluster-down

cluster-up:
	kind create cluster --name $(CLUSTER) --config $(KIND_CONFIG)

cluster-down:
	kind delete cluster --name $(CLUSTER)
