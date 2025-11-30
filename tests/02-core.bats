#!/usr/bin/env bats
# Phase 2 Core Tests - Dependency checking, signal handling, argument parsing

load helpers

@test "bench checks for perl dependency" {
  skip "Requires dependency checking implementation in bench script"

  # Empty PATH so perl can't be found
  run sh -c 'PATH=/dev/null "$BENCH_SCRIPT" --runs 1 "echo test" 2>&1'
  [ "$status" -ne 0 ]
  [[ "$output" =~ "perl" ]]
}

@test "bench checks for bc dependency" {
  skip "Requires dependency checking implementation in bench script"

  # Create perl stub so perl check passes, then bc check can fail
  stub_dir=$(create_stub "perl")

  # PATH has our fake perl but no bc
  run sh -c 'PATH="'"$stub_dir"'" "$BENCH_SCRIPT" --runs 1 "echo test" 2>&1'
  [ "$status" -ne 0 ]
  [[ "$output" =~ "bc" ]]
}

@test "bench handles SIGINT gracefully" {
  skip "Requires implementation of signal handling"

  # Start bench in background
  cd "$TEST_TEMP_DIR"
  "$BENCH_SCRIPT" --runs 100 "sleep 0.1" &
  BENCH_PID=$!

  # Wait for it to start
  sleep 0.5

  # Send SIGINT
  kill -INT "$BENCH_PID"
  wait "$BENCH_PID" || BENCH_EXIT=$?

  # Should exit with 130 (128 + 2 for SIGINT)
  [ "$BENCH_EXIT" -eq 130 ]

  # Should have created partial results
  assert_file_exists "$TEST_TEMP_DIR/bench-results/"*/benchmark.json
}

@test "bench --runs requires numeric argument" {
  run_bench --runs abc "echo test"
  [ "$status" -eq 1 ]
}

@test "bench --runs requires positive number" {
  run_bench --runs 0 "echo test"
  [ "$status" -eq 1 ]

  run_bench --runs -5 "echo test"
  [ "$status" -eq 1 ]
}

@test "bench --name validates length (max 255 chars)" {
  skip "Requires implementation of input validation"

  # Generate 256 character string
  LONG_NAME=$(printf 'a%.0s' {1..256})

  run_bench --runs 1 --name "$LONG_NAME" "echo test"
  [ "$status" -eq 1 ]
}

@test "bench --message validates length (max 1000 chars)" {
  skip "Requires implementation of input validation"

  # Generate 1001 character string
  LONG_MSG=$(printf 'a%.0s' {1..1001})

  run_bench --runs 1 --message "$LONG_MSG" "echo test"
  [ "$status" -eq 1 ]
}

@test "bench validates disk space for large --runs" {
  skip "Requires implementation of pre-flight validation"

  # Try to run with excessive runs (assume 10MB per run)
  # This should fail pre-flight validation if disk < runs*10MB
  run_bench --runs 999999999 "echo test"
  [ "$status" -eq 1 ]
}

@test "bench requires command argument" {
  run_bench --runs 5
  [ "$status" -eq 1 ]
}
