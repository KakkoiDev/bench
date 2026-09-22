#!/usr/bin/env bats
# Phase 4 Tests - Comparison, uncertainty and reporting

load helpers

# Two benchmarks whose metric differs by a known amount
make_pair() {
  make_script slow.sh '#!/bin/sh
printf "{\"metrics\":{\"latency_ms\":20,\"errors\":0}}" > "$BENCH_RESULT_JSON"'
  make_script fast.sh '#!/bin/sh
printf "{\"metrics\":{\"latency_ms\":10,\"errors\":0}}" > "$BENCH_RESULT_JSON"'
  cd "$TEST_TEMP_DIR"
  "$BENCH_SCRIPT" --quiet --runs 8 --name base --message "baseline" ./slow.sh > base.txt
  "$BENCH_SCRIPT" --quiet --runs 8 --name cand --message "candidate" ./fast.sh > cand.txt
  BASE=$(cat base.txt)
  CAND=$(cat cand.txt)
}

@test "compare reports both sides and the change" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "baseline"
  echo "$output" | grep -q "candidate"
  echo "$output" | grep -q "latency_ms"
}

@test "compare --json emits valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
}

@test "the relative difference is computed correctly" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  # 20 -> 10 is -50%
  [ "$(echo "$output" | jq -r '.metrics.latency_ms.relative_difference_percent')" = "-50" ]
  [ "$(echo "$output" | jq -r '.metrics.latency_ms.absolute_difference')" = "-10" ]
}

@test "a confidence interval is reported for the difference" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metrics.latency_ms.difference_ci_95 | length')" = "2" ]
}

@test "confidence interval bounds are ordered low to high" {
  # Regression: naming a lexical $a or $b breaks Perl's sort and silently
  # reverses the interval.
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]

  lo=$(echo "$output" | jq -r '.metrics.latency_ms.difference_ci_95[0]')
  hi=$(echo "$output" | jq -r '.metrics.latency_ms.difference_ci_95[1]')
  awk -v lo="$lo" -v hi="$hi" 'BEGIN { exit (lo <= hi) ? 0 : 1 }'
}

@test "an unchanged metric reports an interval that includes zero" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  # errors is 0 in both
  [ "$(echo "$output" | jq -r '.metrics.errors.interval_excludes_zero')" = "false" ]
}

@test "a real difference reports an interval that excludes zero" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metrics.latency_ms.interval_excludes_zero')" = "true" ]
}

@test "the same seed produces the same interval" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  first=$("$BENCH_SCRIPT" compare "$BASE" "$CAND" --json --seed 5 | jq -c '.timing.difference_ci_95')
  second=$("$BENCH_SCRIPT" compare "$BASE" "$CAND" --json --seed 5 | jq -c '.timing.difference_ci_95')
  [ "$first" = "$second" ]
}

@test "the seed is recorded in the report" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json --seed 123
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.seed')" = "123" ]
}

@test "invalid-run rates are reported for both sides" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script half.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":1}}" > "$BENCH_RESULT_JSON"
[ "$BENCH_RUN_NUMBER" -gt 2 ] || exit 1
exit 0'
  "$BENCH_SCRIPT" --quiet --runs 4 --name a ./half.sh > a.txt
  "$BENCH_SCRIPT" --quiet --runs 4 --name b ./half.sh > b.txt

  run "$BENCH_SCRIPT" compare "$(cat a.txt)" "$(cat b.txt)" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.baseline.runs_invalid')" = "2" ]
  [ "$(echo "$output" | jq -r '.baseline.invalid_rate_percent')" = "50" ]
}

@test "comparison uses valid runs only" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  # Invalid runs report a wildly different value; it must not move the mean
  make_script mixed.sh '#!/bin/sh
if [ "$BENCH_RUN_NUMBER" -le 2 ]; then
  printf "{\"metrics\":{\"v\":1000}}" > "$BENCH_RESULT_JSON"
  exit 1
fi
printf "{\"metrics\":{\"v\":10}}" > "$BENCH_RESULT_JSON"'
  "$BENCH_SCRIPT" --quiet --runs 6 --name a ./mixed.sh > a.txt
  "$BENCH_SCRIPT" --quiet --runs 6 --name b ./mixed.sh > b.txt

  run "$BENCH_SCRIPT" compare "$(cat a.txt)" "$(cat b.txt)" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metrics.v.baseline.mean')" = "10" ]
  [ "$(echo "$output" | jq -r '.metrics.v.baseline.count')" = "4" ]
}

@test "a satisfied --require passes and exits zero" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --require "errors == 0"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pass"
}

@test "a violated --require fails and exits non-zero" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --require "latency_ms < 5"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "FAIL"
}

@test "a --require naming an unknown metric is reported, not silently passed" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json --require "nonexistent < 1"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.constraints[0].status')" = "unknown" ]
}

@test "compare rejects an invalid constraint expression" {
  cd "$TEST_TEMP_DIR"
  make_pair
  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --require "errors =~ 0"
  [ "$status" -eq 1 ]
}

@test "the report distinguishes detectability from importance" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "whether it matters"
}

@test "compare requires two directories" {
  run "$BENCH_SCRIPT" compare
  [ "$status" -eq 1 ]
}

@test "compare rejects a directory with no benchmark.json" {
  cd "$TEST_TEMP_DIR"
  mkdir -p empty
  make_pair
  run "$BENCH_SCRIPT" compare "$BASE" empty
  [ "$status" -eq 1 ]
}

@test "paired statistics appear when the samples are the same size" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" compare "$BASE" "$CAND" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metrics.latency_ms.paired.mean_difference')" = "-10" ]
}

# =============================================================================
# report
# =============================================================================

@test "report summarizes one execution" {
  cd "$TEST_TEMP_DIR"
  make_pair

  run "$BENCH_SCRIPT" report "$CAND"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "timing"
  echo "$output" | grep -q "latency_ms"
}

@test "report shows the validity breakdown" {
  cd "$TEST_TEMP_DIR"
  make_script half.sh '#!/bin/sh
[ "$BENCH_RUN_NUMBER" -gt 2 ] || exit 1
exit 0'
  "$BENCH_SCRIPT" --quiet --runs 4 --name h ./half.sh > h.txt

  run "$BENCH_SCRIPT" report "$(cat h.txt)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "command_failed"
}

@test "report requires a result directory" {
  run "$BENCH_SCRIPT" report
  [ "$status" -eq 1 ]
}

@test "a command literally named like a subcommand is still benchmarked" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  # Only the first argument is treated as a subcommand
  run_bench --runs 1 --quiet "echo compare"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.command' "$(bench_json)")" = "echo compare" ]
}
