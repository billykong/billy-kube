#!/usr/bin/env bash
# Brings up the K1 grid: kind cluster, pinned Kueue and KWOK (release files
# checked against install/versions.env), the KWOK node grid, and the queues.
# Idempotent: re-running converges an existing cluster.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source-path=SCRIPTDIR/.. source=install/versions.env
. "$K1_DIR/install/versions.env"

# fetch <url> <sha256>: download once into the cache, verify, print the path.
fetch() {
  local url=$1 sum=$2 file
  file="$CACHE_DIR/$(basename "$(dirname "$url")")-$(basename "$url")"
  mkdir -p "$CACHE_DIR"
  if [ ! -s "$file" ]; then
    curl -fsSL -o "$file.tmp" "$url"
    mv "$file.tmp" "$file"
  fi
  if ! echo "$sum  $file" | sha256sum -c --quiet - >&2; then
    log "checksum mismatch for $url"; rm -f "$file"; exit 1
  fi
  echo "$file"
}

# retry <tries> <cmd...>: webhooks take a while to serve after rollout.
retry() {
  local n=$1; shift
  for ((i = 1; i <= n; i++)); do "$@" && return 0; sleep 3; done
  return 1
}

if ! kind get clusters 2>/dev/null | grep -qx "$K1_CLUSTER"; then
  log "creating kind cluster $K1_CLUSTER"
  kind create cluster --name "$K1_CLUSTER" --config "$REPO_DIR/cluster/kind/grid.yaml"
fi
k1_kubeconfig

kueue=$(fetch "$KUEUE_URL" "$KUEUE_SHA256")
kwok=$(fetch "$KWOK_URL" "$KWOK_SHA256")
stages=$(fetch "$KWOK_STAGES_URL" "$KWOK_STAGES_SHA256")

log "installing Kueue $KUEUE_VERSION"
kubectl apply --server-side -f "$kueue" >/dev/null
kubectl apply --server-side --force-conflicts -f "$K1_DIR/manifests/kueue-config.yaml" >/dev/null
kubectl -n kueue-system rollout restart deploy/kueue-controller-manager >/dev/null
kubectl -n kueue-system rollout status deploy/kueue-controller-manager --timeout=180s >/dev/null

log "installing KWOK $KWOK_VERSION"
kubectl apply --server-side -f "$kwok" >/dev/null
kubectl apply --server-side -f "$stages" >/dev/null
kubectl apply --server-side --force-conflicts -f "$K1_DIR/manifests/kwok-stages.yaml" >/dev/null
kubectl -n kube-system rollout status deploy/kwok-controller --timeout=120s >/dev/null

# kindnet and kube-proxy tolerate every taint, so without this they would
# put a fake pod on every KWOK node.
for ds in kindnet kube-proxy; do
  kubectl -n kube-system patch ds "$ds" --type merge -p \
    '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"type","operator":"NotIn","values":["kwok"]}]}]}}}}}}}' >/dev/null
done

"$K1_DIR/scripts/nodes.sh"

log "applying flavors, team queues and the queue-name policy"
for f in flavors teams cluster-queues queue-policy; do
  retry 40 kubectl apply --server-side -f "$K1_DIR/manifests/$f.yaml" >/dev/null
done
log "grid is up; run 'make k1-verify'"
