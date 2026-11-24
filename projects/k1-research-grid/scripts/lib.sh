# shellcheck shell=bash
# Shared setup for K1 scripts: every kubectl call goes to the grid cluster
# only, through a kubeconfig that holds nothing else.
K1_CLUSTER=${K1_CLUSTER:-billy-kube-grid}
K1_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC2034 # used by the scripts that source this file
REPO_DIR=$(cd "$K1_DIR/../.." && pwd)
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/billy-kube

k1_kubeconfig() {
  mkdir -p "$CACHE_DIR"
  KUBECONFIG="$CACHE_DIR/kubeconfig-$K1_CLUSTER"
  kind get kubeconfig --name "$K1_CLUSTER" >"$KUBECONFIG"
  export KUBECONFIG
}

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
