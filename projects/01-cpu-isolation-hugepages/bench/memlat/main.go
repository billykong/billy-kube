// memlat measures dependent-load memory latency with a random pointer chase
// over a buffer backed by either 4 KiB pages or 2 MiB huge pages.
//
// Each cache line in the buffer holds the index of the next line to visit, in
// a single random cycle, so every load misses the cache and (for buffers much
// larger than TLB reach) the TLB. Huge pages cut TLB misses, which shows up as
// lower ns/load. Output is one line of key=value pairs.
package main

import (
	"flag"
	"fmt"
	"math/rand"
	"os"
	"runtime"
	"slices"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const lineSize = 64 // bytes per cache line; one chase node per line

func main() {
	sizeMB := flag.Int("size-mb", 256, "buffer size in MiB")
	huge := flag.Bool("hugepages", false, "back the buffer with 2 MiB huge pages (MAP_HUGETLB)")
	batch := flag.Int("batch", 256, "loads per timed sample")
	duration := flag.Duration("duration", 10*time.Second, "how long to sample")
	seed := flag.Int64("seed", 1, "RNG seed for the chase order")
	flag.Parse()

	runtime.LockOSThread()

	buf, err := alloc(*sizeMB<<20, *huge)
	if err != nil {
		fmt.Fprintf(os.Stderr, "memlat: %v\n", err)
		os.Exit(1)
	}
	defer syscall.Munmap(buf)

	lines := buildChase(buf, *seed)
	samples := chase(lines, *batch, *duration)

	slices.Sort(samples)
	fmt.Printf("memlat hugepages=%t size_mb=%d cpus=%s samples=%d p50_ns=%.1f p99_ns=%.1f p999_ns=%.1f max_ns=%.1f\n",
		*huge, *sizeMB, cpusAllowed(), len(samples),
		pct(samples, 0.50), pct(samples, 0.99), pct(samples, 0.999), samples[len(samples)-1])
}

// alloc maps an anonymous, pre-faulted buffer. Without huge pages it opts out
// of transparent huge pages so the 4 KiB case is not silently promoted.
func alloc(size int, huge bool) ([]byte, error) {
	flags := syscall.MAP_PRIVATE | syscall.MAP_ANONYMOUS | syscall.MAP_POPULATE
	if huge {
		flags |= syscall.MAP_HUGETLB
	}
	buf, err := syscall.Mmap(-1, 0, size, syscall.PROT_READ|syscall.PROT_WRITE, flags)
	if err != nil {
		if huge {
			return nil, fmt.Errorf("mmap %d MiB with MAP_HUGETLB: %w (are enough 2 MiB huge pages reserved and requested?)", size>>20, err)
		}
		return nil, fmt.Errorf("mmap %d MiB: %w", size>>20, err)
	}
	if !huge {
		if err := syscall.Madvise(buf, 15 /* MADV_NOHUGEPAGE */); err != nil {
			return nil, fmt.Errorf("madvise(MADV_NOHUGEPAGE): %w", err)
		}
	}
	return buf, nil
}

// buildChase writes a single random cycle through every cache line (Sattolo's
// algorithm) and returns the buffer viewed as uint64 words.
func buildChase(buf []byte, seed int64) []uint64 {
	words := unsafe.Slice((*uint64)(unsafe.Pointer(&buf[0])), len(buf)/8)
	n := len(buf) / lineSize
	order := make([]uint32, n)
	for i := range order {
		order[i] = uint32(i)
	}
	r := rand.New(rand.NewSource(seed))
	for i := n - 1; i > 0; i-- {
		j := r.Intn(i)
		order[i], order[j] = order[j], order[i]
	}
	const stride = lineSize / 8
	for i := 0; i < n; i++ {
		words[int(order[i])*stride] = uint64(order[(i+1)%n]) * stride
	}
	return words
}

// chase follows the pointer chain and returns ns/load for each batch.
func chase(words []uint64, batch int, d time.Duration) []float64 {
	samples := make([]float64, 0, 1<<20)
	var idx uint64
	deadline := time.Now().Add(d)
	for {
		start := time.Now()
		for i := 0; i < batch; i++ {
			idx = words[idx]
		}
		end := time.Now()
		samples = append(samples, float64(end.Sub(start).Nanoseconds())/float64(batch))
		if end.After(deadline) {
			break
		}
	}
	sink = idx
	return samples
}

var sink uint64 // keeps the chase from being optimised away

func pct(sorted []float64, p float64) float64 {
	return sorted[int(p*float64(len(sorted)-1))]
}

func cpusAllowed() string {
	b, err := os.ReadFile("/proc/self/status")
	if err != nil {
		return "unknown"
	}
	for _, l := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(l, "Cpus_allowed_list:"); ok {
			return strings.TrimSpace(v)
		}
	}
	return "unknown"
}
