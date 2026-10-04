#!/usr/bin/env bash
# Run one benchmark variant on the latency node and save its output.
# Usage: bench/run.sh baseline|tuned   (extra env, e.g. DURATION=120, is not
# forwarded; edit the Job manifest to change bench parameters)
set -euo pipefail

variant=${1:?usage: run.sh baseline|tuned}
here=$(cd "$(dirname "$0")/.." && pwd)
ns=latency-bench
job=bench-$variant

kubectl apply -f "$here/manifests/namespace.yaml" -f "$here/manifests/noise.yaml"
kubectl -n "$ns" rollout status deploy/noise --timeout=120s
kubectl -n "$ns" delete job "$job" --ignore-not-found --wait
kubectl apply -f "$here/manifests/$job.yaml"
kubectl -n "$ns" wait --for=condition=complete "job/$job" --timeout=10m

out="$here/results/$variant-$(date -u +%Y%m%dT%H%M%SZ).txt"
kubectl -n "$ns" logs "job/$job" | tee "$out"
echo "saved $out"
