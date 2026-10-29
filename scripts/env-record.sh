#!/usr/bin/env bash
# Print one "env ..." line describing where a benchmark ran (PRD NFR-10).
# Values containing spaces are double-quoted. Fields that can't be read are
# "unknown" rather than missing, so every result has the same keys.
# Usage: scripts/env-record.sh <variant>
set -uo pipefail

variant=${1:-unknown}
q() { if [[ $1 == *' '* ]]; then printf '"%s"' "${1//\"/}"; else printf '%s' "${1:-unknown}"; fi; }
first() { local v; v=$("$@" 2>/dev/null | head -n1) && [ -n "$v" ] && echo "$v" || echo unknown; }

if grep -qi microsoft /proc/version 2>/dev/null; then env_type=wsl2; else env_type=bare-metal; fi
cpu_model=$(first sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo)
smt=$(first cat /sys/devices/system/cpu/smt/active)
governor=$(first cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
if [ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
  turbo=$(( 1 - $(cat /sys/devices/system/cpu/intel_pstate/no_turbo) ))
else
  turbo=$(first cat /sys/devices/system/cpu/cpufreq/boost)
fi
# shellcheck disable=SC2016 # $2 is awk's, not ours
hugepages=$(first awk '/^HugePages_Total:/ {print $2}' /proc/meminfo)
commit=$(first git rev-parse --short HEAD)
# Saved results are untracked output, not code changes, so they do not count.
if [ -n "$(git status --porcelain -- . ':(exclude,glob)projects/*/results/**' 2>/dev/null)" ]; then dirty=1; else dirty=0; fi
# host_tuning, cstate_max_us, boot isolation params and IRQ placement; governor
# and turbo are already recorded above.
host_tuning=$(first sh -c "'$(dirname "$0")/host-tuning.sh' status | sed 's/ governor=[^ ]*//; s/ turbo=[^ ]*//'")
kind_version=$(first sh -c "kind version | awk '{print \$2}'")
context=$(first kubectl config current-context)
k8s=$(first kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')
node_kernel=$(first kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}')
daemonsets=$(kubectl -n kube-system get ds -o name 2>/dev/null)
case $daemonsets in
  *cilium*) cni=cilium ;;
  *kindnet*) cni=kindnet ;;
  *calico*) cni=calico ;;
  *) cni=unknown ;;
esac

echo "env date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) variant=$variant git_commit=$commit git_dirty=$dirty" \
  "host=$(q "$(hostname)") env_type=$env_type kernel=$(uname -r) node_kernel=$(q "$node_kernel")" \
  "cpu_model=$(q "$cpu_model") cpus=$(nproc) smt=$smt governor=$governor turbo=$turbo" \
  "host_hugepages_2m=$hugepages kind=$kind_version context=$(q "$context") k8s=$k8s cni=$cni" \
  "$host_tuning"
