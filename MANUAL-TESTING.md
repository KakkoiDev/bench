# Manual Testing Guide

Comprehensive manual testing reference for the bench CLI tool.

## Quick Reference

```bash
bench [OPTIONS] COMMAND

Options:
  --runs N               Number of runs (default: 10)
  --name NAME            Named group for results
  --message TEXT         Describe what changed
  --quiet                Output only results path
  --pid [NAME:]PID       Monitor process by PID (repeatable)
  --port [NAME:]PORT     Monitor process by port (repeatable)
  --metrics-interval MS  Sampling interval (default: 500, min: 100)
  --help                 Show help
  --version              Show version
```

---

## 1. Basic Timing

```bash
# Simple timing
bench --runs 3 "echo hello"

# Verify output
cat bench-results/echo-hello/*/benchmark.json | jq '.timing'
```

**Expected:** timing.mean, timing.median, timing.min, timing.max present

---

## 2. Options Validation

```bash
# Valid runs
bench --runs 1 "echo test"
bench --runs 100 "echo test"

# Invalid runs (should error)
bench --runs 0 "echo test"      # Error: must be positive
bench --runs -5 "echo test"     # Error: must be positive
bench --runs abc "echo test"    # Error: must be numeric

# Name and message
bench --runs 1 --name "api-test" --message "baseline" "echo test"

# Quiet mode (for scripting)
RESULTS=$(bench --quiet --runs 3 "echo test")
echo "Results at: $RESULTS"
jq '.timing.mean' "$RESULTS/benchmark.json"
```

---

## 3. Process Monitoring (Single Process)

```bash
# Start a test server
python3 -m http.server 8080 &
server_pid=$!
sleep 1

# Monitor by port
bench --runs 5 --port 8080 "curl -s localhost:8080"

# Monitor by PID
bench --runs 5 --pid "$server_pid" "curl -s localhost:8080"

# Monitor with custom name
bench --runs 5 --pid "api:$server_pid" "curl -s localhost:8080"

# Verify metrics in JSON
jq '.processes[0]' bench-results/*/*/benchmark.json

# Cleanup
kill $server_pid
```

**Expected:** processes array with cpu.mean, memory.mean, memory.delta

---

## 4. Continuous Metrics Sampling

```bash
# Start a long-running process
sleep 300 &
pid=$!

# Default 500ms interval
bench --runs 1 --pid "app:$pid" "sleep 2"
cat bench-results/*/*/runs/*.app.metrics
# Expected: ~5 samples (start + 3 loop + end)

# Faster 200ms interval
bench --runs 1 --metrics-interval 200 --pid "app:$pid" "sleep 2"
wc -l bench-results/*/*/runs/*.app.metrics
# Expected: ~12 samples

# Minimum interval validation
bench --metrics-interval 50 "echo test"
# Expected: Error "minimum is 100ms"

kill $pid
```

**Metrics file format:**
```
2025-12-14T19:28:30 cpu:0.0 mem:2.15    # START (real timestamp)
+500ms cpu:0.0 mem:2.15                  # Loop samples (relative)
+1000ms cpu:0.0 mem:2.15
2025-12-14T19:28:33 cpu:0.0 mem:2.15    # END (real timestamp)
```

---

## 5. Multi-Process Monitoring

```bash
# Start two processes
sleep 300 &
pid1=$!
sleep 300 &
pid2=$!

# Monitor both
bench --runs 2 --pid "app:$pid1" --pid "worker:$pid2" "sleep 0.5"

# Verify both in JSON
jq '.processes | length' bench-results/*/*/benchmark.json
# Expected: 2

jq '.processes[].name' bench-results/*/*/benchmark.json
# Expected: "app", "worker"

# Verify per-run metrics
jq '.runs[0].processes' bench-results/*/*/benchmark.json

# Check metrics files
ls bench-results/*/*/runs/*.metrics
# Expected: 1.app.metrics, 1.worker.metrics, 2.app.metrics, 2.worker.metrics

kill $pid1 $pid2
```

---

## 6. CPU-Intensive Process

```bash
# Start CPU-heavy process
yes > /dev/null &
pid=$!

# Monitor it
bench --runs 2 --pid "cpu:$pid" "sleep 1"

# Verify high CPU values
cat bench-results/*/*/runs/*.cpu.metrics
# Expected: cpu:90+ values

jq '.processes[0].cpu.mean' bench-results/*/*/benchmark.json
# Expected: ~100

kill $pid
```

---

## 7. Signal Handling (SIGINT)

```bash
# Start long benchmark
bench --runs 100 "sleep 0.5" &
bench_pid=$!
sleep 2

# Send SIGINT
kill -INT $bench_pid

# Check results
jq '.interrupted, .runs_completed' bench-results/*/*/benchmark.json
# Expected: true, <100
```

---

## 8. Process Death During Benchmark

```bash
# Start short-lived process
sleep 2 &
pid=$!

# Benchmark longer than process lifetime
bench --runs 10 --pid "$pid" "sleep 0.5"
# Expected: Completes without error, partial metrics collected
```

---

## 9. Docker Container Monitoring

```bash
# Start a container
docker run -d --name test-nginx -p 8080:80 nginx
sleep 2

# Get container PID
APP_PID=$(docker inspect --format '{{.State.Pid}}' test-nginx)
echo "Container PID: $APP_PID"

# Benchmark with monitoring (may need sudo for PID access)
sudo bench --runs 10 --pid "nginx:$APP_PID" "curl -s localhost:8080"

# Verify
sudo cat bench-results/*/*/runs/*.nginx.metrics
jq '.processes[0]' bench-results/*/*/benchmark.json

# Cleanup
docker stop test-nginx && docker rm test-nginx
```

---

## 10. Docker Compose Multi-Service

```bash
# Example docker-compose.yml:
# services:
#   app:
#     image: python:3.9
#     command: python -m http.server 5000
#     ports: ["5000:5000"]
#   redis:
#     image: redis:alpine
#     ports: ["6379:6379"]

# Start services
docker compose up -d
sleep 3

# Get PIDs
APP_PID=$(docker inspect --format '{{.State.Pid}}' myapp-app-1)
REDIS_PID=$(docker inspect --format '{{.State.Pid}}' myapp-redis-1)

# Benchmark with multi-process monitoring
sudo bench --runs 20 \
  --pid "app:$APP_PID" \
  --pid "redis:$REDIS_PID" \
  "curl -s localhost:5000"

# Verify both processes tracked
jq '.processes | length' bench-results/*/*/benchmark.json
jq '.processes[].name' bench-results/*/*/benchmark.json

# Cleanup
docker compose down
```

---

## 11. Output Structure Verification

```bash
bench --runs 3 --name "test" --message "verification" "echo hello"

# Directory structure
ls -la bench-results/test/*/
# Expected: benchmark.json, runs/

ls bench-results/test/*/runs/
# Expected: 1.log, 1.stdout, 1.stderr, 2.log, ...

# JSON fields check
jq 'keys' bench-results/test/*/benchmark.json
# Expected: schema_version, tool, tool_version, name, message, command,
#           runs_requested, runs_completed, runs_successful, runs_failed,
#           success_rate, interrupted, timing, environment, runs

# Timing stats
jq '.timing | keys' bench-results/test/*/benchmark.json
# Expected: unit, min, max, mean, median, stddev, p95, p99
```

---

## 12. Failure Tracking

```bash
# All failures
bench --runs 5 "exit 7"
jq '.runs_failed, .success_rate' bench-results/*/*/benchmark.json
# Expected: 5, 0

jq '.runs[].exit_code' bench-results/*/*/benchmark.json
# Expected: 7, 7, 7, 7, 7

# Mixed success/failure
bench --runs 10 'sh -c "exit $((RANDOM % 2))"'
jq '.runs_successful, .runs_failed' bench-results/*/*/benchmark.json
# Expected: Mix of successes and failures
```

---

## 13. Concurrent Benchmarks

```bash
# Run 3 benchmarks in parallel with same name
bench --runs 10 --quiet --name "concurrent" "echo 1" &
bench --runs 10 --quiet --name "concurrent" "echo 2" &
bench --runs 10 --quiet --name "concurrent" "echo 3" &
wait

# Should have 3 separate directories
ls bench-results/concurrent/
# Expected: 3 directories with different timestamp-PID suffixes

# Each has its own benchmark.json
find bench-results/concurrent -name "benchmark.json" | wc -l
# Expected: 3
```

---

## 14. Integration with jq

```bash
# Compare multiple runs
bench --name "api" --message "v1" --runs 10 "sleep 0.01"
bench --name "api" --message "v2" --runs 10 "sleep 0.02"

# Compare timing
jq -r '"\(.message): mean=\(.timing.mean)ms p99=\(.timing.p99)ms"' \
  bench-results/api/*/benchmark.json

# Find slowest runs
jq '.runs | max_by(.duration_ms)' bench-results/api/*/benchmark.json

# Filter failed runs
jq '.runs[] | select(.exit_code != 0)' bench-results/*/*/benchmark.json
```

---

## 15. Stress Testing

```bash
# 100 runs
bench --runs 100 --quiet "true"
jq '.runs_completed' bench-results/*/*/benchmark.json
# Expected: 100

# Timing consistency check
jq '.timing | .min <= .median and .median <= .max' bench-results/*/*/benchmark.json
# Expected: true

jq '.timing | .p95 <= .p99 and .p99 <= .max' bench-results/*/*/benchmark.json
# Expected: true
```

---

## Cleanup

```bash
rm -rf bench-results
```
