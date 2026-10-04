# Benchmark image for project 01: cyclictest (wake-up latency), memlat
# (memory/TLB latency) and stress-ng (noisy neighbour).
# Build: make bench-image  (then `make bench-load` to push it into kind)
FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY memlat/ .
RUN CGO_ENABLED=0 go build -trimpath -o /memlat .

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends rt-tests stress-ng procps \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /memlat /usr/local/bin/memlat
COPY bench.sh /usr/local/bin/bench.sh
ENTRYPOINT ["/usr/local/bin/bench.sh"]
