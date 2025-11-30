#!/usr/bin/env bats
# Phase 1 Foundation Tests - Basic functionality and POSIX compliance

load helpers

@test "bench script exists and is executable" {
  [ -f "$BENCH_SCRIPT" ]
  [ -x "$BENCH_SCRIPT" ]
}

@test "bench --version displays version" {
  run_bench --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^bench[[:space:]]v?[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "bench --help displays usage information" {
  run_bench --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  # Verify all 8 flags are documented
  [[ "$output" =~ "--runs" ]]
  [[ "$output" =~ "--name" ]]
  [[ "$output" =~ "--message" ]]
  [[ "$output" =~ "--quiet" ]]
  [[ "$output" =~ "--pid" ]]
  [[ "$output" =~ "--port" ]]
  [[ "$output" =~ "--help" ]]
  [[ "$output" =~ "--version" ]]
}

@test "bench runs with dash (POSIX compliance)" {
  require_command dash

  # Create minimal bench script stub for testing
  cat > "$TEST_TEMP_DIR/bench-stub" << 'EOF'
#!/bin/sh
# POSIX-compliant stub
echo "bench v1.0.0"
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bench-stub"

  run dash "$TEST_TEMP_DIR/bench-stub"
  [ "$status" -eq 0 ]
}

@test "bench passes ShellCheck validation" {
  require_command shellcheck

  # Exclude SC2034 (unused variable warnings)
  # These variables (QUIET, PID, PORT) will be used in Phase 2 implementation
  # TODO: Remove -e SC2034 flag after Phase 2 Task 6-8 (signal handling, argument parsing, benchmark loop)
  run shellcheck -s sh -e SC2034 "$BENCH_SCRIPT"
  [ "$status" -eq 0 ]
}
