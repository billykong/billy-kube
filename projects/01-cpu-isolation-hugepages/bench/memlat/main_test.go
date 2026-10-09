package main

import (
	"syscall"
	"testing"
)

// The chase must be one cycle through every cache line: otherwise it would
// loop over a subset that fits in cache and under-report latency.
func TestBuildChaseIsSingleCycle(t *testing.T) {
	const size = 1 << 20
	buf, err := alloc(size, false)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Munmap(buf)

	words := buildChase(buf, 42)
	n := size / lineSize
	seen := make([]bool, n)
	var idx uint64
	for i := 0; i < n; i++ {
		line := idx / (lineSize / 8)
		if seen[line] {
			t.Fatalf("line %d revisited after %d hops, want a cycle of %d", line, i, n)
		}
		seen[line] = true
		idx = words[idx]
	}
	if idx != 0 {
		t.Fatalf("after %d hops at word %d, want back at 0", n, idx)
	}
}

func TestBuildChaseDependsOnSeed(t *testing.T) {
	a, _ := alloc(1<<16, false)
	b, _ := alloc(1<<16, false)
	defer syscall.Munmap(a)
	defer syscall.Munmap(b)
	wa, wb := buildChase(a, 1), buildChase(b, 2)
	if wa[0] == wb[0] && wa[wa[0]] == wb[wb[0]] {
		t.Fatal("different seeds produced the same chase start")
	}
}

func TestPct(t *testing.T) {
	s := []float64{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	for _, c := range []struct {
		p    float64
		want float64
	}{{0, 1}, {0.5, 5}, {0.99, 9}, {1, 10}} {
		if got := pct(s, c.p); got != c.want {
			t.Errorf("pct(%v) = %v, want %v", c.p, got, c.want)
		}
	}
}

func TestChaseReturnsSamples(t *testing.T) {
	buf, err := alloc(1<<20, false)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Munmap(buf)
	samples := chase(buildChase(buf, 1), 64, 0)
	if len(samples) == 0 || samples[0] <= 0 {
		t.Fatalf("got %v, want at least one positive sample", samples)
	}
}
