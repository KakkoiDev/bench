# bench

Simple command timing + server monitoring + AI-friendly persistent logs.

https://github.com/user-attachments/assets/50bbcdeb-6e21-43a8-a898-fdbb0045ebb2

## Why bench?

**The gap:** Existing tools ([time](https://man7.org/linux/man-pages/man1/time.1.html), [hyperfine](https://github.com/sharkdp/hyperfine), [k6](https://github.com/grafana/k6), [ab](https://httpd.apache.org/docs/2.4/programs/ab.html), [wrk](https://github.com/wg/wrk)) don't track server CPU/memory during execution, and most output to stdout only.

**bench adds:**
- Server CPU/memory monitoring via `--pid` or `--port`
- Persistent, organized JSON logs you can compare across runs
- AI-friendly output for LLM analysis

**bench doesn't replace** specialized tools - wrap them to add server monitoring:

```bash
bench --port 8080 "hyperfine 'curl localhost:8080'"
bench --port 8080 "k6 run load-test.js"
```

## Installation

```bash
git clone https://github.com/KakkoiDev/bench.git
cd bench
chmod +x bench
sudo ln -s "$(pwd)/bench" /usr/local/bin/bench
```

## Usage

**Basic timing:**

```bash
bench "echo hello world"
```

**Server monitoring:**

```bash
# Start a test server
python3 -m http.server 8080 &

# Benchmark with CPU/memory tracking
bench --runs 20 --port 8080 "curl -s localhost:8080"
```

**Track optimization iterations:**

```bash
# Baseline
bench --name "api" --message "baseline" --runs 100 --port 8080 "curl -s localhost:8080/export"

# After adding cache
bench --name "api" --message "with cache" --runs 100 --port 8080 "curl -s localhost:8080/export"

# Compare
jq -r '"\(.message): \(.timing.mean)ms"' bench-results/api/*/benchmark.json
```

### Options

```
bench [OPTIONS] COMMAND

Options:
  --runs N          Number of runs (default: 10)
  --name NAME       Named group for organizing results
  --message TEXT    Describe what changed (e.g., "baseline", "with cache")
  --quiet           Suppress progress output, only print results path
  --pid PID         Monitor process CPU/memory by PID
  --port PORT       Monitor process by port (auto-resolves PID)
  --help            Show help
  --version         Show version
```

### Output

Results saved to `./bench-results/`:

```
./bench-results/
  api/                            # --name group
    20250130-143052-12345/        # timestamp-pid
      benchmark.json              # all metrics
      runs/
        1.log                     # stdout/stderr per run
        2.log
        ...
```

**benchmark.json:**

```json
{
  "schema_version": "1.0",
  "name": "api",
  "message": "baseline",
  "command": "curl -s localhost:8080",
  "timing": {
    "unit": "milliseconds",
    "mean": 23.4,
    "median": 21.0,
    "stddev": 8.7,
    "min": 12.5,
    "max": 45.2,
    "p95": 38.1,
    "p99": 44.0
  },
  "server": {
    "pid": 12345,
    "cpu": { "mean": 15.2, "min": 10.1, "max": 22.3 },
    "memory": { "initial": 45.0, "final": 47.8, "delta": 2.8, "mean": 46.2 }
  },
  "runs": [{ "run_number": 1, "duration_ms": 23.4, "exit_code": 0 }],
  "environment": { "os": "Linux", "shell": "/bin/bash" }
}
```

## With other tools

**Compare runs with [jq](https://jqlang.github.io/jq/):**

```bash
jq -r '"\(.message): \(.timing.mean)ms"' bench-results/api/*/benchmark.json
```

**Analyze with [Claude Code](https://github.com/anthropics/claude-code):**

```bash
claude -p "$(cat bench-results/api/*/benchmark.json) compare these runs, identify bottlenecks"
```

**Stress test with [xargs](https://man7.org/linux/man-pages/man1/xargs.1.html):**

```bash
bench --name "stress" --port 8080 \
  "seq 100 | xargs -P 100 -I {} curl -s localhost:8080"
```

## Contributing

```bash
# Development
./bench --runs 5 "echo test"

# Run tests (requires BATS)
bats tests/
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Philosophy

- **Composable.** Works with any command, wraps existing tools.
- **Portable.** POSIX shell, runs anywhere.
- **Persistent.** Organized logs you can revisit and compare.
- **AI-friendly.** Structured JSON for LLM analysis.

## Resources

- [Command Line Interface Guidelines](https://clig.dev)

## License

[MIT License](LICENSE)
