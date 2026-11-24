#!/usr/bin/env bash
# Creates (or resizes to) the simulated grid: K1_CPU_NODES CPU nodes and
# K1_GPU_NODES GPU nodes, managed by KWOK. Nodes beyond the requested count
# are deleted. Quotas in manifests/cluster-queues.yaml assume the defaults.
# Usage: nodes.sh            (uses K1_CPU_NODES, K1_GPU_NODES)
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

cpu_nodes=${K1_CPU_NODES:-200}
gpu_nodes=${K1_GPU_NODES:-16}

# node <name> <type> <cpu> <memory> <gpus>
node() {
  cat <<YAML
---
apiVersion: v1
kind: Node
metadata:
  name: $1
  annotations:
    kwok.x-k8s.io/node: fake
    node.alpha.kubernetes.io/ttl: "0"
  labels:
    type: kwok
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: $1
    kubernetes.io/os: linux
    billy-kube/pool: grid-sim
    billy-kube/node-type: $2
spec:
  taints:
    - key: kwok.x-k8s.io/node
      value: fake
      effect: NoSchedule
status:
  allocatable: {cpu: "$3", memory: $4, pods: "110", nvidia.com/gpu: "$5"}
  capacity: {cpu: "$3", memory: $4, pods: "110", nvidia.com/gpu: "$5"}
  nodeInfo: {architecture: amd64, operatingSystem: linux, kubeletVersion: fake}
YAML
}

if [ "${1:-}" != "--print" ]; then k1_kubeconfig; fi
manifest=$(
  for ((i = 0; i < cpu_nodes; i++)); do node "$(printf 'grid-cpu-%03d' "$i")" cpu 32 128Gi 0; done
  for ((i = 0; i < gpu_nodes; i++)); do node "$(printf 'grid-gpu-%03d' "$i")" gpu 32 256Gi 8; done
)
if [ "${1:-}" = "--print" ]; then echo "$manifest"; exit 0; fi

log "applying $cpu_nodes CPU and $gpu_nodes GPU KWOK nodes"
echo "$manifest" | kubectl apply --server-side -f - >/dev/null

# Remove nodes beyond the requested counts.
kubectl get nodes -l type=kwok -o name | while read -r n; do
  name=${n#node/}
  idx=$((10#${name##*-}))
  case $name in
    grid-cpu-*) [ "$idx" -lt "$cpu_nodes" ] || kubectl delete "$n" >/dev/null ;;
    grid-gpu-*) [ "$idx" -lt "$gpu_nodes" ] || kubectl delete "$n" >/dev/null ;;
  esac
done
want=$((cpu_nodes + gpu_nodes))
for _ in $(seq 60); do
  ready=$(kubectl get nodes -l type=kwok --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)
  [ "$ready" -eq "$want" ] && { log "$ready KWOK nodes Ready"; exit 0; }
  sleep 2
done
log "only $ready of $want KWOK nodes Ready"; exit 1
