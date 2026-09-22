#!/usr/bin/env bats
# Phase 5 Tests - Deterministic resumption
#
# An interrupted experiment must continue into the same result rather than
# starting a second partial one, and must refuse to do so when the conditions
# have changed underneath it.

load helpers

# Start a benchmark, interrupt it partway, and leave the results path in
# $PARTIAL. Each run sleeps so the interrupt lands mid-benchmark.
# Usage: interrupt_after <seconds> <runs> <script>
interrupt_after() {
  local wait_for="$1" runs="$2" script="$3"
  "$BENCH_SCRIPT" --runs "$runs" --quiet "$script" > "$TEST_TEMP_DIR/path.txt" 2>&1 &
  local pid=$!
  sleep "$wait_for"
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  sleep 1
  PARTIAL=$(cat "$TEST_TEMP_DIR/path.txt")
}

# A subject that records its run number and takes about a second
slow_emitter() {
  make_script w.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":%s}}" "$BENCH_RUN_NUMBER" > "$BENCH_RESULT_JSON"
sleep 1'
}

# =============================================================================
# The core behaviour
# =============================================================================

@test "an interrupted benchmark can be resumed to completion" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 4.5 10 ./w.sh
  partial_runs=$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")
  [ "$partial_runs" -gt 0 ]
  [ "$partial_runs" -lt 10 ]

  run "$BENCH_SCRIPT" --runs 10 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  [ "$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")" = "10" ]
  [ "$(jq -r '.interrupted' "$PARTIAL/benchmark.json")" = "false" ]
}

@test "resuming continues the same result directory" {
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 8 ./w.sh
  run "$BENCH_SCRIPT" --runs 8 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]
  [ "$output" = "$PARTIAL" ]
}

@test "completed runs are not repeated" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 4.5 10 ./w.sh
  before=$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")

  run "$BENCH_SCRIPT" --runs 10 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  # Each run records its own number; every number appears exactly once
  values=$(jq -c '[.metrics.v.values[]] | sort' "$PARTIAL/benchmark.json")
  [ "$values" = "[1,2,3,4,5,6,7,8,9,10]" ]

  # And the runs before the interrupt kept their original identity
  [ "$(jq -r "[.runs[].run_number] | .[0:$before] | add" "$PARTIAL/benchmark.json")" \
    = "$(seq 1 "$before" | paste -sd+ | bc)" ]
}

@test "run numbers stay contiguous across a resume" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.runs[].run_number]' "$PARTIAL/benchmark.json")" = "[1,2,3,4,5,6]" ]
}

@test "statistics are recomputed over the combined sample" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  json="$PARTIAL/benchmark.json"
  # v is the run number, so over runs 1..6 the mean is 3.5
  [ "$(jq -r '.metrics.v.count' "$json")" = "6" ]
  [ "$(jq -r '.metrics.v.mean' "$json")" = "3.5" ]
  # Timing statistics cover all six runs too
  [ "$(jq -r '.runs | length' "$json")" = "6" ]
}

@test "the interrupted run's directory is discarded and redone" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  [ "$(find "$PARTIAL/runs" -name INCOMPLETE | wc -l)" -eq 1 ]

  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  # No marker survives, and the run that was in flight produced a real record
  [ "$(find "$PARTIAL/runs" -name INCOMPLETE | wc -l)" -eq 0 ]
  [ "$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")" = "6" ]
}

@test "resuming a finished benchmark changes nothing" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter e.sh '{"metrics":{"a":1}}'

  run_bench --runs 3 --quiet ./e.sh
  [ "$status" -eq 0 ]
  d=$(run_dir)
  before=$(jq -r '.runs_completed' "$d/benchmark.json")

  run "$BENCH_SCRIPT" --runs 3 --quiet --resume "$d" ./e.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs_completed' "$d/benchmark.json")" = "$before" ]
}

@test "validity accounting survives a resume" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script w.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":%s}}" "$BENCH_RUN_NUMBER" > "$BENCH_RESULT_JSON"
sleep 1
[ "$BENCH_RUN_NUMBER" = "2" ] && exit 1
exit 0'

  interrupt_after 4.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  json="$PARTIAL/benchmark.json"
  # Run 2 failed before the interrupt and is still counted as failed after
  [ "$(jq -r '.validity.command_failed' "$json")" = "1" ]
  [ "$(jq -r '.runs_valid' "$json")" = "5" ]
  [ "$(jq -r '[.validity[]] | add' "$json")" = "6" ]
}

@test "an invalid completed run is not re-rolled" {
  # Re-running failures until they pass would bias the sample toward success
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script w.sh '#!/bin/sh
sleep 1
[ "$BENCH_RUN_NUMBER" = "1" ] && exit 1
exit 0'

  interrupt_after 3.5 5 ./w.sh
  [ "$(jq -r '.runs[0].status' "$PARTIAL/benchmark.json")" = "command_failed" ]

  run "$BENCH_SCRIPT" --runs 5 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  # Run 1 is still the failure it was
  [ "$(jq -r '.runs[0].status' "$PARTIAL/benchmark.json")" = "command_failed" ]
  [ "$(jq -r '.validity.command_failed' "$PARTIAL/benchmark.json")" = "1" ]
}

@test "metrics from before the interrupt are preserved" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  before=$(jq -c '.metrics.v.values' "$PARTIAL/benchmark.json")

  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  after=$(jq -c '[.metrics.v.values[]] | sort' "$PARTIAL/benchmark.json")
  # Everything present before is still present
  for v in $(echo "$before" | jq -r '.[]'); do
    echo "$after" | grep -q "$v" || {
      echo "value $v lost across resume"
      return 1
    }
  done
}

@test "the resumed result is still valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]
  assert_valid_json "$PARTIAL/benchmark.json"
}

# =============================================================================
# Verification before resuming
# =============================================================================

@test "a resume with a different command is refused" {
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" "echo something-else"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fingerprint"
}

@test "a refused resume names the override flag" {
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" "echo something-else"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q -- "--force-resume"
}

@test "a resume with different constraints is refused" {
  cd "$TEST_TEMP_DIR"
  make_script w.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":1}}" > "$BENCH_RESULT_JSON"
sleep 1'

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --require "v == 1" --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 1 ]
}

@test "--force-resume proceeds and records the override" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --force-resume --resume "$PARTIAL" "echo something-else"
  [ "$status" -eq 0 ]

  entry=$(jq -c '.provenance.resumes[-1]' "$PARTIAL/benchmark.json")
  echo "$entry" | grep -q '"override":true'
  echo "$entry" | grep -q "fingerprint"
}

@test "an unforced resume records no override" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 3.5 6 ./w.sh
  run "$BENCH_SCRIPT" --runs 6 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  entry=$(jq -c '.provenance.resumes[-1]' "$PARTIAL/benchmark.json")
  echo "$entry" | grep -q '"override":false'
}

@test "the resume history records where it picked up" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 4.5 8 ./w.sh
  completed=$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")

  run "$BENCH_SCRIPT" --runs 8 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.resumes[-1].resumed_from_run' "$PARTIAL/benchmark.json")" = "$completed" ]
}

@test "resume history accumulates across several sittings" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  slow_emitter

  interrupt_after 2.5 12 ./w.sh

  # Interrupt the resume itself, then resume again
  "$BENCH_SCRIPT" --runs 12 --quiet --resume "$PARTIAL" ./w.sh >/dev/null 2>&1 &
  pid=$!
  sleep 2.5
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
  sleep 1

  run "$BENCH_SCRIPT" --runs 12 --quiet --resume "$PARTIAL" ./w.sh
  [ "$status" -eq 0 ]

  [ "$(jq -r '.provenance.resumes | length' "$PARTIAL/benchmark.json")" -ge 2 ]
  [ "$(jq -r '.runs_completed' "$PARTIAL/benchmark.json")" = "12" ]
  [ "$(jq -c '[.metrics.v.values[]] | sort' "$PARTIAL/benchmark.json")" \
    = "[1,2,3,4,5,6,7,8,9,10,11,12]" ]
}

@test "a fresh benchmark records an empty resume history" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.provenance.resumes' "$(bench_json)")" = "[]" ]
}

# =============================================================================
# Argument handling
# =============================================================================

@test "--resume requires a directory" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --resume
  [ "$status" -eq 1 ]
}

@test "--resume rejects a directory with no benchmark.json" {
  cd "$TEST_TEMP_DIR"
  mkdir -p empty
  run_bench --runs 1 --quiet --resume empty "echo test"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "benchmark.json"
}

@test "--resume rejects a nonexistent directory" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --resume /nonexistent/path "echo test"
  [ "$status" -eq 1 ]
}
