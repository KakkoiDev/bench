#!/usr/bin/env bats
# Phase 2 Tests - Evaluators and validity (schema 2.1)
#
# The governing rule: a benchmark subject cannot mark itself successful.
# Validity is established by the exit requirement, an independent evaluator,
# schema-valid evidence, hard constraints and required artifacts -- never by
# the subject's own claim.

load helpers

# A subject that emits one metric per run and an artifact
emitter() {
  make_script emit.sh '#!/bin/sh
echo "subject stdout"
echo "subject stderr" >&2
echo body > "$BENCH_ARTIFACTS/out.txt"
printf "{\"metrics\":{\"errors\":0,\"score\":0.9}}" > "$BENCH_RESULT_JSON"'
}

# =============================================================================
# The central guarantee
# =============================================================================

@test "a failing command cannot rescue itself by declaring valid:true" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script cheat.sh '#!/bin/sh
printf "{\"valid\":true,\"metrics\":{\"score\":1.0}}" > "$BENCH_RESULT_JSON"
exit 1'

  run_bench --runs 1 --quiet ./cheat.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  # The claim is recorded...
  [ "$(jq -r '.runs[0].evidence.declared_valid' "$json")" = "true" ]
  # ...and carries no weight
  [ "$(run_status 1)" = "command_failed" ]
  [ "$(jq -r '.runs[0].valid' "$json")" = "false" ]
  [ "$(jq -r '.runs_valid' "$json")" = "0" ]
}

@test "declaring valid:true does not substitute for an evaluator" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter claim.sh '{"valid":true,"metrics":{"score":1.0}}'

  run_bench --runs 1 --quiet ./claim.sh
  [ "$status" -eq 0 ]

  # With no evaluator configured, nothing independently validated this run
  [ "$(jq -r '.evaluator' "$(bench_json)")" = "" ]
  [ "$(jq -r '.runs[0].evaluation' "$(bench_json)")" = "null" ]
}

@test "a command may veto itself with valid:false" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter veto.sh '{"valid":false,"metrics":{"score":0.1}}'

  run_bench --runs 1 --quiet ./veto.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "declared_invalid" ]
  [ "$(jq -r '.runs_valid' "$(bench_json)")" = "0" ]
}

@test "an evaluator can reject a command that exited cleanly" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"valid\":false}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 2 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "evaluator_failed" ]
  [ "$(jq -r '.runs_valid' "$(bench_json)")" = "0" ]
  [ "$(jq -r '.runs_successful' "$(bench_json)")" = "2" ]
}

# =============================================================================
# Evaluator interface
# =============================================================================

@test "the evaluator receives the run directory as its first argument" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
echo "$1" > "'"$TEST_TEMP_DIR"'/arg.txt"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ -d "$(cat "$TEST_TEMP_DIR/arg.txt")" ]
  [ -f "$(cat "$TEST_TEMP_DIR/arg.txt")/result.json" ]
}

@test "the evaluator receives BENCH_RUN_DIR" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
[ "$BENCH_RUN_DIR" = "$1" ] || exit 1'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the evaluator receives the command's exit code" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
[ "$BENCH_EXIT_CODE" = "0" ] || exit 1'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the evaluator can read the command's stdout and stderr" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
grep -q "subject stdout" "$BENCH_STDOUT" || exit 1
grep -q "subject stderr" "$BENCH_STDERR" || exit 1'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the evaluator can read artifacts the command produced" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
grep -q body "$1/artifacts/out.txt" || exit 1'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "evaluator stdout and stderr are recorded" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
echo "grader says hello"
echo "grader warning" >&2'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  grep -q "grader says hello" "$(run_dir)/runs/1/evaluator.stdout"
  grep -q "grader warning" "$(run_dir)/runs/1/evaluator.stderr"
}

@test "the evaluator exit status is recorded" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
exit 7'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs[0].evaluation.exit_code' "$(bench_json)")" = "7" ]
  [ "$(run_status 1)" = "evaluator_failed" ]
}

@test "an evaluator declaring valid:true is recorded as such" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"valid\":true}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs[0].evaluation.valid' "$(bench_json)")" = "true" ]
  [ "$(run_status 1)" = "ok" ]
}

@test "evaluator metrics are merged into the aggregate" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"metrics\":{\"grade\":0.88}}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 3 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.grade.mean' "$(bench_json)")" = "0.88" ]
  [ "$(jq -r '.metrics.grade.count' "$(bench_json)")" = "3" ]
  # The subject's own metrics are still there
  [ "$(jq -r '.metrics.score.count' "$(bench_json)")" = "3" ]
}

@test "the evaluator may be given arguments" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
[ "$1" = "--strict" ] || exit 1
[ -d "$2" ] || exit 1'

  run_bench --runs 1 --quiet --evaluate "./grade.sh --strict" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the evaluator is not consulted when the command failed" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script fail.sh '#!/bin/sh
exit 1'
  make_script grade.sh '#!/bin/sh
echo ran > "'"$TEST_TEMP_DIR"'/grader-ran.txt"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./fail.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "command_failed" ]
  [ "$(jq -r '.runs[0].evaluation' "$(bench_json)")" = "null" ]
  [ ! -f "$TEST_TEMP_DIR/grader-ran.txt" ]
}

@test "invalid evaluator evidence is reported as invalid_result" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"metrics\":{\"grade\":\"excellent\"}}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "evaluation"
}

@test "the evaluator command is recorded in the result" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
exit 0'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.evaluator' "$(bench_json)")" = "./grade.sh" ]
}

@test "--evaluate requires an argument" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --evaluate
  [ "$status" -eq 1 ]
}

# =============================================================================
# Hard constraints
# =============================================================================

@test "a satisfied constraint leaves the run valid" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet --require "errors == 0" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "a violated constraint invalidates the run" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"errors":3}}'

  run_bench --runs 1 --quiet --require "errors == 0" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
  echo "$(run_error 1)" | grep -q "errors == 0"
  [ "$(jq -r '.validity.constraint_failed' "$(bench_json)")" = "1" ]
}

@test "a constraint on an unreported metric fails clearly" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet --require "nonexistent < 5" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
  echo "$(run_error 1)" | grep -q "did not report"
}

@test "all six comparison operators work" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"v":5}}'

  for expr in "v == 5" "v != 4" "v < 6" "v <= 5" "v > 4" "v >= 5"; do
    rm -rf "$TEST_TEMP_DIR/bench-results"
    run_bench --runs 1 --quiet --require "$expr" ./emit.sh
    [ "$status" -eq 0 ]
    [ "$(run_status 1)" = "ok" ] || {
      echo "expected '$expr' to hold for v=5"
      return 1
    }
  done
}

@test "all six operators also reject correctly" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"v":5}}'

  for expr in "v == 4" "v != 5" "v < 5" "v <= 4" "v > 5" "v >= 6"; do
    rm -rf "$TEST_TEMP_DIR/bench-results"
    run_bench --runs 1 --quiet --require "$expr" ./emit.sh
    [ "$status" -eq 0 ]
    [ "$(run_status 1)" = "constraint_failed" ] || {
      echo "expected '$expr' to fail for v=5"
      return 1
    }
  done
}

@test "constraints compare floating point values" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"rate":0.955}}'

  run_bench --runs 1 --quiet --require "rate >= 0.95" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]

  rm -rf "$TEST_TEMP_DIR/bench-results"
  run_bench --runs 1 --quiet --require "rate >= 0.96" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
}

@test "constraints accept negative right-hand sides" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"delta":-2}}'

  run_bench --runs 1 --quiet --require "delta < -1" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "multiple constraints are all enforced" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"errors":0,"latency":120}}'

  run_bench --runs 1 --quiet --require "errors == 0" --require "latency < 100" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
  echo "$(run_error 1)" | grep -q "latency < 100"
}

@test "a constraint may reference an evaluator-supplied metric" {
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"metrics\":{\"grade\":0.4}}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh --require "grade >= 0.8" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
}

@test "--require rejects an expression with the wrong number of terms" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require "errors ==" "echo test"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "metric.*op.*number"
}

@test "--require rejects an unknown operator" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require "errors =~ 0" "echo test"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "operator"
}

@test "--require rejects a non-numeric right-hand side" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require "errors == baseline" "echo test"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "number"
}

@test "--require rejects an invalid metric name" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require "2bad == 0" "echo test"
  [ "$status" -eq 1 ]
}

@test "--require does not evaluate shell code" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require 'x == $(touch pwned)' "echo test"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_TEMP_DIR/pwned" ]
}

@test "--require requires an argument" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require
  [ "$status" -eq 1 ]
}

# =============================================================================
# Required artifacts
# =============================================================================

@test "a present required artifact leaves the run valid" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet --require-artifact "artifacts/out.txt" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "a required artifact is also found by its bare name" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet --require-artifact "out.txt" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "a missing required artifact invalidates the run" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet --require-artifact "absent.txt" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
  echo "$(run_error 1)" | grep -q "required artifact"
}

@test "several required artifacts are all checked" {
  cd "$TEST_TEMP_DIR"
  emitter

  run_bench --runs 1 --quiet \
    --require-artifact "out.txt" --require-artifact "absent.txt" ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "constraint_failed" ]
}

@test "--require-artifact rejects an absolute path" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require-artifact "/etc/passwd" "echo test"
  [ "$status" -eq 1 ]
}

@test "--require-artifact rejects a traversal path" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --require-artifact "../escape" "echo test"
  [ "$status" -eq 1 ]
}

# =============================================================================
# Exit requirements
# =============================================================================

@test "a non-zero exit is a command failure by default" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "exit 1"
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "command_failed" ]
  echo "$(run_error 1)" | grep -q "expected 0"
}

@test "--expect-exit accepts a specific non-zero code" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit 3 "exit 3"
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "--expect-exit fails when the code does not match" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit 3 "exit 4"
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "command_failed" ]
}

@test "--expect-exit any accepts every exit code" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit any "exit 9"
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "--expect-exit is recorded in the result" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit 2 "exit 2"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expect_exit' "$(bench_json)")" = "2" ]
}

@test "--expect-exit rejects a non-numeric code" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit nope "echo test"
  [ "$status" -eq 1 ]
}

@test "--expect-exit rejects a code above 255" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --expect-exit 999 "echo test"
  [ "$status" -eq 1 ]
}

# =============================================================================
# Validity accounting
# =============================================================================

@test "validity counts sum to the number of completed runs" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script mixed.sh '#!/bin/sh
case "$BENCH_RUN_NUMBER" in
  1) printf "{\"metrics\":{\"e\":0}}" > "$BENCH_RESULT_JSON" ;;
  2) exit 1 ;;
  3) printf "{\"metrics\":{\"e\":\"bad\"}}" > "$BENCH_RESULT_JSON" ;;
  4) printf "{\"valid\":false}" > "$BENCH_RESULT_JSON" ;;
esac'

  run_bench --runs 4 --quiet ./mixed.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  total=$(jq -r '[.validity[]] | add' "$json")
  [ "$total" = "$(jq -r '.runs_completed' "$json")" ]
}

@test "each failure class is reported distinctly" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script mixed.sh '#!/bin/sh
case "$BENCH_RUN_NUMBER" in
  1) printf "{\"metrics\":{\"e\":0}}" > "$BENCH_RESULT_JSON" ;;
  2) exit 1 ;;
  3) printf "{\"metrics\":{\"e\":\"bad\"}}" > "$BENCH_RESULT_JSON" ;;
  4) printf "{\"valid\":false}" > "$BENCH_RESULT_JSON" ;;
esac'

  run_bench --runs 4 --quiet ./mixed.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.validity.ok' "$json")" = "1" ]
  [ "$(jq -r '.validity.command_failed' "$json")" = "1" ]
  [ "$(jq -r '.validity.invalid_result' "$json")" = "1" ]
  [ "$(jq -r '.validity.declared_invalid' "$json")" = "1" ]
}

@test "runs_valid and runs_invalid partition the completed runs" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script half.sh '#!/bin/sh
[ "$BENCH_RUN_NUMBER" -le 2 ] || exit 1'

  run_bench --runs 4 --quiet ./half.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.runs_valid' "$json")" = "2" ]
  [ "$(jq -r '.runs_invalid' "$json")" = "2" ]
  [ "$(jq -r '.valid_rate' "$json")" = "50.00" ]
}

@test "validity is distinct from exit-code success" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  emitter
  make_script grade.sh '#!/bin/sh
printf "{\"valid\":false}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 2 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  # Every run exited 0 ...
  [ "$(jq -r '.runs_successful' "$json")" = "2" ]
  [ "$(jq -r '.success_rate' "$json")" = "100.00" ]
  # ... and none of them is valid
  [ "$(jq -r '.runs_valid' "$json")" = "0" ]
  [ "$(jq -r '.valid_rate' "$json")" = "0" ]
}

@test "every run carries a status, a valid flag and an error field" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 2 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '[.runs[] | has("status")] | all' "$json")" = "true" ]
  [ "$(jq -r '[.runs[] | has("valid")] | all' "$json")" = "true" ]
  [ "$(jq -r '[.runs[] | has("error")] | all' "$json")" = "true" ]
}

@test "a valid run has an empty error field" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(run_error 1)" = "" ]
}

@test "error text containing quotes and backslashes stays valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  # JSON::PP renders the offending input in its message, which puts both
  # quotes and backslash escapes into the recorded error
  make_emitter emit.sh '{"broken'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  assert_valid_json "$(bench_json)"
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "benchmarks without evaluation keep working unchanged" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 3 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.runs_valid' "$json")" = "3" ]
  [ "$(jq -r '.validity.ok' "$json")" = "3" ]
  [ "$(jq -r '.evaluator' "$json")" = "" ]
}
