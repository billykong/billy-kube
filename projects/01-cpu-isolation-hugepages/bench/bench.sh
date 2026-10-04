#!/usr/bin/env bash
# Runs inside the bench pod: cyclictest on one allowed CPU, then memlat with
# 4 KiB pages and (if HUGEPAGES=1) with 2 MiB huge pages. Prints one
# key=value summary line per measurement.
set -euo pipefail

VARIANT=${VARIANT:-unknown}
DURATION=${DURATION:-60}        # seconds of cyclictest
INTERVAL_US=${INTERVAL_US:-200} # cyclictest wake-up interval
RT_PRIORITY=${RT_PRIORITY:-0}   # >0 runs SCHED_FIFO (needs CAP_SYS_NICE)
HIST_MAX_US=${HIST_MAX_US:-2000}
MEMLAT_MB=${MEMLAT_MB:-256}
MEMLAT_DURATION=${MEMLAT_DURATION:-10s}
HUGEPAGES=${HUGEPAGES:-0}

cpus=$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status)
cpu=${cpus%%[,-]*}
echo "bench variant=${VARIANT} node=${NODE_NAME:-unknown} cpus=${cpus} pinned_cpu=${cpu}"

prio=()
if [ "$RT_PRIORITY" -gt 0 ]; then
  prio=(--priority="$RT_PRIORITY" --policy=fifo)
fi

cyclictest --mlockall --quiet --duration="${DURATION}s" --interval="$INTERVAL_US" \
  --threads=1 --affinity="$cpu" "${prio[@]}" --histogram="$HIST_MAX_US" > /tmp/cyclictest.txt

# Histogram lines are "<bucket_us> <count>"; overflows are samples > HIST_MAX_US.
awk -v rt="$RT_PRIORITY" '
  /^[0-9]/ { n++; b[n] = $1 + 0; c[n] = $2 + 0; total += $2 }
  /^# Max Latencies:/ { max = $4 + 0 }
  /^# Histogram Overflows:/ { ovf = $4 + 0; total += ovf }
  function pct(p,   t, i, acc) {
    t = p * total
    for (i = 1; i <= n; i++) { acc += c[i]; if (acc >= t) return b[i] }
    return ">" b[n]
  }
  END {
    printf "cyclictest rt_priority=%d samples=%d p50_us=%s p99_us=%s p999_us=%s max_us=%d overflows=%d\n",
      rt, total, pct(0.5), pct(0.99), pct(0.999), max, ovf
  }' /tmp/cyclictest.txt

memlat -size-mb "$MEMLAT_MB" -duration "$MEMLAT_DURATION"
if [ "$HUGEPAGES" = 1 ]; then
  memlat -size-mb "$MEMLAT_MB" -duration "$MEMLAT_DURATION" -hugepages
fi
