#!/usr/bin/env bats
# Phase 3 Output Tests - JSON structure, per-run data, statistics

load helpers

@test "benchmark.json contains runs array" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 3 --quiet "echo test"
  [ "$status" -eq 0 ]

  # Find the output directory
  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ -f "$json_file" ]

  # Check runs array exists and has 3 elements
  runs_count=$(grep -o '"run_number"' "$json_file" | wc -l)
  [ "$runs_count" -eq 3 ]
}

@test "per-run data contains required fields" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Check required fields in runs array
  grep -q '"run_number":1' "$json_file"
  grep -q '"exit_code":0' "$json_file"
  grep -q '"start":"' "$json_file"
  grep -q '"end":"' "$json_file"
  grep -q '"duration_seconds":' "$json_file"
  grep -q '"stdout_bytes":' "$json_file"
  grep -q '"stderr_bytes":' "$json_file"
}

@test "per-run timestamps are ISO 8601 format" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # ISO 8601 format: YYYY-MM-DDTHH:MM:SS.mmm
  grep -qE '"start":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}"' "$json_file"
  grep -qE '"end":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}"' "$json_file"
}

@test "per-run exit_code captures command failures" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 2 --quiet "exit 42"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Both runs should have exit_code 42
  exit_codes=$(grep -o '"exit_code":[0-9]*' "$json_file" | grep -o '[0-9]*$')
  echo "$exit_codes" | while read code; do
    [ "$code" -eq 42 ]
  done

  # runs_failed should be 2
  grep -q '"runs_failed": 2' "$json_file" || grep -q '"runs_failed":2' "$json_file"
}

@test "per-run stdout_bytes counts output correctly" {
  cd "$TEST_TEMP_DIR"
  # "hello" + newline = 6 bytes
  run_bench --runs 1 --quiet "echo hello"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # stdout should be 6 bytes
  grep -q '"stdout_bytes": *6' "$json_file" || grep -q '"stdout_bytes":6' "$json_file"
}

@test "per-run stderr_bytes counts stderr correctly" {
  cd "$TEST_TEMP_DIR"
  # "error" + newline = 6 bytes to stderr
  run_bench --runs 1 --quiet "echo error >&2"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # stderr should be 6 bytes
  grep -q '"stderr_bytes": *6' "$json_file" || grep -q '"stderr_bytes":6' "$json_file"
}

@test "timing statistics have leading zeros" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Numbers should have leading zeros (0.xxx not .xxx)
  # Check that there are no bare decimals like ": .5" or ":.5"
  ! grep -qE '": *\.[0-9]' "$json_file"
  ! grep -qE '":\.[0-9]' "$json_file"
}

@test "runs array preserves order" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 5 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)

  # Extract run numbers in order
  run_numbers=$(grep -o '"run_number":[0-9]*' "$json_file" | grep -o '[0-9]*$' | tr '\n' ' ')
  [ "$run_numbers" = "1 2 3 4 5 " ]
}

@test "auto-name falls back to 'benchmark' for special char commands" {
  cd "$TEST_TEMP_DIR"
  # Command with only special chars that get stripped
  run_bench --runs 1 --quiet ":"
  [ "$status" -eq 0 ]

  # Should create directory named "benchmark"
  [ -d "$TEST_TEMP_DIR/bench-results/benchmark" ]
}
