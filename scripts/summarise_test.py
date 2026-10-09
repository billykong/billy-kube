"""Unit tests for summarise.py. Run: python3 scripts/summarise_test.py"""

import tempfile
import unittest
from pathlib import Path

import summarise

ENV_BM = 'env date_utc=2026-10-09T00:00:00Z variant=%s host=lab env_type=bare-metal kernel=6.8 cpu_model="Intel(R) Core(TM) i7" k8s=v1.31.0 cni=kindnet'
ENV_WSL = 'env variant=%s host=desk env_type=wsl2 kernel=5.15'


def run(env, variant, cyc_p99, mem4k_p50, mem2m_p50=None):
    lines = [env % variant,
             "check expect=exclusive result=pass",
             "bench variant=%s node=w2 cpus=2-3 pinned_cpu=2" % variant,
             "cyclictest rt_priority=0 samples=100 p50_us=10 p99_us=%s p999_us=40 max_us=90 overflows=0" % cyc_p99,
             "memlat hugepages=false size_mb=256 cpus=2-3 samples=9 p50_ns=%s p99_ns=300 p999_ns=500 max_ns=900" % mem4k_p50]
    if mem2m_p50 is not None:
        lines.append("memlat hugepages=true size_mb=256 cpus=2-3 samples=9 p50_ns=%s p99_ns=250 p999_ns=400 max_ns=800" % mem2m_p50)
    return "\n".join(lines) + "\n"


class ParseTest(unittest.TestCase):
    def test_quoted_values(self):
        record, kv = summarise.parse_line('env host=a cpu_model="Intel(R) Core i7" cpus=8')
        self.assertEqual(record, "env")
        self.assertEqual(kv, {"host": "a", "cpu_model": "Intel(R) Core i7", "cpus": "8"})

    def test_cell_median_and_spread(self):
        self.assertEqual(summarise.cell(["30", "10", "20"]), "20 (10-30)")
        self.assertEqual(summarise.cell(["12.34"]), "12.3")
        self.assertEqual(summarise.cell(["165.6", "170.2"]), "168 (166-170)")

    def test_cell_overflow(self):
        self.assertEqual(summarise.cell(["10", ">2000"]), "10 +1 overflow")
        self.assertEqual(summarise.cell([">2000"]), "overflow (1/1)")


class RenderTest(unittest.TestCase):
    def write(self, files):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        for name, text in files.items():
            Path(d.name, name).write_text(text)
        return summarise.collect([d.name])

    def test_groups_and_medians(self):
        runs = self.write({
            "baseline-1.txt": run(ENV_BM, "baseline", 80, 160),
            "baseline-2.txt": run(ENV_BM, "baseline", 100, 170),
            "baseline-3.txt": run(ENV_BM, "baseline", 90, 165),
            "tuned-1.txt": run(ENV_BM, "tuned", 30, 150, 110),
        })
        out = summarise.render(runs)
        self.assertIn("### bare-metal: lab", out)
        self.assertIn("| baseline | cyclictest | SCHED_OTHER | 3 | 10 µs | 90 (80-100) µs |", out)
        self.assertIn("| tuned | memlat | 2 MiB pages, 256 MiB | 1* | 110 ns |", out)
        self.assertIn("fewer than 3 runs", out)
        # baseline rows come before tuned rows for the same tool and mode
        self.assertLess(out.index("| baseline | cyclictest"), out.index("| tuned | cyclictest"))

    def test_environments_never_mixed(self):
        runs = self.write({
            "a.txt": run(ENV_BM, "tuned", 30, 150),
            "b.txt": run(ENV_WSL, "tuned", 300, 400),
        })
        out = summarise.render(runs)
        self.assertIn("### wsl2: desk (non-authoritative", out)
        bm, wsl = out.split("### wsl2")
        self.assertIn("| tuned | cyclictest | SCHED_OTHER | 1* | 10 µs | 30 µs |", bm)
        self.assertIn("| tuned | cyclictest | SCHED_OTHER | 1* | 10 µs | 300 µs |", wsl)

    def test_no_flag_when_enough_runs(self):
        runs = self.write({"r%d.txt" % i: run(ENV_BM, "tuned", 30, 150) for i in range(3)})
        self.assertNotIn("fewer than", summarise.render(runs))

    def test_main_fails_without_results(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(summarise.main([d]), 1)


if __name__ == "__main__":
    unittest.main()
