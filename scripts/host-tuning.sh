#!/usr/bin/env bash
# Host tuning for P01 milestone 4, in two stages that can be measured apart:
#
#   runtime  performance governor, turbo off, C-states deeper than
#            MAX_CSTATE_US disabled on every CPU. Lasts until reboot.
#   boot     nohz_full, rcu_nocbs, irqaffinity and isolcpus=managed_irq on the
#            kernel command line, via a GRUB drop-in. Needs a reboot.
#
# HOUSEKEEPING must match the kubelet's reserved CPUs in
# cluster/kind/isolated-cpu.yaml; every other CPU is isolated.
#
# Usage (apply-* and revert-* need root):
#   scripts/host-tuning.sh status          one "host_tuning=..." key=value line
#   scripts/host-tuning.sh apply-runtime | revert-runtime
#   scripts/host-tuning.sh apply-boot | revert-boot   (then reboot)
set -euo pipefail

HOUSEKEEPING=${HOUSEKEEPING:-0,4}
MAX_CSTATE_US=${MAX_CSTATE_US:-1}
# Overridable so the test can point them at a fake tree.
CPU_SYS=${CPU_SYS:-/sys/devices/system/cpu}
CMDLINE=${CMDLINE:-/proc/cmdline}
IRQ_DIR=${IRQ_DIR:-/proc/irq}
GRUB_DROPIN=${GRUB_DROPIN:-/etc/default/grub.d/90-billy-kube-isolation.cfg}
SAVED=${SAVED:-/run/billy-kube-host-tuning.saved}

cpus() { printf '%s\n' "$CPU_SYS"/cpu[0-9]* | sort -V; }

# Expand a CPU list like "0,2-3" to "0 2 3".
expand() {
  local part n out=()
  IFS=, read -ra parts <<< "$1"
  for part in "${parts[@]}"; do
    if [[ $part == *-* ]]; then
      for n in $(seq "${part%-*}" "${part#*-}"); do out+=("$n"); done
    else
      out+=("$part")
    fi
  done
  echo "${out[@]}"
}

# The isolated set: every online CPU not in HOUSEKEEPING, as a list like "1-3,5-7".
isolated() {
  local hk c n out=() start="" prev=""
  hk=" $(expand "$HOUSEKEEPING") "
  for c in $(cpus); do
    n=${c##*cpu}
    [[ $hk == *" $n "* ]] && continue
    if [ -n "$prev" ] && [ "$n" -eq $((prev + 1)) ]; then prev=$n; continue; fi
    [ -n "$start" ] && out+=("$start$([ "$prev" != "$start" ] && echo "-$prev")")
    start=$n; prev=$n
  done
  [ -n "$start" ] && out+=("$start$([ "$prev" != "$start" ] && echo "-$prev")")
  local IFS=,; echo "${out[*]}"
}

boot_params() {
  local iso; iso=$(isolated)
  echo "nohz_full=$iso rcu_nocbs=$iso irqaffinity=$HOUSEKEEPING isolcpus=managed_irq,$iso"
}

param() { local v; v=$(grep -o "\b$1=[^ ]*" "$CMDLINE" | head -n1 | cut -d= -f2-) || true; echo "${v:-none}"; }

status() {
  local governors turbo deepest=0 s lat runtime=1 boot=0 label irqs=0 iso f
  governors=$(cat "$CPU_SYS"/cpu[0-9]*/cpufreq/scaling_governor 2>/dev/null | sort -u | paste -sd/)
  if [ -r "$CPU_SYS/intel_pstate/no_turbo" ]; then turbo=$((1 - $(cat "$CPU_SYS/intel_pstate/no_turbo"))); else turbo=unknown; fi
  # Deepest exit latency still enabled on any CPU.
  for s in "$CPU_SYS"/cpu[0-9]*/cpuidle/state*; do
    [ "$(cat "$s/disable")" = 0 ] || continue
    lat=$(cat "$s/latency"); [ "$lat" -gt "$deepest" ] && deepest=$lat
  done
  [ "$governors" = performance ] && [ "$turbo" = 0 ] && [ "$deepest" -le "$MAX_CSTATE_US" ] || runtime=0
  [ "$(param nohz_full)" != none ] && boot=1
  case $runtime$boot in 00) label=none ;; 10) label=runtime ;; 01) label=boot ;; 11) label="runtime+boot" ;; esac
  # IRQs whose effective affinity reaches an isolated CPU.
  iso=" $(expand "$(isolated)") "
  for f in "$IRQ_DIR"/*/effective_affinity_list; do
    [ -r "$f" ] || continue
    for c in $(expand "$(cat "$f")"); do [[ $iso == *" $c "* ]] && { irqs=$((irqs + 1)); break; }; done
  done
  echo "host_tuning=$label governor=$governors turbo=$turbo cstate_max_us=$deepest" \
    "nohz_full=$(param nohz_full) isolcpus=$(param isolcpus) irqaffinity=$(param irqaffinity) irqs_on_isolated=$irqs"
}

need_root() { [ "$(id -u)" = 0 ] || { echo "$1 needs root: sudo $0 $1" >&2; exit 1; }; }

apply_runtime() {
  local c s
  # Save what we change, once, so revert restores this host's own defaults.
  [ -e "$SAVED" ] || {
    echo "governor=$(cat "$CPU_SYS/cpu0/cpufreq/scaling_governor")"
    echo "no_turbo=$(cat "$CPU_SYS/intel_pstate/no_turbo" 2>/dev/null || echo 0)"
  } > "$SAVED"
  for c in $(cpus); do
    echo performance > "$c/cpufreq/scaling_governor"
    for s in "$c"/cpuidle/state*; do
      [ "$(cat "$s/latency")" -gt "$MAX_CSTATE_US" ] && echo 1 > "$s/disable"
    done
  done
  [ -w "$CPU_SYS/intel_pstate/no_turbo" ] && echo 1 > "$CPU_SYS/intel_pstate/no_turbo"
  status
}

revert_runtime() {
  local c s governor=powersave no_turbo=0
  # shellcheck disable=SC1090 # written by apply_runtime
  [ -r "$SAVED" ] && . "$SAVED"
  for c in $(cpus); do
    echo "$governor" > "$c/cpufreq/scaling_governor"
    for s in "$c"/cpuidle/state*; do echo 0 > "$s/disable"; done
  done
  [ -w "$CPU_SYS/intel_pstate/no_turbo" ] && echo "$no_turbo" > "$CPU_SYS/intel_pstate/no_turbo"
  rm -f "$SAVED"
  status
}

apply_boot() {
  cat > "$GRUB_DROPIN" <<EOF
# Written by billy-kube scripts/host-tuning.sh apply-boot; remove with revert-boot.
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT $(boot_params)"
EOF
  update-grub
  echo "added to the kernel command line: $(boot_params)"
  echo "reboot to apply; after the reboot, reserve huge pages again (make hugepages-on) and re-run apply-runtime"
}

revert_boot() {
  rm -f "$GRUB_DROPIN"
  update-grub
  echo "removed $GRUB_DROPIN; reboot to apply"
}

case ${1:-status} in
  status) status ;;
  params) boot_params ;;
  apply-runtime) need_root "$1"; apply_runtime ;;
  revert-runtime) need_root "$1"; revert_runtime ;;
  apply-boot) need_root "$1"; apply_boot ;;
  revert-boot) need_root "$1"; revert_boot ;;
  *) echo "usage: $0 status | params | apply-runtime | revert-runtime | apply-boot | revert-boot" >&2; exit 2 ;;
esac
