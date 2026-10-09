#!/usr/bin/env bash
# Run one benchmark variant on the latency node and save its output.
# Usage: bench/run.sh baseline|tuned   (extra env, e.g. DURATION=120, is not
# forwarded; edit the Job manifest to change bench parameters)
#
# The result file holds an environment record, the tuning check and the
# benchmark output. It is only written if the check and the Job both pass
# (PRD NFR-14), so results/ never holds a run whose tuning didn't apply.
set -euo pipefail

variant=${1:?usage: run.sh baseline|tuned}
here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/../.." && pwd)
ns=latency-bench
job=bench-$variant
case $variant in
  tuned) expect=exclusive ;;
  baseline) expect=shared ;;
  *) echo "unknown variant: $variant" >&2; exit 2 ;;
esac

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
discard() {
  echo "run discarded: $1" >&2
  kubectl -n "$ns" delete job "$job" --ignore-not-found --wait=false >/dev/null
  exit 1
}

kubectl apply -f "$here/manifests/namespace.yaml" -f "$here/manifests/noise.yaml"
kubectl -n "$ns" rollout status deploy/noise --timeout=120s
kubectl -n "$ns" delete job "$job" --ignore-not-found --wait

(cd "$repo" && scripts/env-record.sh "$variant") > "$tmp"
kubectl apply -f "$here/manifests/$job.yaml"

pod=""
for _ in $(seq 60); do
  pod=$(kubectl -n "$ns" get pod -l "job-name=$job" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$pod" ] && break
  sleep 1
done
[ -n "$pod" ] || discard "no pod created for job/$job"
kubectl -n "$ns" wait --for=condition=Ready "pod/$pod" --timeout=120s || discard "pod/$pod never became ready"

"$here/bench/check-tuning.sh" "$ns" "$pod" "$expect" | tee -a "$tmp" || discard "tuning check failed (see check line above)"

# Poll rather than `kubectl wait --for=condition=complete`, which would sit out
# the whole timeout on a Job that has already failed.
status=""
for _ in $(seq 120); do
  status=$(kubectl -n "$ns" get job "$job" -o jsonpath='{.status.succeeded}/{.status.failed}')
  case $status in 1/*) break ;; */[1-9]*) break ;; esac
  sleep 5
done
if [ "${status%%/*}" != 1 ]; then
  kubectl -n "$ns" logs "job/$job" >&2 || true
  discard "job/$job did not succeed (succeeded/failed: ${status:-none})"
fi
kubectl -n "$ns" logs "job/$job" >> "$tmp"

out="$here/results/$variant-$(date -u +%Y%m%dT%H%M%SZ).txt"
cp "$tmp" "$out"
cat "$out"
echo "saved $out"
