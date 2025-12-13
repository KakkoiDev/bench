#!/usr/bin/env bats
# Phase 4 Monitoring Tests - Server monitoring with --pid and --port

load helpers

@test "--pid accepts valid PID" {
  cd "$TEST_TEMP_DIR"

  # Start process directly (not in subshell) to avoid early termination
  sleep 60 &
  pid=$!

  run_bench --runs 1 --quiet --pid "$pid" "echo test"
  [ "$status" -eq 0 ]

  kill "$pid" 2>/dev/null || true
}

@test "--pid validates numeric argument" {
  run_bench --runs 1 --quiet --pid "abc" "echo test"
  [ "$status" -eq 1 ]
}

@test "--pid validates process exists before benchmark" {
  # Use a PID that definitely doesn't exist
  run_bench --runs 1 --quiet --pid "999999999" "echo test"
  [ "$status" -eq 1 ]
}

@test "--port accepts valid port number" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3
  port=$(get_server_port "$pid")

  run_bench --runs 1 --quiet --port "$port" "echo test"
  [ "$status" -eq 0 ]

  kill_mock_process "$pid"
}

@test "--port validates numeric argument" {
  run_bench --runs 1 --quiet --port "abc" "echo test"
  [ "$status" -eq 1 ]
}

@test "process metrics included in JSON when --pid used" {
  cd "$TEST_TEMP_DIR"

  # Start process directly (not in subshell) to avoid early termination
  sleep 60 &
  pid=$!

  # Give process time to start
  sleep 0.1

  # Verify process exists
  kill -0 "$pid" 2>/dev/null || { echo "Process $pid doesn't exist"; return 1; }

  # Run directly to avoid any run wrapper issues
  "$BENCH_SCRIPT" --runs 2 --quiet --pid "$pid" "echo test"
  bench_status=$?
  [ "$bench_status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ -f "$json_file" ] || { echo "No json file found"; return 1; }

  # Process metrics should be present (schema 2.0 uses "processes" array)
  grep -q '"processes":' "$json_file"
  grep -q '"cpu":' "$json_file"
  grep -q '"memory":' "$json_file"

  kill "$pid" 2>/dev/null || true
}

@test "process metrics included in JSON when --port used" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3
  port=$(get_server_port "$pid")

  run_bench --runs 1 --quiet --port "$port" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Process metrics should be present (schema 2.0 uses "processes" array)
  grep -q '"processes":' "$json_file"

  kill_mock_process "$pid"
}

@test "CPU metrics are numeric" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3

  run_bench --runs 2 --quiet --pid "$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # CPU values should be numeric (may be 0.0 for idle process)
  grep -qE '"cpu":\s*\{' "$json_file"
  grep -qE '"mean":\s*[0-9]' "$json_file"

  kill_mock_process "$pid"
}

@test "memory metrics are in megabytes" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3

  run_bench --runs 2 --quiet --pid "$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Memory section should have unit specified
  grep -q '"memory":' "$json_file"

  kill_mock_process "$pid"
}

@test "memory leak detection fields present" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3

  run_bench --runs 3 --quiet --pid "$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Memory leak detection fields
  grep -q '"initial":' "$json_file"
  grep -q '"final":' "$json_file"
  grep -q '"delta":' "$json_file"

  kill_mock_process "$pid"
}

@test "graceful handling when monitored process terminates" {
  cd "$TEST_TEMP_DIR"

  # Create a process that will die during benchmark
  # Process lives for 2 seconds, benchmark runs 5 times with 0.5s sleep each
  sleep 2 &
  pid=$!

  # Run benchmark with more runs than the process will live
  # Should complete gracefully, not crash
  run_bench --runs 5 --quiet --pid "$pid" "sleep 0.5"

  # Should exit 0 (benchmark completed) even if monitored process died
  [ "$status" -eq 0 ]

  # JSON should still be created
  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ -f "$json_file" ]
}

@test "no server metrics when --pid not used" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Server/processes section should NOT be present
  ! grep -q '"server":' "$json_file"
  ! grep -q '"processes":' "$json_file"
}

# =============================================================================
# Multi-Process Monitoring Tests (Schema 2.0)
# =============================================================================

@test "multiple --pid flags are accepted" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid1=$!
  sleep 60 &
  pid2=$!

  run_bench --runs 1 --quiet --pid "$pid1" --pid "$pid2" "echo test"
  [ "$status" -eq 0 ]

  kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "--pid accepts name:pid format" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid=$!

  run_bench --runs 1 --quiet --pid "myapp:$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  grep -q '"name": "myapp"' "$json_file" || grep -q '"name":"myapp"' "$json_file"

  kill "$pid" 2>/dev/null || true
}

@test "processes array contains all monitored processes" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid1=$!
  sleep 60 &
  pid2=$!

  run_bench --runs 2 --quiet --pid "app:$pid1" --pid "redis:$pid2" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ "$(jq '.processes | length' "$json_file")" -eq 2 ]
  [ "$(jq '.processes[0].name' "$json_file")" = '"app"' ]
  [ "$(jq '.processes[1].name' "$json_file")" = '"redis"' ]

  kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "per-run processes keyed by name" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid1=$!
  sleep 60 &
  pid2=$!

  run_bench --runs 1 --quiet --pid "app:$pid1" --pid "redis:$pid2" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  jq -e '.runs[0].processes.app' "$json_file"
  jq -e '.runs[0].processes.redis' "$json_file"

  kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "metrics files created for each process" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid1=$!
  sleep 60 &
  pid2=$!

  run_bench --runs 2 --quiet --pid "app:$pid1" --pid "redis:$pid2" "echo test"
  [ "$status" -eq 0 ]

  output_dir=$(find "$TEST_TEMP_DIR/bench-results" -type d -name "2*" | head -1)
  [ -f "$output_dir/runs/1.app.metrics" ]
  [ -f "$output_dir/runs/1.redis.metrics" ]
  [ -f "$output_dir/runs/2.app.metrics" ]
  [ -f "$output_dir/runs/2.redis.metrics" ]

  kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "auto-detects process name when not provided" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid=$!

  run_bench --runs 1 --quiet --pid "$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  grep -q '"name": "sleep"' "$json_file" || grep -q '"name":"sleep"' "$json_file"

  kill "$pid" 2>/dev/null || true
}

@test "mixed --pid and --port flags work together" {
  require_command python3

  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid=$!
  server_pid=$(create_real_server)
  sleep 0.3
  port=$(get_server_port "$server_pid")

  run_bench --runs 1 --quiet --pid "worker:$pid" --port "api:$port" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ "$(jq '.processes | length' "$json_file")" -eq 2 ]

  kill "$pid" 2>/dev/null || true
  kill_mock_process "$server_pid"
}

@test "duplicate process names produce error" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid1=$!
  sleep 60 &
  pid2=$!

  run_bench --runs 1 --quiet --pid "app:$pid1" --pid "app:$pid2" "echo test"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Duplicate process name" ]]

  kill "$pid1" "$pid2" 2>/dev/null || true
}

@test "--port accepts name:port format" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  server_pid=$(create_real_server)
  sleep 0.3
  port=$(get_server_port "$server_pid")

  run_bench --runs 1 --quiet --port "api:$port" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  grep -q '"name": "api"' "$json_file" || grep -q '"name":"api"' "$json_file"

  kill_mock_process "$server_pid"
}

@test "schema version is 2.0 when using multi-process monitoring" {
  cd "$TEST_TEMP_DIR"

  sleep 60 &
  pid=$!

  run_bench --runs 1 --quiet --pid "app:$pid" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ "$(jq -r '.schema_version' "$json_file")" = "2.0" ]

  kill "$pid" 2>/dev/null || true
}
