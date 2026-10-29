#!/usr/bin/env bash
# Tests host-tuning.sh status and params against a fake sysfs/proc tree, so no
# root or real tuning is needed.
# Run: scripts/host-tuning_test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# fake_host <governor> <no_turbo> <deepest enabled state latency> <cmdline> <irq cpu lists...>
fake_host() {
  rm -rf "${root:?}"/*
  local c s lat
  mkdir -p "$root/cpu/intel_pstate" "$root/irq"
  echo "$2" > "$root/cpu/intel_pstate/no_turbo"
  for c in 0 1 2 3; do
    mkdir -p "$root/cpu/cpu$c/cpufreq"
    echo "$1" > "$root/cpu/cpu$c/cpufreq/scaling_governor"
    s=0
    for lat in 0 1 253 1048; do
      mkdir -p "$root/cpu/cpu$c/cpuidle/state$s"
      echo "$lat" > "$root/cpu/cpu$c/cpuidle/state$s/latency"
      if [ "$lat" -le "$3" ]; then echo 0; else echo 1; fi > "$root/cpu/cpu$c/cpuidle/state$s/disable"
      s=$((s + 1))
    done
  done
  echo "$4" > "$root/cmdline"
  shift 4
  local i=0
  for c in "$@"; do mkdir -p "$root/irq/$i"; echo "$c" > "$root/irq/$i/effective_affinity_list"; i=$((i + 1)); done
}

run() { CPU_SYS=$root/cpu CMDLINE=$root/cmdline IRQ_DIR=$root/irq HOUSEKEEPING=0 "$here/host-tuning.sh" "$@"; }

fails=0
# check <name> <want substring> <got>
check() {
  if [[ $3 == *"$2"* ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2' in '$3'"; fails=$((fails + 1)); fi
}

fake_host powersave 0 1048 "ro quiet" 0 1 0-3
check "untuned host" "host_tuning=none governor=powersave turbo=1 cstate_max_us=1048 nohz_full=none" "$(run status)"
check "IRQs reaching isolated CPUs are counted" "irqs_on_isolated=2" "$(run status)"

fake_host performance 1 1 "ro quiet" 0
check "runtime tuning only" "host_tuning=runtime governor=performance turbo=0 cstate_max_us=1" "$(run status)"

fake_host performance 1 253 "ro quiet" 0
check "a deep C-state left enabled is not runtime-tuned" "host_tuning=none" "$(run status)"

fake_host performance 1 1 "ro nohz_full=1-3 isolcpus=managed_irq,1-3 irqaffinity=0" 0 0
check "runtime and boot tuning" "host_tuning=runtime+boot" "$(run status)"
check "boot params are recorded" "nohz_full=1-3 isolcpus=managed_irq,1-3 irqaffinity=0 irqs_on_isolated=0" "$(run status)"

fake_host powersave 0 1048 "ro nohz_full=1-3" 0
check "boot tuning only" "host_tuning=boot" "$(run status)"

check "boot params isolate every non-housekeeping CPU" \
  "nohz_full=1-3 rcu_nocbs=1-3 irqaffinity=0 isolcpus=managed_irq,1-3" "$(run params)"
check "a split housekeeping set gives a split isolated list" \
  "nohz_full=1,3" "$(CPU_SYS=$root/cpu HOUSEKEEPING=0,2 "$here/host-tuning.sh" params)"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
