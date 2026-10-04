#!/usr/bin/env bash
# Reserve or release 2 MiB huge pages on the host. kind nodes share the host
# kernel, so do this before `make cluster-up-tuned`: the kubelet only reads
# huge page capacity at startup.
# Usage: scripts/hugepages.sh on [pages] | off | status
set -euo pipefail

nr=/proc/sys/vm/nr_hugepages
case ${1:-status} in
  on)  echo "${2:-512}" | sudo tee "$nr" >/dev/null ;;
  off) echo 0 | sudo tee "$nr" >/dev/null ;;
  status) ;;
  *) echo "usage: $0 on [pages] | off | status" >&2; exit 2 ;;
esac
grep -E '^(HugePages_(Total|Free)|Hugepagesize):' /proc/meminfo
