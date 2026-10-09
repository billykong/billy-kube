#!/usr/bin/env bash
# Tests check-tuning.sh against a stub kubectl, so no cluster is needed.
# Run: bench/check-tuning_test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT

# The stub answers the handful of calls check-tuning.sh makes. FAKE_NOISE_CPUS
# may be "a;b": the first exec of the noise pod returns a, later ones b, to
# mimic the kubelet's reconcile loop moving the noise pod.
cat > "$stub/kubectl" <<'STUB'
#!/usr/bin/env bash
args="$*"
case $args in
  *configz*) echo "{\"kubeletconfig\":{\"cpuManagerPolicy\":\"$FAKE_POLICY\",\"topologyManagerPolicy\":\"best-effort\",\"reservedSystemCPUs\":\"0\"}}" ;;
  *nodeName*) echo node1 ;;
  *limits.cpu*) echo "$FAKE_LIMIT" ;;
  *app=noise*) echo noise-0 ;;
  *"exec noise-0"*)
    n=$(cat "$FAKE_STATE" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_STATE"
    if [ "$n" -eq 0 ]; then echo "${FAKE_NOISE_CPUS%%;*}"; else echo "${FAKE_NOISE_CPUS##*;}"; fi ;;
  *exec*) echo "$FAKE_BENCH_CPUS" ;;
  *) echo "stub kubectl: unexpected call: $args" >&2; exit 1 ;;
esac
STUB
chmod +x "$stub/kubectl"

fails=0
# case <name> <want: pass|fail> <expect> <policy> <limit> <bench cpus> <noise cpus>
case_() {
  local out got
  rm -f "$stub/state"
  out=$(PATH="$stub:$PATH" FAKE_STATE="$stub/state" FAKE_POLICY=$4 FAKE_LIMIT=$5 \
    FAKE_BENCH_CPUS=$6 FAKE_NOISE_CPUS=$7 RETRIES=3 SLEEP_S=0 \
    "$here/check-tuning.sh" ns bench-0 "$3" 2>&1) && got=pass || got=fail
  if [ "$got" = "$2" ] && grep -q "result=$2" <<< "$out"; then
    echo "ok   $1"
  else
    echo "FAIL $1: want $2, got $got"; printf '     %s\n' "${out//$'\n'/$'\n'     }"; fails=$((fails + 1))
  fi
}

case_ "exclusive: pinned, disjoint"        pass exclusive static 2 2-3 0-1
case_ "exclusive: noise moved after retry" pass exclusive static 2 2-3 "0-3;0-1"
case_ "exclusive: shares with noise"       fail exclusive static 2 2-3 0-3
case_ "exclusive: wrong CPU count"         fail exclusive static 2 0-3 ''
case_ "exclusive: policy not static"       fail exclusive none   2 2-3 0-1
case_ "shared: overlaps noise"             pass shared    static '' 0-3 0-3
case_ "shared: no overlap"                 fail shared    static '' 2-3 0-1

if [ "$fails" -ne 0 ]; then
  echo "check-tuning_test: $fails failed"
  exit 1
fi
echo "check-tuning_test: all passed"
