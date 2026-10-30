#!/usr/bin/env python3
"""Summarise benchmark result files into Markdown tables (PRD LAB-14).

Each result file holds "<record> key=value ..." lines: one "env" line (see
scripts/env-record.sh), optional "node"/"check"/"bench" lines, and one line
per measurement ("cyclictest ...", "memlat ..."). Runs are grouped by
environment (env_type + host + host_tuning), variant, tool and mode; each cell shows the
median across runs with the min-max spread.

Environments are never mixed in one table, and WSL2 tables are labelled
non-authoritative (NFR-15). Groups with fewer than --min-runs runs are flagged
(NFR-11).

Usage: scripts/summarise.py [--min-runs N] <results dir or file>...
"""

import argparse
import re
import statistics
import sys
from pathlib import Path

KV = re.compile(r'(\w+)=("[^"]*"|\S*)')

# tool -> (metric keys in column order, unit, function giving the mode label)
TOOLS = {
    "cyclictest": (
        ["p50_us", "p99_us", "p999_us", "max_us"],
        "µs",
        lambda kv: "SCHED_FIFO %s" % kv["rt_priority"] if kv.get("rt_priority", "0") != "0" else "SCHED_OTHER",
    ),
    "memlat": (
        ["p50_ns", "p99_ns", "p999_ns", "max_ns"],
        "ns",
        lambda kv: "%s pages, %s MiB" % ("2 MiB" if kv.get("hugepages") == "true" else "4 KiB", kv.get("size_mb", "?")),
    ),
}
VARIANT_ORDER = {"baseline": 0, "tuned": 1}


def parse_line(line):
    """Split '<record> k=v k="v w"' into (record, {k: v})."""
    record, _, rest = line.strip().partition(" ")
    return record, {k: v.strip('"') for k, v in KV.findall(rest)}


def parse_file(path):
    """Return {"env": {...}, "measurements": [(tool, {...}), ...]} for one run."""
    run = {"env": {}, "measurements": [], "file": str(path)}
    for line in Path(path).read_text().splitlines():
        record, kv = parse_line(line)
        if record == "env":
            run["env"] = kv
        elif record == "bench":
            run.setdefault("bench", kv)
        elif record in TOOLS:
            run["measurements"].append((record, kv))
    return run


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt(x):
    return "%.0f" % x if x >= 100 or x == int(x) else "%.1f" % x


def cell(values):
    """Median (min-max) of numeric values; counts overflows like '>2000'."""
    nums = [n for n in map(number, values) if n is not None]
    over = len(values) - len(nums)
    if not nums:
        return "overflow (%d/%d)" % (over, len(values))
    text = fmt(statistics.median(nums))
    if min(nums) != max(nums):
        text += " (%s-%s)" % (fmt(min(nums)), fmt(max(nums)))
    if over:
        text += " +%d overflow" % over
    return text


def group(runs):
    """{(env_type, host, host_tuning): {(variant, tool, mode): [kv, ...]}} plus env info."""
    envs, groups = {}, {}
    for run in runs:
        env = run["env"]
        # Results from before host tuning was recorded have no host_tuning key.
        env_key = (env.get("env_type", "unknown"), env.get("host", "unknown"), env.get("host_tuning", "unrecorded"))
        envs.setdefault(env_key, env)
        variant = env.get("variant") or run.get("bench", {}).get("variant", "unknown")
        for tool, kv in run["measurements"]:
            key = (variant, tool, TOOLS[tool][2](kv))
            groups.setdefault(env_key, {}).setdefault(key, []).append(kv)
    return envs, groups


def render(runs, min_runs=3):
    envs, groups = group(runs)
    out, flagged = [], False
    for env_key in sorted(groups):
        env_type, host, host_tuning = env_key
        env = envs[env_key]
        title = "### %s: %s" % (env_type, host)
        if env_type == "wsl2":
            title += " (non-authoritative: WSL2 vCPUs)"
        title += ", host tuning: %s" % host_tuning
        out.append(title)
        out.append("")
        details = ["%s=%s" % (k, env[k]) for k in ("cpu_model", "kernel", "k8s", "cni", "smt", "governor", "turbo",
                                                    "cstate_max_us", "isolcpus", "nohz_full", "isolated_cpus", "irqs_on_isolated") if k in env]
        if details:
            out.append(", ".join(details))
            out.append("")
        out.append("| Variant | Tool | Mode | Runs | p50 | p99 | p99.9 | max |")
        out.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        rows = groups[env_key]
        # 4 KiB rows before 2 MiB, baseline before tuned, so comparisons sit together
        order = lambda k: (k[1], k[2].replace("4 KiB", " "), VARIANT_ORDER.get(k[0], 9), k[0])
        for variant, tool, mode in sorted(rows, key=order):
            kvs = rows[(variant, tool, mode)]
            metrics, unit, _ = TOOLS[tool]
            runs_cell = str(len(kvs))
            if len(kvs) < min_runs:
                runs_cell += "*"
                flagged = True
            cells = [cell([kv.get(m) for kv in kvs]) + " " + unit for m in metrics]
            out.append("| %s | %s | %s | %s | %s |" % (variant, tool, mode, runs_cell, " | ".join(cells)))
        out.append("")
    if flagged:
        out.append("\\* fewer than %d runs: not enough to publish (NFR-11)." % min_runs)
        out.append("")
    return "\n".join(out)


def collect(paths):
    files = []
    for p in map(Path, paths):
        files += sorted(p.glob("*.txt")) if p.is_dir() else [p]
    return [parse_file(f) for f in files]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--min-runs", type=int, default=3)
    ap.add_argument("paths", nargs="+")
    args = ap.parse_args(argv)
    runs = [r for r in collect(args.paths) if r["measurements"]]
    if not runs:
        print("no results found in: %s" % " ".join(args.paths), file=sys.stderr)
        return 1
    for r in runs:
        if not r["env"]:
            print("warning: %s has no env record; grouped as unknown" % r["file"], file=sys.stderr)
    print(render(runs, args.min_runs), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
