# bench

Simple command timing + server monitoring + AI-friendly persistent logs.

<a href="https://asciinema.org/a/eQeiWHV3Eip4VkLDAp6SWsflt"><img src="https://asciinema.org/a/eQeiWHV3Eip4VkLDAp6SWsflt.svg" width="600"/></a>

## Why bench?

**The gap:** Existing tools ([time](https://man7.org/linux/man-pages/man1/time.1.html), [hyperfine](https://github.com/sharkdp/hyperfine), [k6](https://github.com/grafana/k6), [ab](https://httpd.apache.org/docs/2.4/programs/ab.html), [wrk](https://github.com/wg/wrk)) don't track server CPU/memory during execution, and most output to stdout only.

**bench adds:**
- Multi-process CPU/memory monitoring via `--pid` or `--port` (repeatable)
- Persistent, organized JSON logs you can compare across runs
- AI-friendly output for LLM analysis

**bench doesn't replace** specialized tools - wrap them to add server monitoring:

```bash
bench --port 8080 "hyperfine 'curl localhost:8080'"
bench --port 8080 "k6 run load-test.js"
```

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/KakkoiDev/bench/main/install.sh | sh
```

Or clone and run locally:

```bash
git clone https://github.com/KakkoiDev/bench.git
cd bench
./install.sh
```

<details>
<summary>With Claude Code integration</summary>

Installs a [Claude Code](https://github.com/anthropics/claude-code) skill and agent for running benchmarks and analyzing results.

Remote:

```bash
curl -fsSL https://raw.githubusercontent.com/KakkoiDev/bench/main/install.sh | sh -s -- --with-claude
```

Local:

```bash
./install.sh --with-claude
```

</details>

<details>
<summary>Manual installation</summary>

```bash
chmod +x bench
sudo ln -s "$(pwd)/bench" /usr/local/bin/bench
```

</details>

<details>
<summary>Install options</summary>

```
./install.sh [OPTIONS]

Options:
  --dir PATH        Install directory (default: ~/.local/bin or /usr/local/bin)
  --with-claude     Also install Claude Code skill and agent
  --skip-deps       Skip dependency checks
  --uninstall       Remove bench and optional Claude Code files
  --help            Show this help
```

</details>

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

**Scripting with --quiet:**

```bash
# --quiet suppresses progress, outputs only the results path
RESULTS=$(bench --quiet --runs 10 "curl -s localhost:8080")
jq .timing "$RESULTS/benchmark.json"

# One-liner
jq .timing "$(bench --quiet --runs 5 "echo test")/benchmark.json"
```

### Options

```
bench [OPTIONS] COMMAND

Options:
  --runs N            Number of runs (default: 10)
  --name NAME         Named group for organizing results
  --message TEXT      Describe what changed (e.g., "baseline", "with cache")
  --quiet             Suppress progress output, only print results path
  --pid [NAME:]PID    Monitor process CPU/memory by PID (repeatable)
  --port [NAME:]PORT  Monitor process by port (repeatable)
  --metrics-interval MS  Metrics sampling interval (default: 500, min: 100)
  --help              Show help
  --version           Show version
```

Note: Process names cannot contain colons (`:` is the delimiter).

### Output

Results saved to `./bench-results/<name>/<timestamp>/`:

```
benchmark.json        # all metrics
runs/
  1.log               # stdout/stderr per run
  1.app.metrics       # CPU/memory samples (format: "timestamp cpu:% mem:MB")
```

**benchmark.json:**

```json
{
  "schema_version": "2.0",
  "name": "api",
  "message": "baseline",
  "command": "curl -s localhost:8080",
  "timing": { "mean": 23.4, "median": 21.0, "min": 12.5, "max": 45.2, "p95": 38.1, "p99": 44.0 },
  "processes": [
    { "name": "app", "pid": 12345, "cpu": { "mean": 15.2 }, "memory": { "mean": 46.2, "delta": 2.8 } }
  ],
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
claude --print "$(cat bench-results/api/*/benchmark.json) compare these runs, identify bottlenecks"
```

**Stress test with [xargs](https://man7.org/linux/man-pages/man1/xargs.1.html):**

```bash
bench --name "stress" --port 8080 \
  "seq 100 | xargs -P 100 -I {} curl -s localhost:8080"
```

**Monitor [Docker Compose](https://docs.docker.com/compose/) services:**

```bash
# Get container PIDs
APP_PID=$(docker inspect --format '{{.State.Pid}}' myapp_app_1)
REDIS_PID=$(docker inspect --format '{{.State.Pid}}' myapp_redis_1)

# Benchmark with multi-process monitoring
bench --runs 20 \
  --pid "app:$APP_PID" \
  --pid "redis:$REDIS_PID" \
  "curl -s localhost:5000/api/data"
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
