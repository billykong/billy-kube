#!/usr/bin/env bash
# Check, while a bench pod is running, that the tuning it depends on applied.
# Prints "node ..." and "check ..." lines and exits 1 if the check fails, so
# the runner can discard the run instead of recording a misleading result.
#
# Usage: bench/check-tuning.sh <namespace> <bench-pod> exclusive|shared
#   exclusive: the pod has exactly its CPU limit in CPUs, none shared with the
#              noise pod (static CPU manager handed them out exclusively).
#   shared:    the pod shares CPUs with the noise pod (the baseline really is
#              noisy, so a "no difference" result means something).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

ns=$1 pod=$2 expect=$3
RETRIES=${RETRIES:-10} # the kubelet moves shared-pool pods off exclusive CPUs
SLEEP_S=${SLEEP_S:-3}  # on its reconcile loop (10s by default), so retry

# shellcheck disable=SC2016 # $2 is awk's, not ours
cpus_of() { kubectl -n "$ns" exec "$1" -- awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status; }
json_field() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" <<< "$2"; }

node=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.spec.nodeName}')
configz=$(kubectl get --raw "/api/v1/nodes/$node/proxy/configz")
policy=$(json_field cpuManagerPolicy "$configz")
echo "node name=$node cpu_manager_policy=${policy:-none}" \
  "topology_manager_policy=$(json_field topologyManagerPolicy "$configz")" \
  "reserved_cpus=$(json_field reservedSystemCPUs "$configz")"

requested=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
noise_pod=$(kubectl -n "$ns" get pod -l app=noise -o jsonpath='{.items[0].metadata.name}')

result=fail reason=""
for _ in $(seq "$RETRIES"); do
  bench_cpus=$(cpus_of "$pod")
  noise_cpus=$(cpus_of "$noise_pod")
  case $expect in
    exclusive)
      if [ "$policy" != static ]; then
        reason=cpu_manager_policy_not_static; break
      elif [ "$(cpu_count "$bench_cpus")" != "$requested" ]; then
        reason=cpu_count_not_${requested:-unset}
      elif cpus_overlap "$bench_cpus" "$noise_cpus"; then
        reason=shares_cpus_with_noise
      else
        result=pass reason=""; break
      fi ;;
    shared)
      if cpus_overlap "$bench_cpus" "$noise_cpus"; then
        result=pass reason=""; break
      fi
      reason=no_cpus_shared_with_noise ;;
    *) echo "unknown expectation: $expect" >&2; exit 2 ;;
  esac
  sleep "$SLEEP_S"
done

echo "check expect=$expect requested_cpus=${requested:-none} bench_cpus=$bench_cpus" \
  "noise_cpus=$noise_cpus result=$result${reason:+ reason=$reason}"
[ "$result" = pass ]
