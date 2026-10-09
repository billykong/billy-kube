#!/usr/bin/env bash
# Unit tests for lib.sh. Run: bench/lib_test.sh
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

fails=0
eq() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
ok() {
  if "${@:2}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

eq "expand single"       "$(expand_cpus 3)"         "3"
eq "expand range"        "$(expand_cpus 0-3)"       "0 1 2 3"
eq "expand mixed"        "$(expand_cpus 0-1,4,6-7)" "0 1 4 6 7"
eq "expand empty"        "$(expand_cpus '')"        ""
eq "count mixed"         "$(cpu_count 0-1,4,6-7)"   "5"
eq "count single"        "$(cpu_count 2)"           "1"
ok "overlap in range"    cpus_overlap 0-3 3,4
ok "overlap identical"   cpus_overlap 0-1 0-1
ok "no overlap disjoint" not cpus_overlap 0-1 2-3
ok "no overlap split"    not cpus_overlap 0,2 1,3

if [ "$fails" -ne 0 ]; then
  echo "lib_test: $fails failed"
  exit 1
fi
echo "lib_test: all passed"
