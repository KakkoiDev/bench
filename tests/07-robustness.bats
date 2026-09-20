#!/usr/bin/env bats
# Phase 7 Robustness Tests - JSON escaping, path safety, process name handling
#
# These cover regressions found by fuzzing the CLI with input that is ordinary
# for a benchmarking tool (quoted shell commands, paths, arbitrary --message
# text) but which previously produced unparseable JSON or escaped the results
# directory.

load helpers

# -----------------------------------------------------------------------------
# JSON escaping
# -----------------------------------------------------------------------------

@test "command containing double quotes produces valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet 'echo "hello world"'
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  assert_valid_json "$json_file"

  # Round-trips back to the original command
  [ "$(get_json_value "$json_file" '.command')" = 'echo "hello world"' ]
}

@test "message containing quotes and backslashes produces valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --message 'said "hi" at C:\temp' "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  assert_valid_json "$json_file"

  [ "$(get_json_value "$json_file" '.message')" = 'said "hi" at C:\temp' ]
}

@test "message containing a tab produces valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --message "$(printf 'a\tb')" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  assert_valid_json "$json_file"

  [ "$(get_json_value "$json_file" '.message')" = "$(printf 'a\tb')" ]
}

@test "name containing a double quote produces valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name 'my"group' "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  assert_valid_json "$json_file"

  [ "$(get_json_value "$json_file" '.name')" = 'my"group' ]
}

@test "working directory containing a quote produces valid JSON" {
  require_command jq

  odd_dir="$TEST_TEMP_DIR/dir\"with-quote"
  mkdir -p "$odd_dir"
  cd "$odd_dir"

  run "$BENCH_SCRIPT" --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$odd_dir/bench-results" -name "benchmark.json" | head -1)
  assert_valid_json "$json_file"
}

# -----------------------------------------------------------------------------
# --name path safety
# -----------------------------------------------------------------------------

@test "--name rejects path traversal" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name "../../escaped" "echo test"
  [ "$status" -eq 1 ]
  [ ! -d "$TEST_TEMP_DIR/../../escaped" ]
}

@test "--name rejects any slash" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name "a/b" "echo test"
  [ "$status" -eq 1 ]
}

@test "--name rejects dot and dot-dot" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name "." "echo test"
  [ "$status" -eq 1 ]

  run_bench --runs 1 --quiet --name ".." "echo test"
  [ "$status" -eq 1 ]
}

@test "--name still accepts ordinary names" {
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name "api-v2.1_test" "echo test"
  [ "$status" -eq 0 ]
  assert_dir_exists "$TEST_TEMP_DIR/bench-results/api-v2.1_test"
}

# -----------------------------------------------------------------------------
# Process name handling
# -----------------------------------------------------------------------------

@test "--pid rejects a process name containing a slash" {
  cd "$TEST_TEMP_DIR"

  create_mock_process 30

  run_bench --runs 1 --quiet --pid "a/b:$MOCK_PID" "echo test"
  [ "$status" -eq 1 ]

  kill_mock_process "$MOCK_PID"
}

@test "--pid rejects a process name containing a space" {
  cd "$TEST_TEMP_DIR"

  create_mock_process 30

  run_bench --runs 1 --quiet --pid "my app:$MOCK_PID" "echo test"
  [ "$status" -eq 1 ]

  kill_mock_process "$MOCK_PID"
}

@test "--port rejects an invalid process name" {
  require_command python3
  require_command lsof
  cd "$TEST_TEMP_DIR"

  server_pid=$(create_real_server)
  port=$(get_server_port "$server_pid") || {
    kill_mock_process "$server_pid"
    skip "could not determine server port"
  }

  run_bench --runs 1 --quiet --port "bad name:$port" "echo test"
  [ "$status" -eq 1 ]

  kill_mock_process "$server_pid"
}

@test "duplicate auto-detected names get sequential suffixes" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  create_mock_process 30 PID_A
  create_mock_process 30 PID_B
  create_mock_process 30 PID_C

  run_bench --runs 1 --quiet --pid "$PID_A" --pid "$PID_B" --pid "$PID_C" "echo test"
  [ "$status" -eq 0 ]

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  names=$(jq -r '.processes[].name' "$json_file" | tr '\n' ' ')

  # All three are the same binary, so they differ only by suffix: X X-2 X-3
  [ "$(jq -r '.processes | length' "$json_file")" -eq 3 ]
  [ "$(jq -r '[.processes[].name] | unique | length' "$json_file")" -eq 3 ]
  echo "$names" | grep -q -- '-2 '
  echo "$names" | grep -q -- '-3 '

  kill_mock_process "$PID_A"
  kill_mock_process "$PID_B"
  kill_mock_process "$PID_C"
}

@test "a name that is a prefix of another is not a duplicate" {
  # Regression: duplicate detection used `grep -w`, for which '-' is a word
  # boundary, so "app" collided with "app-2".
  cd "$TEST_TEMP_DIR"

  create_mock_process 30 PID_A
  create_mock_process 30 PID_B

  # Order matters: the stale name must be registered first, so that checking
  # "app" scans a seen-list already containing "app-2".
  run_bench --runs 1 --quiet --pid "app-2:$PID_A" --pid "app:$PID_B" "echo test"
  [ "$status" -eq 0 ]

  kill_mock_process "$PID_A"
  kill_mock_process "$PID_B"
}

@test "a name containing a dot is matched literally, not as a regex" {
  # Regression: `grep -w "node.js"` matched the unrelated name "nodeXjs".
  cd "$TEST_TEMP_DIR"

  create_mock_process 30 PID_A
  create_mock_process 30 PID_B

  # "nodeXjs" is registered first so that "node.js", read as a regex, would
  # match it.
  run_bench --runs 1 --quiet --pid "nodeXjs:$PID_A" --pid "node.js:$PID_B" "echo test"
  [ "$status" -eq 0 ]

  kill_mock_process "$PID_A"
  kill_mock_process "$PID_B"
}

@test "explicit duplicate process names are rejected" {
  cd "$TEST_TEMP_DIR"

  create_mock_process 30 PID_A
  create_mock_process 30 PID_B

  run_bench --runs 1 --quiet --pid "app:$PID_A" --pid "app:$PID_B" "echo test"
  [ "$status" -eq 1 ]

  kill_mock_process "$PID_A"
  kill_mock_process "$PID_B"
}

# -----------------------------------------------------------------------------
# Resource cleanup
# -----------------------------------------------------------------------------

@test "temp files are removed after a successful run" {
  cd "$TEST_TEMP_DIR"

  before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
  run_bench --runs 2 --quiet "echo test"
  [ "$status" -eq 0 ]
  after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)

  [ "$after" -le "$before" ]
}

@test "temp files are removed when bench exits with an error" {
  cd "$TEST_TEMP_DIR"

  before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)
  run_bench --runs 1 --quiet --name "a/b" "echo test"
  [ "$status" -eq 1 ]
  after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' 2>/dev/null | wc -l)

  [ "$after" -le "$before" ]
}

@test "metrics sampler does not outlive an interrupted benchmark" {
  # The sampler is a background loop with no natural end. On a normal exit
  # stop_metrics_sampler kills it; this covers the abnormal path, where only
  # the EXIT trap can.
  cd "$TEST_TEMP_DIR"

  create_mock_process 60

  "$BENCH_SCRIPT" --runs 50 --quiet --metrics-interval 100 \
    --pid "app:$MOCK_PID" "sleep 2" >/dev/null 2>&1 &
  bench_pid=$!

  # Let the first run start so the sampler is definitely running
  sleep 1
  [ -n "$(pgrep -P "$bench_pid" 2>/dev/null)" ]

  kill -TERM "$bench_pid" 2>/dev/null
  wait "$bench_pid" 2>/dev/null || true
  sleep 0.5

  # No descendant of the (now gone) bench process may remain
  [ -z "$(pgrep -P "$bench_pid" 2>/dev/null)" ]

  kill_mock_process "$MOCK_PID"
}

@test "interrupted benchmark still writes valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  "$BENCH_SCRIPT" --runs 50 --quiet "sleep 1" >/dev/null 2>&1 &
  bench_pid=$!

  sleep 2
  kill -TERM "$bench_pid" 2>/dev/null
  wait "$bench_pid" 2>/dev/null || true

  json_file=$(find "$TEST_TEMP_DIR/bench-results" -name "benchmark.json" | head -1)
  [ -f "$json_file" ]
  assert_valid_json "$json_file"

  [ "$(get_json_value "$json_file" '.interrupted')" = "true" ]
}
