#!/usr/bin/env bats
# Phase 6 Tests - Domain demonstrations
#
# The examples are the cross-domain evidence, so they are executed rather than
# assumed to work. Each is copied into the test temp directory so a run never
# writes into the repository.

load helpers

# Copy one example into the test temp dir and cd there
use_example() {
  cp -R "$ORIGINAL_DIR/examples/$1" "$TEST_TEMP_DIR/ex"
  cd "$TEST_TEMP_DIR/ex"
}

@test "every example ships a manifest, a subject and an evaluator" {
  cd "$ORIGINAL_DIR/examples"
  for d in */; do
    [ "$d" = "./" ] && continue
    [ -f "$d/experiment.yaml" ] || { echo "$d has no experiment.yaml"; return 1; }
    [ -f "$d/run.sh" ]         || { echo "$d has no run.sh"; return 1; }
    [ -f "$d/grade.sh" ]       || { echo "$d has no grade.sh"; return 1; }
  done
}

@test "every example manifest validates" {
  cd "$ORIGINAL_DIR/examples"
  for d in */; do
    run "$BENCH_SCRIPT" validate "$d/experiment.yaml"
    [ "$status" -eq 0 ] || { echo "$d: $output"; return 1; }
  done
}

@test "every example is listed in the examples README" {
  cd "$ORIGINAL_DIR/examples"
  for d in */; do
    name="${d%/}"
    grep -q "$name" README.md || { echo "$name is not described in README.md"; return 1; }
  done
}

@test "command-performance runs and validates its output ordering" {
  require_command jq
  use_example command-performance

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 2
  [ "$status" -eq 0 ]
  root="$output"

  for v in baseline parallel; do
    [ "$(jq -r '.runs_valid' "$root/variants/$v/benchmark.json")" = "2" ]
  done
}

@test "algorithm-tuning finds the exact solver at least as good as greedy" {
  require_command jq
  use_example algorithm-tuning

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 2
  [ "$status" -eq 0 ]
  root="$output"

  greedy=$(jq -r '.metrics.value.mean' "$root/variants/greedy/benchmark.json")
  exact=$(jq -r '.metrics.value.mean' "$root/variants/exact/benchmark.json")
  awk -v g="$greedy" -v e="$exact" 'BEGIN { exit (e >= g) ? 0 : 1 }'
}

@test "agent-task: a self-declared success is rejected by the held-out tests" {
  # This is the claim the whole protocol exists for. The overconfident variant
  # writes "valid": true and still scores zero valid runs.
  require_command jq
  use_example agent-task

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 3
  [ "$status" -eq 0 ]
  root="$output"

  honest="$root/variants/honest/benchmark.json"
  over="$root/variants/overconfident/benchmark.json"

  [ "$(jq -r '.runs_valid' "$honest")" = "3" ]
  [ "$(jq -r '.runs_valid' "$over")" = "0" ]

  # Both claimed success ...
  [ "$(jq -r '.runs[0].evidence.declared_valid' "$over")" = "true" ]
  # ... and both exited zero ...
  [ "$(jq -r '.runs_successful' "$over")" = "3" ]
  # ... but only one passed independent evaluation
  [ "$(jq -r '.runs[0].status' "$over")" = "evaluator_failed" ]
}

@test "ci-configuration: a faster pipeline that skips tests is rejected" {
  require_command jq
  use_example ci-configuration

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 2
  [ "$status" -eq 0 ]
  root="$output"

  honest="$root/variants/honest/benchmark.json"
  skipping="$root/variants/skips-slow-tests/benchmark.json"

  [ "$(jq -r '.runs_valid' "$honest")" = "2" ]
  [ "$(jq -r '.runs_valid' "$skipping")" = "0" ]

  # The skipping variant really was faster -- and still invalid
  fast=$(jq -r '.metrics.wall_ms.mean' "$skipping")
  slow=$(jq -r '.metrics.wall_ms.mean' "$honest")
  awk -v f="$fast" -v s="$slow" 'BEGIN { exit (f < s) ? 0 : 1 }'
}

@test "web-service runs with lifecycle hooks managing the server" {
  require_command jq
  require_command python3
  require_command curl
  use_example web-service

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 2
  [ "$status" -eq 0 ]
  root="$output"

  for v in light heavy; do
    [ "$(jq -r '.runs_valid' "$root/variants/$v/benchmark.json")" = "2" ]
  done

  # The cleanup hook stopped the server it started
  [ ! -f .server.pid ]
}

@test "an example's variants can be compared" {
  require_command jq
  use_example algorithm-tuning

  run "$BENCH_SCRIPT" run experiment.yaml --quiet --runs 3
  [ "$status" -eq 0 ]
  root="$output"

  run "$BENCH_SCRIPT" compare "$root/variants/greedy" "$root/variants/exact" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.metrics.value' >/dev/null
}

@test "no example required a change to bench itself" {
  # Each example uses only the documented environment contract
  cd "$ORIGINAL_DIR/examples"
  for f in */run.sh */grade.sh; do
    # Every BENCH_ variable an example uses must be documented in PROTOCOL.md
    for var in $(grep -oE 'BENCH_[A-Z_]+' "$f" | sort -u); do
      grep -q "$var" "$ORIGINAL_DIR/PROTOCOL.md" || {
        echo "$f uses $var, which PROTOCOL.md does not document"
        return 1
      }
    done
  done
}
