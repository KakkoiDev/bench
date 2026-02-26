---
name: bench
description: Run benchmarks, compare results, and analyze performance. Use when user asks to benchmark a command, compare bench runs, or analyze benchmark.json files.
---

# bench - Benchmarking Skill

Run commands with `bench`, compare results, and analyze performance.

## Commands

| Action | Command |
|--------|---------|
| Basic run | `bench "COMMAND"` |
| Named run | `bench --name NAME --message TEXT --runs N "COMMAND"` |
| With monitoring | `bench --port PORT "COMMAND"` or `bench --pid PID "COMMAND"` |
| Quiet (scripting) | `bench --quiet --runs N "COMMAND"` |
| Compare runs | `jq -r '"\(.message): mean=\(.timing.mean)ms p95=\(.timing.p95)ms"' bench-results/NAME/*/benchmark.json` |

## Workflow

### Run a benchmark

1. Ask the user for: command, number of runs, optional name/message, optional PID/port to monitor
2. Construct and execute the bench command
3. Read the resulting benchmark.json
4. Present timing summary (mean, median, p95, stddev) and process metrics if present

### Compare runs

1. List available results: `ls bench-results/`
2. Read benchmark.json from each run to compare
3. Present side-by-side table with percentage changes
4. Flag regressions (>10% slower) and improvements (>10% faster)

### Analyze existing results

1. Find benchmark.json files: `find bench-results -name benchmark.json`
2. Read and extract key metrics
3. Check for: high stddev (inconsistency), memory delta (leaks), low success rate, tail latency (p95/p99)

## Output Location

`./bench-results/<name>/<YYYYMMDD-HHMMSS-PID>/`
- `benchmark.json` - All metrics
- `runs/*.log` - Per-run stdout+stderr
- `runs/*.metrics` - Per-run process CPU/memory samples

## Examples

```bash
# Baseline measurement
bench --name "api" --message "baseline" --runs 20 --port 8080 "curl -s localhost:8080/api"

# After optimization
bench --name "api" --message "with cache" --runs 20 --port 8080 "curl -s localhost:8080/api"

# Quick comparison
jq -r '"\(.message): \(.timing.mean)ms"' bench-results/api/*/benchmark.json

# Multi-process monitoring
bench --name "stack" --pid "app:$(pgrep node)" --pid "redis:$(pgrep redis)" "curl -s localhost:3000"
```
