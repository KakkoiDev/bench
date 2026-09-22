#!/usr/bin/env bats
# Phase 3 Tests - Manifests, variants and execution order

load helpers

manifest() {
  printf '%s\n' "$2" > "$TEST_TEMP_DIR/$1"
}

# A subject whose output depends on the variant's environment
variant_subject() {
  make_script work.sh '#!/bin/sh
if [ "$MODE" = "fast" ]; then L=10; else L=20; fi
printf "{\"metrics\":{\"latency_ms\":%s,\"errors\":0}}" "$L" > "$BENCH_RESULT_JSON"'
}

two_variant_manifest() {
  manifest exp.yaml 'schema_version: "1.0"
name: exp
command: ./work.sh
runs: 4
order: interleaved
seed: 7
variants:
  baseline:
    env:
      MODE: "slow"
  candidate:
    env:
      MODE: "fast"
metrics:
  latency_ms:
    goal: minimize
  errors:
    constraint: "== 0"'
}

# =============================================================================
# validate
# =============================================================================

@test "validate accepts the documented manifest" {
  cd "$TEST_TEMP_DIR"
  two_variant_manifest
  run "$BENCH_SCRIPT" validate exp.yaml
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "is valid"
  echo "$output" | grep -q "baseline"
}

@test "validate rejects a missing schema_version" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'command: ./x.sh'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "schema_version"
}

@test "validate rejects an unsupported schema_version" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "9.9"
command: ./x.sh'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
}

@test "validate rejects a missing command" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
name: x'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "command is required"
}

@test "validate rejects an unknown field rather than ignoring it" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
tyops: 1'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "tyops"
}

@test "validate rejects an unknown field inside a variant" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
variants:
  a:
    envv:
      X: "1"'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "envv"
}

@test "validate rejects an invalid metric goal" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
metrics:
  m:
    goal: sideways'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
}

@test "validate rejects a constraint that is not the permitted grammar" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
metrics:
  m:
    constraint: "rm -rf /"'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  [ ! -f /tmp/bench-should-not-exist ]
}

@test "validate rejects tabs used for indentation" {
  cd "$TEST_TEMP_DIR"
  printf 'schema_version: "1.0"\ncommand: ./x.sh\nvariants:\n\ta: 1\n' > tabs.yaml
  run "$BENCH_SCRIPT" validate tabs.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "tab"
}

@test "validate rejects flow collections, which the subset does not support" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
metrics: {a: 1}'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "flow"
}

@test "validate reports every problem, not just the first" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./x.sh
nope: 1
also: 2'
  run "$BENCH_SCRIPT" validate bad.yaml
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "nope"
  echo "$output" | grep -q "also"
}

@test "validate accepts a JSON manifest" {
  cd "$TEST_TEMP_DIR"
  printf '{"schema_version":"1.0","command":"./x.sh","runs":3}' > m.json
  run "$BENCH_SCRIPT" validate m.json
  [ "$status" -eq 0 ]
}

@test "validate requires a manifest path" {
  run "$BENCH_SCRIPT" validate
  [ "$status" -eq 1 ]
}

# =============================================================================
# run
# =============================================================================

@test "a manifest runs every variant" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  two_variant_manifest

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  root="$output"

  [ -f "$root/experiment.json" ]
  [ -f "$root/variants/baseline/benchmark.json" ]
  [ -f "$root/variants/candidate/benchmark.json" ]
}

@test "each variant's environment reaches its command" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  two_variant_manifest

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  root="$output"

  [ "$(jq -r '.metrics.latency_ms.mean' "$root/variants/baseline/benchmark.json")" = "20" ]
  [ "$(jq -r '.metrics.latency_ms.mean' "$root/variants/candidate/benchmark.json")" = "10" ]
}

@test "variant environments do not leak between variants" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script work.sh '#!/bin/sh
printf "{\"metrics\":{\"seen\":%s}}" "$( [ -n "$ONLY_A" ] && echo 1 || echo 0 )" > "$BENCH_RESULT_JSON"'
  manifest exp.yaml 'schema_version: "1.0"
name: leak
command: ./work.sh
runs: 3
variants:
  a:
    env:
      ONLY_A: "yes"
  b: {}'
  # b has no env at all; an empty mapping is written the long way below
  manifest exp.yaml 'schema_version: "1.0"
name: leak
command: ./work.sh
runs: 3
variants:
  a:
    env:
      ONLY_A: "yes"
  b:
    env:
      OTHER: "1"'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  root="$output"
  [ "$(jq -r '.metrics.seen.mean' "$root/variants/a/benchmark.json")" = "1" ]
  [ "$(jq -r '.metrics.seen.mean' "$root/variants/b/benchmark.json")" = "0" ]
}

@test "each variant result is a standalone benchmark.json" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  two_variant_manifest

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  json="$output/variants/baseline/benchmark.json"

  assert_valid_json "$json"
  for field in schema_version timing runs runs_valid provenance metrics; do
    [ "$(jq "has(\"$field\")" "$json")" = "true" ]
  done
}

@test "the execution order and seed are recorded" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  two_variant_manifest

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  exp="$output/experiment.json"

  assert_valid_json "$exp"
  [ "$(jq -r '.order' "$exp")" = "interleaved" ]
  [ "$(jq -r '.seed' "$exp")" = "7" ]
  [ "$(jq -r '.execution_order | length' "$exp")" = "8" ]
}

@test "interleaved order does not run one variant to completion first" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  two_variant_manifest

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]

  # The first two entries must cover both variants
  first_two=$(jq -r '[.execution_order[0:2][].variant] | sort | join(",")' "$output/experiment.json")
  [ "$first_two" = "baseline,candidate" ]
}

@test "the same seed reproduces the same random order" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: r
command: ./work.sh
runs: 5
order: random
seed: 99
variants:
  a:
    env:
      MODE: "fast"
  b:
    env:
      MODE: "slow"'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  first=$(jq -c '[.execution_order[].variant]' "$output/experiment.json")

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  second=$(jq -c '[.execution_order[].variant]' "$output/experiment.json")

  [ "$first" = "$second" ]
}

@test "sequential order runs each variant to completion" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: s
command: ./work.sh
runs: 3
order: sequential
variants:
  a:
    env:
      MODE: "fast"
  b:
    env:
      MODE: "slow"'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.execution_order[0:3][].variant] | unique | length' "$output/experiment.json")" = "1" ]
}

@test "a manifest constraint is enforced like --require" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script work.sh '#!/bin/sh
printf "{\"metrics\":{\"errors\":3}}" > "$BENCH_RESULT_JSON"'
  manifest exp.yaml 'schema_version: "1.0"
name: c
command: ./work.sh
runs: 2
metrics:
  errors:
    constraint: "== 0"'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs[0].status' "$output/benchmark.json")" = "constraint_failed" ]
}

@test "warm-up runs are excluded from the recorded sample" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script work.sh '#!/bin/sh
echo x >> "'"$TEST_TEMP_DIR"'/invocations.txt"
printf "{\"metrics\":{\"a\":1}}" > "$BENCH_RESULT_JSON"'
  manifest exp.yaml 'schema_version: "1.0"
name: w
command: ./work.sh
runs: 3
warmup: 2'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]

  # Five invocations happened; three were measured
  [ "$(wc -l < "$TEST_TEMP_DIR/invocations.txt")" -eq 5 ]
  [ "$(jq -r '.runs_completed' "$output/benchmark.json")" = "3" ]
}

@test "setup and cleanup run once per variant when so scoped" {
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: lc
command: ./work.sh
setup: sh -c '"'"'echo setup >> lifecycle.txt'"'"'
setup_scope: variant
cleanup: sh -c '"'"'echo cleanup >> lifecycle.txt'"'"'
cleanup_scope: variant
runs: 3
variants:
  a:
    env:
      MODE: "fast"
  b:
    env:
      MODE: "slow"'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  [ "$(grep -c setup lifecycle.txt)" -eq 2 ]
  [ "$(grep -c cleanup lifecycle.txt)" -eq 2 ]
}

@test "a failing setup stops the experiment" {
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: bad-setup
command: ./work.sh
setup: sh -c '"'"'exit 1'"'"'
runs: 2'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "setup"
}

@test "a manifest without variants behaves like a plain benchmark" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: plain
command: ./work.sh
runs: 3'

  run "$BENCH_SCRIPT" run exp.yaml --quiet
  [ "$status" -eq 0 ]
  [ -f "$output/benchmark.json" ]
  [ ! -d "$output/variants" ]
  [ "$(jq -r '.runs_completed' "$output/benchmark.json")" = "3" ]
}

@test "flags after the manifest override it" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  variant_subject
  manifest exp.yaml 'schema_version: "1.0"
name: over
command: ./work.sh
runs: 9'

  run "$BENCH_SCRIPT" run exp.yaml --quiet --runs 2
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs_completed' "$output/benchmark.json")" = "2" ]
}

@test "run requires a manifest path" {
  run "$BENCH_SCRIPT" run
  [ "$status" -eq 1 ]
}

@test "an invalid manifest is refused before anything runs" {
  cd "$TEST_TEMP_DIR"
  manifest bad.yaml 'schema_version: "1.0"
command: ./work.sh
nope: 1'
  run "$BENCH_SCRIPT" run bad.yaml --quiet
  [ "$status" -eq 1 ]
  [ ! -d "$TEST_TEMP_DIR/bench-results" ]
}
