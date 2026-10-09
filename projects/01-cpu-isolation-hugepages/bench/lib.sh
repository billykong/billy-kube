# shellcheck shell=bash
# Helpers for Linux CPU lists ("0-2,5"), as found in Cpus_allowed_list.
# Sourced by check-tuning.sh and lib_test.sh.

# expand_cpus "0-2,5" prints "0 1 2 5".
expand_cpus() {
  local part lo hi out=()
  local IFS=,
  for part in $1; do
    if [[ $part == *-* ]]; then
      lo=${part%-*} hi=${part#*-}
      while [ "$lo" -le "$hi" ]; do out+=("$lo"); lo=$((lo + 1)); done
    elif [ -n "$part" ]; then
      out+=("$part")
    fi
  done
  IFS=' '
  echo "${out[*]}"
}

# cpu_count "0-2,5" prints 4.
cpu_count() {
  local cpus
  read -ra cpus <<< "$(expand_cpus "$1")"
  echo "${#cpus[@]}"
}

# cpus_overlap "0-3" "3,4" succeeds if the two lists share any CPU.
cpus_overlap() {
  local a b
  for a in $(expand_cpus "$1"); do
    for b in $(expand_cpus "$2"); do
      [ "$a" = "$b" ] && return 0
    done
  done
  return 1
}
