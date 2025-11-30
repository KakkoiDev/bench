#!/usr/bin/env bats
# Phase 5 Integration Tests - End-to-end workflows and stress tests

load helpers

@test "full workflow: multiple runs with timing stats" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 10 --name "integration-test" --message "full workflow" "echo hello"
  [ "$status" -eq 0 ]

  # Verify directory structure
  [ -d "$TEST_TEMP_DIR/bench-results/integration-test" ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ -f "$json_file" ]

  # Verify all required fields present
  grep -q '"schema_version": "1.0"' "$json_file"
  grep -q '"name": "integration-test"' "$json_file"
  grep -q '"message": "full workflow"' "$json_file"
  grep -q '"runs_requested": 10' "$json_file"
  grep -q '"runs_completed": 10' "$json_file"
  grep -q '"runs_successful": 10' "$json_file"
  grep -q '"runs_failed": 0' "$json_file"

  # Verify timing stats
  grep -q '"mean":' "$json_file"
  grep -q '"median":' "$json_file"
  grep -q '"stddev":' "$json_file"
  grep -q '"p95":' "$json_file"
  grep -q '"p99":' "$json_file"

  # Verify runs array has 10 entries
  runs_count=$(grep -o '"run_number"' "$json_file" | wc -l)
  [ "$runs_count" -eq 10 ]
}

@test "full workflow with server monitoring" {
  require_command python3

  cd "$TEST_TEMP_DIR"
  pid=$(create_real_server)
  sleep 0.3
  port=$(get_server_port "$pid")

  run_bench --runs 5 --pid "$pid" --name "server-test" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Verify server metrics present
  grep -q '"server":' "$json_file"
  grep -q '"cpu":' "$json_file"
  grep -q '"memory":' "$json_file"
  grep -q '"initial":' "$json_file"
  grep -q '"final":' "$json_file"
  grep -q '"delta":' "$json_file"

  kill_mock_process "$pid"
}

@test "stress test: 50 runs complete successfully" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 50 --quiet "echo stress"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  grep -q '"runs_completed": 50' "$json_file"
  grep -q '"runs_successful": 50' "$json_file"

  # Verify all 50 log files created
  log_count=$(find "$TEST_TEMP_DIR/bench-results" -name "*.log" | wc -l)
  [ "$log_count" -eq 50 ]
}

@test "stress test: 100 runs with timing accuracy" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 100 --quiet "true"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  grep -q '"runs_completed": 100' "$json_file"

  # Timing values should be reasonable (< 1000ms for 'true' command)
  # Extract mean and verify it's a small number
  mean=$(grep -o '"mean": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  # Mean should be less than 100ms for 'true' command
  result=$(echo "$mean < 100" | bc)
  [ "$result" -eq 1 ]
}

@test "concurrent benchmarks create unique directories" {
  cd "$TEST_TEMP_DIR"

  # Run 3 benchmarks in parallel
  "$BENCH_SCRIPT" --runs 5 --quiet --name "concurrent" "echo 1" &
  pid1=$!
  "$BENCH_SCRIPT" --runs 5 --quiet --name "concurrent" "echo 2" &
  pid2=$!
  "$BENCH_SCRIPT" --runs 5 --quiet --name "concurrent" "echo 3" &
  pid3=$!

  wait $pid1
  wait $pid2
  wait $pid3

  # Should have 3 unique timestamp-PID directories
  dir_count=$(find "$TEST_TEMP_DIR/bench-results/concurrent" -maxdepth 1 -type d | wc -l)
  # Count is 4: concurrent dir + 3 subdirs
  [ "$dir_count" -eq 4 ]

  # Each should have a valid benchmark.json
  json_count=$(find "$TEST_TEMP_DIR/bench-results/concurrent" -name "benchmark.json" | wc -l)
  [ "$json_count" -eq 3 ]
}

@test "command failure tracking across multiple runs" {
  cd "$TEST_TEMP_DIR"

  # Mix of successful and failing commands
  run_bench --runs 10 --quiet "sh -c 'exit \$((RANDOM % 2))'"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # runs_completed should be 10
  grep -q '"runs_completed": 10' "$json_file"

  # Should have mix of success/failure (statistically likely)
  # Just verify the fields exist
  grep -q '"runs_successful":' "$json_file"
  grep -q '"runs_failed":' "$json_file"
  grep -q '"success_rate":' "$json_file"
}

@test "all exit codes tracked in failing command" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 5 --quiet "exit 7"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # All runs should have exit_code 7
  exit_7_count=$(grep -o '"exit_code":7' "$json_file" | wc -l)
  [ "$exit_7_count" -eq 5 ]

  grep -q '"runs_failed": 5' "$json_file"
  grep -q '"success_rate": 0' "$json_file"
}

@test "output bytes tracked correctly" {
  cd "$TEST_TEMP_DIR"

  # Command that produces known output sizes (7 chars)
  run_bench --runs 3 --quiet "echo -n 'seven77'"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Each run should have stdout_bytes: 7
  stdout_count=$(grep -o '"stdout_bytes": *7[,}]' "$json_file" | wc -l)
  [ "$stdout_count" -eq 3 ]
}

@test "stderr bytes tracked correctly" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 3 --quiet "echo -n 'error' >&2"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Each run should have stderr_bytes: 5
  stderr_5_count=$(grep -o '"stderr_bytes": *5' "$json_file" | wc -l)
  [ "$stderr_5_count" -eq 3 ]
}

@test "environment metadata captured" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  grep -q '"environment":' "$json_file"
  grep -q '"os":' "$json_file"
  grep -q '"shell":' "$json_file"
  grep -q '"pwd":' "$json_file"
}

@test "tool metadata in JSON" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  grep -q '"tool": "bench"' "$json_file"
  grep -q '"tool_version": "1.0.0"' "$json_file"
}

@test "quiet mode suppresses progress output" {
  cd "$TEST_TEMP_DIR"

  # With --quiet, stderr should be empty
  output=$("$BENCH_SCRIPT" --runs 5 --quiet "echo test" 2>&1 >/dev/null)
  [ -z "$output" ]
}

@test "non-quiet mode shows progress" {
  cd "$TEST_TEMP_DIR"

  # Without --quiet, stderr should have progress
  output=$("$BENCH_SCRIPT" --runs 3 "echo test" 2>&1 >/dev/null)
  [[ "$output" =~ "Running" ]]
  [[ "$output" =~ "Run" ]]
}

@test "absolute path output to stdout" {
  cd "$TEST_TEMP_DIR"

  result=$("$BENCH_SCRIPT" --runs 1 --quiet "echo test")

  # Output should be absolute path
  [[ "$result" == /* ]]

  # Path should exist
  [ -d "$result" ]

  # Path should contain benchmark.json
  [ -f "$result/benchmark.json" ]
}

@test "log files contain actual command output" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 3 --quiet "echo 'unique-marker-12345'"
  [ "$status" -eq 0 ]

  # Check each log file contains the marker
  for i in 1 2 3; do
    log_file=$(find "$TEST_TEMP_DIR/bench-results" -name "${i}.log" | head -1)
    grep -q "unique-marker-12345" "$log_file"
  done
}

@test "complex command with pipes works" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 3 --quiet "echo 'hello world' | tr 'a-z' 'A-Z'"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  grep -q '"runs_completed": 3' "$json_file"

  # Check output was transformed
  log_file=$(find "$TEST_TEMP_DIR/bench-results" -name "1.log" | head -1)
  grep -q "HELLO WORLD" "$log_file"
}

@test "command with environment variables works" {
  cd "$TEST_TEMP_DIR"

  export TEST_VAR="bench-test-value"
  run_bench --runs 2 --quiet 'echo $TEST_VAR'
  [ "$status" -eq 0 ]

  log_file=$(find "$TEST_TEMP_DIR/bench-results" -name "1.log" | head -1)
  grep -q "bench-test-value" "$log_file"
}

@test "working directory preserved during benchmark" {
  cd "$TEST_TEMP_DIR"
  mkdir -p subdir
  echo "test-content" > subdir/test-file.txt

  run_bench --runs 1 --quiet "cat subdir/test-file.txt"
  [ "$status" -eq 0 ]

  log_file=$(find "$TEST_TEMP_DIR/bench-results" -name "1.log" | head -1)
  grep -q "test-content" "$log_file"
}

@test "statistical consistency: min <= median <= max" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 20 --quiet "sleep 0.01"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  min=$(grep -o '"min": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  median=$(grep -o '"median": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  max=$(grep -o '"max": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')

  # min <= median
  result=$(echo "$min <= $median" | bc)
  [ "$result" -eq 1 ]

  # median <= max
  result=$(echo "$median <= $max" | bc)
  [ "$result" -eq 1 ]
}

@test "statistical consistency: mean within min-max range" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 20 --quiet "sleep 0.01"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  min=$(grep -o '"min": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  mean=$(grep -o '"mean": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  max=$(grep -o '"max": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')

  # min <= mean
  result=$(echo "$min <= $mean" | bc)
  [ "$result" -eq 1 ]

  # mean <= max
  result=$(echo "$mean <= $max" | bc)
  [ "$result" -eq 1 ]
}

@test "p95 <= p99 <= max" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 20 --quiet "sleep 0.01"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  p95=$(grep -o '"p95": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  p99=$(grep -o '"p99": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')
  max=$(grep -o '"max": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')

  # p95 <= p99
  result=$(echo "$p95 <= $p99" | bc)
  [ "$result" -eq 1 ]

  # p99 <= max
  result=$(echo "$p99 <= $max" | bc)
  [ "$result" -eq 1 ]
}

@test "stddev is non-negative" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 10 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  stddev=$(grep -o '"stddev": *[0-9.]*' "$json_file" | grep -o '[0-9.]*$')

  result=$(echo "$stddev >= 0" | bc)
  [ "$result" -eq 1 ]
}
