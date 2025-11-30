# bench

> Minimal data logger for command benchmarking with server monitoring

**Unix Philosophy**: Do one thing well - capture structured benchmark data.

<!-- TODO: Add visual demo (asciinema/screenshot) after v1.0 implementation complete -->

## Quick Start

```bash
# Install
git clone https://github.com/KakkoiDev/bench.git
cd bench && chmod +x bench

# Basic benchmark
./bench --runs 10 "curl localhost:8080"

# With server monitoring
./bench --runs 50 --pid 12345 "curl localhost:8080"

# Compare iterations
./bench --name "api-v1" --message "baseline" --pid 12345 "curl localhost/api"
./bench --name "api-v1" --message "with Redis" --pid 12345 "curl localhost/api"
```

## Why bench?

**bench fills a unique gap in the benchmarking ecosystem** - it adds server resource monitoring and persistent organized logs to any benchmarking tool.

### What makes bench different

- **Server resource monitoring** - Track CPU/memory during benchmarks (not in [hyperfine](https://github.com/sharkdp/hyperfine), [ab](https://httpd.apache.org/docs/2.4/programs/ab.html), [wrk](https://github.com/wg/wrk))
- **Persistent organized results** - Named groups with timestamps, not one-off stdout
- **Context tracking** - `--message` flag documents what changed between runs
- **Works WITH other tools** - Wrap hyperfine/ab/wrk/k6 to ADD monitoring and logs
- **AI/LLM-ready output** - Structured JSON schema for automated analysis
- **Human-first CLI** - Follows [clig.dev](https://clig.dev) best practices

### Where bench fits

bench is a **universal command benchmarker** - it captures execution time metrics for any CLI command while optionally monitoring server resources.

#### What bench captures

- **Timing**: mean, median, stddev, min, max, p95, p99 (milliseconds)
- **Per-run data**: duration, exit code, timestamps, stdout/stderr byte counts
- **Server metrics** (with `--pid`/`--port`): CPU%, memory MB, leak detection

#### AI/LLM-friendly output

bench outputs structured JSON designed for automated analysis:

```json
{
  "schema_version": "1.0",
  "timing": { "mean": 67.70, "p95": 81.00, "stddev": 16.22, ... },
  "runs": [
    { "run_number": 1, "duration_ms": 72.47, "exit_code": 0, ... },
    ...
  ],
  "server": { "memory": { "initial": 45.2, "final": 47.8, "delta": 2.6 }, ... }
}
```

Feed directly to Claude, GPT, or scripts for trend analysis, anomaly detection, or optimization suggestions.

#### Use cases

| Scenario | Without bench | With bench |
|----------|---------------|------------|
| "How fast is this command?" | `time` gives one sample | Stats across N runs + JSON |
| "Is my server leaking memory?" | Watch htop manually | `--pid` tracks delta automatically |
| "Compare before/after optimization" | Copy/paste somewhere | Named groups organize experiments |
| "Analyze with AI" | Screenshot terminal | Structured JSON, paste and ask |

#### Works with any command

```bash
# Build tools
bench --runs 5 "make clean && make"

# Database queries
bench --runs 20 "psql -c 'SELECT count(*) FROM users'"

# File operations
bench --runs 50 "find . -name '*.log' | wc -l"

# Scripts
bench --runs 10 "python process_data.py"

# With server monitoring
bench --runs 30 --pid $SERVER_PID "curl -s localhost:8080/api"
```

#### Complements specialized tools

| Tool | What it does | What bench adds |
|------|--------------|-----------------|
| [hyperfine](https://github.com/sharkdp/hyperfine) | Statistical CLI comparison | Server monitoring + persistent logs |
| [ab](https://httpd.apache.org/docs/2.4/programs/ab.html) / [wrk](https://github.com/wg/wrk) | HTTP load generation | CPU/memory tracking during load |
| [k6](https://github.com/grafana/k6) | Scriptable load testing | Server-side metrics + organized logs |
| [time](https://man7.org/linux/man-pages/man1/time.1.html) | Single command timing | N runs + statistics + JSON |

## Installation

```bash
# Clone repository
git clone https://github.com/KakkoiDev/bench.git
cd bench

# Make executable
chmod +x bench

# Optional: Add to PATH
sudo ln -s "$(pwd)/bench" /usr/local/bin/bench
```

### Requirements

**Core dependencies** (required):
- **Perl 5.8+** with Time::HiRes module (usually pre-installed)
- **bc** command for floating-point calculations

**Server monitoring** (optional, only if using --pid or --port):
- **top** command for process monitoring
- **lsof** or **ss** for port-to-PID resolution

```bash
# Debian/Ubuntu
sudo apt-get install perl bc procps lsof

# RHEL/Fedora
sudo dnf install perl bc procps-ng lsof

# macOS
brew install perl bc
# top and lsof pre-installed on macOS
```

## Usage

```
bench [OPTIONS] COMMAND

Options:
  --runs N          Number of runs (default: 10)
  --name NAME       Named group (optional, auto-generated from command if omitted)
  --message TEXT    Message describing this run (optional)
  --quiet           No progress output

  --pid PID         Monitor process by PID
  --port PORT       Monitor process by port

  --help            Show help
  --version         Show version
```

### Exit Codes

- **0**: Success (even with partial results or failed runs)
- **1**: Pre-flight validation failed (missing deps, disk full, invalid input)
- **130**: User interruption (SIGINT/Ctrl+C)

## Output

**Directory structure**:
```
./bench-results/
  api-v1/                       # Named group
    20250123-143052-12345/      # Timestamp-PID
      benchmark.json            # All metrics (machine-readable)
      runs/                     # Individual run outputs
        1.log
        2.log
        ...
```

**benchmark.json** contains:
- Timing metrics: mean, median, stddev, min, max, p95, p99 (milliseconds)
- Success/failure tracking: runs_total, runs_successful, runs_failed, success_rate
- Server metrics (if --pid/--port): CPU (percent), memory (megabytes)
- Per-run data: exit codes, timestamps, timing breakdown, output sizes
- Environment metadata: os, shell, pwd, git commit
- Interruption tracking: partial results if Ctrl+C

**stdout** outputs absolute path to results directory for piping:
```bash
RESULTS=$(bench --quiet --runs 10 "echo test")
cat "$RESULTS/benchmark.json" | jq .benchmark.timing.mean
```

## Examples

### Analysis with jq

```bash
# Quick summary
jq -r '"Mean: \(.benchmark.timing.mean)ms"' benchmark.json

# Compare multiple runs
jq -r '"\(.benchmark.message): \(.benchmark.timing.mean)ms"' \
  bench-results/api-v1/*/benchmark.json

# Server CPU usage
jq -r '"\(.benchmark.message): \(.benchmark.server.cpu.mean)%"' \
  bench-results/api-v1/*/benchmark.json
```

### Analysis with LLM

```bash
# Analyze performance trends
cat bench-results/api-v1/*/benchmark.json | llm \
  "Compare all runs. How did performance improve?"

# Memory leak detection
cat benchmark.json | llm \
  "Analyze memory delta. Is there a leak?"
```

### Iterative optimization

```bash
# Baseline
bench --name "api-v1" --message "baseline" --pid 12345 "curl localhost/api"

# After Redis caching
bench --name "api-v1" --message "Redis caching" --pid 12345 "curl localhost/api"

# After query optimization
bench --name "api-v1" --message "optimized queries" --pid 12345 "curl localhost/api"

# Compare all iterations
jq -r '"\(.benchmark.message): \(.benchmark.timing.mean)ms (CPU: \(.benchmark.server.cpu.mean)%)"' \
  bench-results/api-v1/*/benchmark.json
```

### Using bench WITH other tools

**With [hyperfine](https://github.com/sharkdp/hyperfine)** (statistical command comparison):
```bash
# hyperfine provides statistical rigor, bench adds server monitoring
bench --name "query-perf" --message "baseline" --pid 12345 \
  "hyperfine --warmup 3 'psql -c \"SELECT * FROM users\"'"

# Get hyperfine's detailed stats (in run logs) + server CPU/memory tracking
```

**With [ab](https://httpd.apache.org/docs/2.4/programs/ab.html)/[wrk](https://github.com/wg/wrk)** (HTTP load testing):
```bash
# ab provides HTTP-specific metrics, bench adds server resource tracking
bench --name "load-test" --message "100 concurrent" --pid 12345 \
  "ab -n 1000 -c 100 http://localhost/api"

# Get ab's throughput/latency metrics + server CPU/memory under load
```

**With [k6](https://github.com/grafana/k6)** (complex load testing):
```bash
# k6 handles complex scenarios, bench tracks server resources over time
bench --name "checkout-flow" --message "v1.0" --pid 12345 \
  "k6 run --quiet checkout.js"

# k6's detailed metrics (in logs) + server resource consumption tracked
```

**Standalone** (general commands):
```bash
# For any command where you need timing + server metrics
bench --name "data-pipeline" --message "1000 records" --pid 12345 \
  "./process_data.sh --batch-size 1000"

# 100 concurrent requests with xargs
bench --name "stress-test" --pid 12345 \
  "seq 100 | xargs -P 100 -I {} curl -s localhost"
```

## Features

### Auto-naming

If --name not provided, generates from command:
- `curl localhost:8080/api` → `curl-localhost-8080-api`
- `echo "hello world"` → `echo-hello-world`

### Server monitoring

Track CPU and memory of your application during benchmark:
```bash
# Start server
python3 -m http.server 8080 & SERVER_PID=$!

# Benchmark with monitoring
bench --pid $SERVER_PID --runs 20 "curl localhost:8080"

# Results include server.cpu and server.memory metrics
```

### Interruption handling

Press Ctrl+C to save partial results:
- Saves completed runs immediately
- JSON includes `interrupted: true` and `interrupted_at_run`
- Exit code 130 (standard SIGINT)

### Failure tracking

Continues all runs even if command fails:
- Tracks success/failure counts
- Per-run exit codes in JSON
- Useful for testing flaky services

## Design Philosophy

**POSIX shell syntax**: Written in POSIX sh (dash-compatible), not bash-specific. Portable shell code across Linux, macOS, BSD.

**Unix tools required**: Depends on common Unix utilities (`perl`, `bc`, `top`) that aren't strictly POSIX but are universally available. The script is POSIX-compliant, the runtime requires Unix tools.

**Long-only flags**: No short flags (--runs, not -r) to avoid namespace conflicts and improve clarity.

**JSON-only output**: No summary.txt. Use jq/llm/scripts for human-readable formatting.

**Millisecond precision**: Uses Perl Time::HiRes (portable) or date +%s.%N (modern systems).

**Timestamp-PID directories**: Prevents collisions when running concurrent benchmarks.

## Development

### Running Tests

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
# Install BATS (if not already installed)
git clone https://github.com/bats-core/bats-core.git
sudo ./bats-core/install.sh /usr/local

# Run all tests
bats tests/

# Run specific test file
bats tests/01-foundation.bats

# Run with verbose output
bats -t tests/
```

### Development Dependencies

```bash
# Debian/Ubuntu
sudo apt-get install shellcheck dash

# Validate POSIX compliance
shellcheck -s sh bench
dash -n bench
```

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Links

- **GitHub**: https://github.com/KakkoiDev/bench
- **Issues**: https://github.com/KakkoiDev/bench/issues
- **CLI Design**: [clig.dev](https://clig.dev) - Command Line Interface Guidelines
