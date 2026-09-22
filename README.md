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
  --evaluate CMD      Independently validate each run (receives the run dir)
  --expect-exit CODE  Exit code the command must return, or "any" (default: 0)
  --require EXPR      Hard constraint on a metric, e.g. "errors == 0"
  --require-artifact PATH   Artifact that must exist after the run
  --capture-env VAR   Record an environment variable in provenance
  --resume DIR        Continue an interrupted benchmark
  --force-resume      Resume despite a configuration change (recorded)
  --help              Show help
  --version           Show version
```

Naming rules:

- Process names may contain letters, digits, `.`, `_` and `-` (`:` is the
  `NAME:PID` delimiter). Auto-detected names are sanitized to this set.
- `--name` must be a single directory name: no `/`, `.` or `..`, so results
  always stay inside `bench-results/`.

### Output

Results saved to `./bench-results/<name>/<timestamp>/`:

```
benchmark.json        # all metrics
runs/
  1.log               # stdout + stderr combined, per run
  1.stdout            # raw stdout
  1.stderr            # raw stderr
  1.app.metrics       # CPU/memory samples (format: "timestamp cpu:% mem:MB")
  1/                  # per-run evidence ($BENCH_RUN_DIR)
    result.json       # written by the command (optional)
    metrics.jsonl     # streamed events (optional)
    metrics.json      # normalized + validated by bench
    artifacts/        # files the run produced
    evaluator.stdout  # with --evaluate
    evaluator.stderr
    INCOMPLETE        # present only while a run is unfinished
```

All string fields in `benchmark.json` are JSON-escaped, so commands
containing quotes or backslashes still produce parseable output:

```bash
jq -r .command "$(bench --quiet 'echo "hello"')/benchmark.json"
# echo "hello"
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

## Custom measurements

Any command can report its own metrics. bench creates a directory per run and
exports it as `$BENCH_RUN_DIR`; write a result object there and bench
validates, records and aggregates it.

```bash
cat > run-agent.sh <<'EOF'
#!/bin/sh
./agent --task "$TASK" > out.txt
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"accuracy": 0.94, "tokens": 1842}, "artifacts": ["artifacts/patch.diff"]}
JSON
cp patch.diff "$BENCH_ARTIFACTS/"
EOF

bench --runs 20 ./run-agent.sh
jq '.metrics.accuracy' bench-results/*/*/benchmark.json
```

Streaming collectors can append JSON Lines to `$BENCH_METRICS` instead:

```json
{"type":"metric","name":"tokens","value":1420,"unit":"token"}
{"type":"artifact","path":"patch.diff"}
```

Metric values must be finite numbers; bad evidence marks the run
`invalid_result` with an error naming the metric, rather than silently
producing a misleading average. Raw per-run values are always kept — bench
never trims outliers.

## Independent evaluation

A command reporting its own success proves nothing. `--evaluate` runs a
separate command that receives the run directory and decides:

```bash
bench --runs 20 \
  --evaluate ./grade-result.sh \
  --require "tests_passed >= 40" \
  --require-artifact "patch.diff" \
  ./run-agent.sh
```

A run is **valid** only if the command met its exit requirement, its evidence
validated, the evaluator succeeded, every `--require` held, and every required
artifact exists. A subject declaring `"valid": true` is recorded and otherwise
ignored; declaring `"valid": false` does veto the run.

Each run reports why it is or is not valid:

```bash
jq -r '.runs[] | "\(.run_number): \(.status)"' bench-results/*/*/benchmark.json
# 1: ok
# 2: constraint_failed
# 3: evaluator_failed
```

Statuses are `ok`, `command_failed`, `invalid_result`, `declared_invalid`,
`evaluator_failed`, `constraint_failed` and `infrastructure_failed`. Note that
`runs_successful` counts exit codes while `runs_valid` counts validated runs —
they are deliberately different numbers.

Each metric is summarized twice: over every run, and over validated runs only.

```bash
jq '.metrics.tokens | {mean, valid_only}' bench-results/*/*/benchmark.json
# { "mean": 1400, "valid_only": { "count": 8, "mean": 1250 } }
```

Cost per *verified* unit of work is usually the figure that matters; `mean`
answers the different question of cost per attempt. Observations from invalid
runs are kept rather than dropped — a run that burned the resource and then
failed its checks really happened.

The full contract for commands and evaluators is in
[PROTOCOL.md](PROTOCOL.md).

## Resuming an interrupted benchmark

A long benchmark that is interrupted continues into the same result rather than
starting a second partial one:

```bash
bench --runs 500 --evaluate ./grade.sh ./run-agent.sh
# ^C after 120 runs
bench --runs 500 --evaluate ./grade.sh --resume bench-results/run-agent-sh/20260922-084500-123 ./run-agent.sh
```

Before resuming, bench checks that the configuration fingerprint still matches —
same command, run count, exit requirement, evaluator and constraints. If it does
not, the resume is refused; `--force-resume` proceeds and records the override in
the result, so a reader can see the sample is not homogeneous.

Runs already recorded are kept, **including ones that completed and were judged
invalid**: re-rolling failures until they pass would bias the sample toward
success. Only the run that was in flight when the interrupt landed — marked
`INCOMPLETE`, with no record written — is discarded and redone.

## Provenance

Every result records what produced it: configuration fingerprint, machine and
kernel, tool versions, and git commit with dirty state.

```bash
jq '.provenance | {config_fingerprint, git, machine}' bench-results/*/*/benchmark.json
```

The environment is never dumped. Only variables named with `--capture-env` are
recorded, and credential-shaped names (`KEY`, `TOKEN`, `SECRET`, `PASSWORD`,
`CREDENTIAL`, `AUTH`, `SESSION`, `COOKIE`) are refused even when explicitly
requested. The number of variables left out is recorded so the omission is
visible.

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

## Future direction

See [GENERAL-BENCHMARK-DESIGN.md](GENERAL-BENCHMARK-DESIGN.md) for the plan to extend Bench into a domain-agnostic, evidence-producing experiment runner while preserving the current simple CLI.

Phases 1 (stable evidence format) and 2 (evaluators and validity) are
implemented — see [Custom measurements](#custom-measurements) and
[Independent evaluation](#independent-evaluation). Phases 3–6 (manifests,
variants, `bench compare`, provenance and resumption) are still proposals.

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
