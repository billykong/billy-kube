#!/usr/bin/env bash
# K1 milestone 1 checks on a running grid (K1-01..K1-08). Prints one
# "check=<name> result=pass|fail ..." line per check, saves the output with an
# environment record to results/verify-<UTC timestamp>.txt, and exits non-zero
# if any check fails. Deletes all Jobs in the team namespaces before and after.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"
k1_kubeconfig

TEAMS=(equities futures options)
cpu_nodes=${K1_CPU_NODES:-200}
gpu_nodes=${K1_GPU_NODES:-16}
out="$K1_DIR/results/verify-$(date -u +%Y%m%dT%H%M%SZ).txt"
failed=0

check() { # check <name> <pass|fail> [detail...]
  local name=$1 result=$2; shift 2
  [ "$result" = pass ] || failed=1
  echo "check=$name result=$result${*:+ $*}"
}
ok() { if "$@" >/dev/null 2>&1; then echo pass; else echo fail; fi; }

clean() {
  for t in "${TEAMS[@]}"; do kubectl -n "$t" delete jobs --all --wait=true >/dev/null 2>&1; done
}

# sim_job <name> <team> <pods> <cpu> <run time>: a KWOK job with whole-node pods.
sim_job() {
  kubectl apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $1
  namespace: $2
  labels: {kueue.x-k8s.io/queue-name: $2}
spec:
  parallelism: $3
  completions: $3
  template:
    metadata:
      annotations: {pod-complete.stage.kwok.x-k8s.io/delay: "$5"}
    spec:
      restartPolicy: Never
      containers:
        - name: sim
          image: sim
          resources: {requests: {cpu: "$4", memory: $(($4 * 2))Gi}}
YAML
}

wl() { # wl <team> <job> <jsonpath>: read a field of the Job's Workload
  local uid
  uid=$(kubectl -n "$1" get job "$2" -o jsonpath='{.metadata.uid}' 2>/dev/null) || return 0
  # Kueue labels a Job's Workload with the Job's UID, not its name.
  kubectl -n "$1" get workloads -l "kueue.x-k8s.io/job-uid=$uid" -o "jsonpath={.items[0]$3}" 2>/dev/null
}
admitted() { [ "$(wl "$1" "$2" '.status.conditions[?(@.type=="Admitted")].status')" = True ]; }
wait_admitted() { for _ in $(seq 30); do admitted "$1" "$2" && return 0; sleep 1; done; return 1; }
borrowed() { # borrowed <cq> <flavor> <resource>
  kubectl get clusterqueue "$1" -o \
    "jsonpath={.status.flavorsReservation[?(@.name==\"$2\")].resources[?(@.name==\"$3\")].borrowed}"
}

run() {
  "$REPO_DIR/scripts/env-record.sh" k1-m1-verify
  clean

  # K1-01: components installed and ready.
  check kueue-ready "$(ok kubectl -n kueue-system wait --for=condition=available deploy/kueue-controller-manager --timeout=60s)" \
    "image=$(kubectl -n kueue-system get deploy kueue-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}')"
  check kwok-ready "$(ok kubectl -n kube-system wait --for=condition=available deploy/kwok-controller --timeout=60s)" \
    "image=$(kubectl -n kube-system get deploy kwok-controller -o jsonpath='{.spec.template.spec.containers[0].image}')"

  # K1-02: the simulated grid has the requested size, all Ready.
  local cpu gpu
  cpu=$(kubectl get nodes -l billy-kube/node-type=cpu --no-headers | awk '$2 == "Ready"' | wc -l)
  gpu=$(kubectl get nodes -l billy-kube/node-type=gpu --no-headers | awk '$2 == "Ready"' | wc -l)
  [ "$cpu" -eq "$cpu_nodes" ] && [ "$gpu" -eq "$gpu_nodes" ] && r=pass || r=fail
  check kwok-nodes "$r" "cpu_nodes=$cpu/$cpu_nodes gpu_nodes=$gpu/$gpu_nodes"
  local fake_ds
  fake_ds=$(kubectl get pods -n kube-system -o wide --no-headers | awk '$7 ~ /^grid-/' | wc -l)
  check no-daemonsets-on-fake-nodes "$([ "$fake_ds" -eq 0 ] && echo pass || echo fail)" "pods=$fake_ds"

  # K1-04: three active ClusterQueues in one cohort, each with a LocalQueue.
  local active=0 lq=0
  for t in "${TEAMS[@]}"; do
    [ "$(kubectl get clusterqueue "$t" -o jsonpath='{.spec.cohortName}/{.status.conditions[?(@.type=="Active")].status}')" = research/True ] && active=$((active + 1))
    kubectl -n "$t" get localqueue "$t" >/dev/null 2>&1 && lq=$((lq + 1))
  done
  check queues-active "$([ "$active" -eq 3 ] && [ "$lq" -eq 3 ] && echo pass || echo fail)" "clusterqueues=$active/3 localqueues=$lq/3 cohort=research"

  # K1-06: nothing bypasses the queues; cluster-admin credentials, server-side dry run.
  local msg
  msg=$(kubectl -n equities create job no-queue --image=sim --dry-run=server -- true 2>&1)
  check policy-rejects-unqueued-job "$([[ $msg == *grid-queue-required* ]] && echo pass || echo fail)"
  msg=$(kubectl -n equities run bare-pod --image=sim --dry-run=server 2>&1)
  check policy-rejects-bare-pod "$([[ $msg == *grid-queue-required* ]] && echo pass || echo fail)"
  msg=$(kubectl -n default create job outside-grid --image=sim --dry-run=server -- true 2>&1)
  check policy-ignores-other-namespaces "$([[ $msg == *created* ]] && echo pass || echo fail)"

  # K1-03 and K1-04: a queued job per team is admitted on sim-cpu, and its
  # simulated pods finish after the run time in their annotation.
  for t in "${TEAMS[@]}"; do sim_job smoke "$t" 2 32 15s; done
  for t in "${TEAMS[@]}"; do
    if wait_admitted "$t" smoke && [ "$(wl "$t" smoke '.status.admission.podSetAssignments[0].flavors.cpu')" = sim-cpu ]; then r=pass; else r=fail; fi
    check team-job-admitted "$r" "team=$t flavor=$(wl "$t" smoke '.status.admission.podSetAssignments[0].flavors.cpu')"
  done
  if kubectl -n equities wait --for=condition=complete job/smoke --timeout=60s >/dev/null; then
    local s f secs
    s=$(kubectl -n equities get pods -l job-name=smoke -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.startedAt}')
    f=$(kubectl -n equities get pods -l job-name=smoke -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.finishedAt}')
    secs=$(( $(date -d "$f" +%s) - $(date -d "$s" +%s) ))
    check sim-run-time "$([ "$secs" -ge 14 ] && [ "$secs" -le 17 ] && echo pass || echo fail)" "want=15s got=${secs}s"
  else
    check sim-run-time fail "job did not complete"
  fi
  clean

  # K1-05: equities borrows idle quota (3200 CPU against a 2400 nominal) ...
  sim_job borrow equities 100 32 300s
  if wait_admitted equities borrow; then r=pass; else r=fail; fi
  local b
  b=$(borrowed equities sim-cpu cpu)
  check borrow-idle-quota "$([ "$r" = pass ] && [ "$b" = 800 ] && echo pass || echo fail)" "requested_cpu=3200 nominal=2400 borrowed=${b:-none}"
  # ... the cohort still has room for futures within its own quota ...
  sim_job lend futures 60 32 300s
  if wait_admitted futures lend; then r=pass; else r=fail; fi
  check owner-uses-own-quota "$r" "team=futures requested_cpu=1920 nominal=2000 borrowed=$(borrowed futures sim-cpu cpu)"
  # ... but equities can't go past its borrowing limit (2400 + 1600 = 4000).
  sim_job over-limit equities 29 32 300s
  sleep 8
  msg=$(wl equities over-limit '.status.conditions[?(@.type=="QuotaReserved")].message')
  if ! admitted equities over-limit && [[ $msg == *"insufficient unused quota for cpu in flavor sim-cpu, 128 more needed"* ]]; then r=pass; else r=fail; fi
  check borrowing-limit-holds "$r" "requested_cpu=928 would_use=4128 limit=4000"
  clean

  # GPU jobs go to the sim-gpu flavor and land on GPU nodes.
  kubectl apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu
  namespace: options
  labels: {kueue.x-k8s.io/queue-name: options}
spec:
  parallelism: 2
  completions: 2
  template:
    metadata:
      annotations: {pod-complete.stage.kwok.x-k8s.io/delay: "5s"}
    spec:
      restartPolicy: Never
      containers:
        - name: sim
          image: sim
          resources: {requests: {cpu: "16", memory: 128Gi, nvidia.com/gpu: "8"}, limits: {nvidia.com/gpu: "8"}}
YAML
  wait_admitted options gpu
  local nodes=
  for _ in $(seq 30); do # admitted first, then the Job creates and the scheduler places the pods
    nodes=$(kubectl -n options get pods -l job-name=gpu -o jsonpath='{.items[*].spec.nodeName}')
    [ "$(wc -w <<<"$nodes")" -eq 2 ] && break
    sleep 1
  done
  if [ "$(wl options gpu '.status.admission.podSetAssignments[0].flavors.nvidia\.com/gpu')" = sim-gpu ] && [[ $nodes == grid-gpu-* ]]; then r=pass; else r=fail; fi
  check gpu-job-on-gpu-flavor "$r" "nodes=${nodes// /,}"

  # K1-08: a real container runs on the kind worker through the same queue.
  kubectl apply -f - >/dev/null <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: real
  namespace: futures
  labels: {kueue.x-k8s.io/queue-name: futures}
spec:
  template:
    spec:
      restartPolicy: Never
      nodeSelector: {billy-kube/pool: grid-real}
      containers:
        - name: hello
          image: busybox:1.37
          command: [sh, -c, 'echo "ran on $(hostname)"']
          resources: {requests: {cpu: 500m, memory: 64Mi}, limits: {memory: 64Mi}}
YAML
  if kubectl -n futures wait --for=condition=complete job/real --timeout=120s >/dev/null &&
     [ "$(wl futures real '.status.admission.podSetAssignments[0].flavors.cpu')" = real ]; then r=pass; else r=fail; fi
  check real-job-on-real-flavor "$r" "node=$(kubectl -n futures get pods -l job-name=real -o jsonpath='{.items[0].spec.nodeName}')"
  clean
  echo "summary result=$([ "$failed" -eq 0 ] && echo pass || echo fail)"
  return "$failed"
}

mkdir -p "$(dirname "$out")"
run | tee "$out"
status=${PIPESTATUS[0]}
log "saved $out"
exit "$status"
