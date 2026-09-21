#!/usr/bin/env bats
# Phase 1 Tests - Stable evidence format (schema 2.1)
#
# Covers the protocol by which a benchmarked command emits its own
# measurements, artifacts and evidence, and how bench validates, preserves
# and aggregates them.

load helpers

setup_file() {
  :
}

# =============================================================================
# Run directory and environment
# =============================================================================

@test "BENCH_RUN_DIR is exported and exists" {
  cd "$TEST_TEMP_DIR"
  make_script probe.sh '#!/bin/sh
[ -d "$BENCH_RUN_DIR" ] || exit 1
echo "$BENCH_RUN_DIR" > dir.txt'

  run_bench --runs 1 --quiet ./probe.sh
  [ "$status" -eq 0 ]
  [ -d "$(cat "$TEST_TEMP_DIR/dir.txt")" ]
}

@test "BENCH_ARTIFACTS points at an existing directory" {
  cd "$TEST_TEMP_DIR"
  make_script probe.sh '#!/bin/sh
[ -d "$BENCH_ARTIFACTS" ] || exit 1'

  run_bench --runs 1 --quiet ./probe.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "BENCH_RUN_NUMBER increments across runs" {
  cd "$TEST_TEMP_DIR"
  make_script probe.sh '#!/bin/sh
echo "$BENCH_RUN_NUMBER" >> seen.txt'

  run_bench --runs 3 --quiet ./probe.sh
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' < "$TEST_TEMP_DIR/seen.txt")" = "1 2 3 " ]
}

@test "BENCH_RUNS reports the total run count" {
  cd "$TEST_TEMP_DIR"
  make_script probe.sh '#!/bin/sh
echo "$BENCH_RUNS" > total.txt'

  run_bench --runs 4 --quiet ./probe.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/total.txt")" = "4" ]
}

@test "each run gets its own evidence directory" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 3 --quiet "true"
  [ "$status" -eq 0 ]

  d=$(run_dir)
  [ -d "$d/runs/1" ]
  [ -d "$d/runs/2" ]
  [ -d "$d/runs/3" ]
}

@test "evidence directory coexists with the schema 2.0 flat files" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo out"
  [ "$status" -eq 0 ]

  d=$(run_dir)
  [ -f "$d/runs/1.log" ]
  [ -f "$d/runs/1.stdout" ]
  [ -f "$d/runs/1.stderr" ]
  [ -d "$d/runs/1" ]
}

# =============================================================================
# Metric ingestion
# =============================================================================

@test "metrics from result.json reach the aggregate" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"accuracy":0.94}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.accuracy.mean' "$(bench_json)")" = "0.94" ]
}

@test "metrics from metrics.jsonl reach the aggregate" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"tokens","value":1420,"unit":"token"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.tokens.mean' "$(bench_json)")" = "1420" ]
  [ "$(jq -r '.metrics.tokens.unit' "$(bench_json)")" = "token" ]
}

@test "result.json and metrics.jsonl combine in one run" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
printf "{\"metrics\":{\"a\":1}}" > "$BENCH_RESULT_JSON"
printf "{\"type\":\"metric\",\"name\":\"b\",\"value\":2}\n" > "$BENCH_METRICS"'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.a.mean' "$(bench_json)")" = "1" ]
  [ "$(jq -r '.metrics.b.mean' "$(bench_json)")" = "2" ]
}

@test "a command emitting nothing still succeeds with no metrics" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 2 --quiet "echo plain"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics | length' "$(bench_json)")" = "0" ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the doc's JSON Lines example is accepted verbatim" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"tokens","value":1420,"unit":"token"}
{"type":"metric","name":"accuracy","value":0.94}
{"type":"artifact","path":"patch.diff"}
{"type":"evidence","path":"test-report.xml"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
  [ "$(jq -r '.metrics.tokens.mean' "$(bench_json)")" = "1420" ]
  [ "$(jq -r '.runs[0].evidence.artifacts[0]' "$(bench_json)")" = "patch.diff" ]
  [ "$(jq -r '.runs[0].evidence.evidence[0]' "$(bench_json)")" = "test-report.xml" ]
}

@test "the doc's result object example is accepted verbatim" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{
  "metrics": {
    "accuracy": 0.94,
    "tokens": 1842,
    "tests_passed": 37,
    "tests_total": 40,
    "human_review_seconds": 52
  },
  "artifacts": ["report.json", "patch.diff"],
  "valid": true
}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics | length' "$(bench_json)")" = "5" ]
  [ "$(jq -r '.metrics.tests_passed.mean' "$(bench_json)")" = "37" ]
  [ "$(jq -r '.runs[0].evidence.artifacts | length' "$(bench_json)")" = "2" ]
}

@test "integer metrics stay integers" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"count":42}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.count.mean' "$(bench_json)")" = "42" ]
}

@test "negative and zero metric values are accepted" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"delta":-3.5,"zero":0}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
  [ "$(jq -r '.metrics.delta.mean' "$(bench_json)")" = "-3.5" ]
  [ "$(jq -r '.metrics.zero.mean' "$(bench_json)")" = "0" ]
}

@test "scientific notation is accepted" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"tiny":1.5e-3}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
  [ "$(jq -r '.metrics.tiny.mean' "$(bench_json)")" = "0.0015" ]
}

@test "a repeated metric in the stream takes its last value" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"a","value":1}
{"type":"metric","name":"a","value":9}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.a.mean' "$(bench_json)")" = "9" ]
  [ "$(jq -r '.metrics.a.count' "$(bench_json)")" = "1" ]
}

@test "blank lines in the stream are ignored" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '

{"type":"metric","name":"a","value":1}

'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

# =============================================================================
# Raw measurements and aggregation
# =============================================================================

@test "raw per-run values are preserved alongside aggregates" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":%s}}" "$BENCH_RUN_NUMBER" > "$BENCH_RESULT_JSON"'

  run_bench --runs 4 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -c '.metrics.v.values' "$(bench_json)")" = "[1,2,3,4]" ]
  [ "$(jq -r '.metrics.v.count' "$(bench_json)")" = "4" ]
}

@test "each value records the run it came from" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
printf "{\"metrics\":{\"v\":%s}}" "$BENCH_RUN_NUMBER" > "$BENCH_RESULT_JSON"'

  run_bench --runs 3 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -c '.metrics.v.runs' "$(bench_json)")" = "[1,2,3]" ]
}

@test "aggregate statistics are correct for known values" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  # Emits 2, 4, 4, 4, 5, 5, 7, 9 -> mean 5, median 4.5, sample stddev 2.138090
  make_script emit.sh '#!/bin/sh
set -- 2 4 4 4 5 5 7 9
eval "v=\${$BENCH_RUN_NUMBER}"
printf "{\"metrics\":{\"v\":%s}}" "$v" > "$BENCH_RESULT_JSON"'

  run_bench --runs 8 --quiet ./emit.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.metrics.v.count' "$json")" = "8" ]
  [ "$(jq -r '.metrics.v.min' "$json")" = "2" ]
  [ "$(jq -r '.metrics.v.max' "$json")" = "9" ]
  [ "$(jq -r '.metrics.v.mean' "$json")" = "5" ]
  [ "$(jq -r '.metrics.v.median' "$json")" = "4.5" ]
  [ "$(jq -r '.metrics.v.stddev' "$json")" = "2.13809" ]
}

@test "median of an odd sample is the middle value" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
set -- 10 1 5
eval "v=\${$BENCH_RUN_NUMBER}"
printf "{\"metrics\":{\"v\":%s}}" "$v" > "$BENCH_RESULT_JSON"'

  run_bench --runs 3 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.v.median' "$(bench_json)")" = "5" ]
}

@test "stddev is zero for a single observation" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"v":7}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.v.stddev' "$(bench_json)")" = "0" ]
}

@test "outliers are kept, not trimmed" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
set -- 1 1 1 1000
eval "v=\${$BENCH_RUN_NUMBER}"
printf "{\"metrics\":{\"v\":%s}}" "$v" > "$BENCH_RESULT_JSON"'

  run_bench --runs 4 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.v.max' "$(bench_json)")" = "1000" ]
  [ "$(jq -c '.metrics.v.values' "$(bench_json)")" = "[1,1,1,1000]" ]
}

@test "metrics from a failed run are still recorded" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
printf "{\"metrics\":{\"partial\":5}}" > "$BENCH_RESULT_JSON"
exit 1'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "command_failed" ]
  # The measurement survives even though the run is invalid
  [ "$(jq -r '.metrics.partial.mean' "$(bench_json)")" = "5" ]
}

# =============================================================================
# Validation
# =============================================================================

@test "a non-numeric metric value is rejected" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"bad":"not-a-number"}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "the validation error names the offending metric" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"accuracy":"high"}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  echo "$(run_error 1)" | grep -q "accuracy"
  echo "$(run_error 1)" | grep -q "finite number"
}

@test "Infinity is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"huge":1e999}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a boolean metric value is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"flag":true}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a null metric value is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"missing":null}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a metric name starting with a digit is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"2fast":1}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a metric name containing a space is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"two words":1}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "dots, dashes and underscores are allowed in metric names" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"http.p95_latency-ms":12}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
  [ "$(jq -r '.metrics["http.p95_latency-ms"].mean' "$(bench_json)")" = "12" ]
}

@test "malformed JSON in result.json is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{not json'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -qi "invalid json"
}

@test "a non-object top level in result.json is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '[1,2,3]'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a metrics field that is not an object is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":[1,2]}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "a malformed stream line is rejected with its line number" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"a","value":1}
this is not json'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "line 2"
}

@test "an unknown stream event type is rejected" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"teleport","name":"a"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "unknown event type"
}

@test "a stream event without a type is rejected" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"name":"a","value":1}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

@test "changing a metric's unit within a run is rejected" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"t","value":1,"unit":"token"}
{"type":"metric","name":"t","value":2,"unit":"count"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "changed unit"
}

@test "a unit conflict across runs fails the benchmark" {
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
if [ "$BENCH_RUN_NUMBER" = "1" ]; then u=ms; else u=s; fi
printf "{\"type\":\"metric\",\"name\":\"latency\",\"value\":1,\"unit\":\"%s\"}\n" "$u" > "$BENCH_METRICS"'

  run_bench --runs 2 --quiet ./emit.sh
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "inconsistent units"
}

@test "several validation errors are reported together" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"bogus"}
{"type":"metric","name":"2bad","value":1}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "unknown event type"
  echo "$(run_error 1)" | grep -q "2bad"
}

@test "an invalid unit is rejected" {
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"metric","name":"a","value":1,"unit":"this unit has spaces"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
}

# =============================================================================
# Artifacts and evidence
# =============================================================================

@test "artifacts declared in result.json are registered" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
echo body > "$BENCH_ARTIFACTS/out.txt"
printf "{\"artifacts\":[\"artifacts/out.txt\"]}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs[0].evidence.artifacts[0]' "$(bench_json)")" = "artifacts/out.txt" ]
}

@test "artifacts written to BENCH_ARTIFACTS persist in the run directory" {
  cd "$TEST_TEMP_DIR"
  make_script emit.sh '#!/bin/sh
echo "the payload" > "$BENCH_ARTIFACTS/out.txt"'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$(run_dir)/runs/1/artifacts/out.txt")" = "the payload" ]
}

@test "evidence paths are recorded separately from artifacts" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"artifact","path":"a.diff"}
{"type":"evidence","path":"report.xml"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -c '.runs[0].evidence.artifacts' "$(bench_json)")" = '["a.diff"]' ]
  [ "$(jq -c '.runs[0].evidence.evidence' "$(bench_json)")" = '["report.xml"]' ]
}

@test "an absolute artifact path is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"artifacts":["/etc/passwd"]}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "relative"
}

@test "an artifact path escaping the run directory is rejected" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"artifacts":["../../escape"]}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "invalid_result" ]
  echo "$(run_error 1)" | grep -q "escape"
}

@test "a duplicate artifact path is registered once" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_streamer emit.sh '{"type":"artifact","path":"a.diff"}
{"type":"artifact","path":"a.diff"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.runs[0].evidence.artifacts | length' "$(bench_json)")" = "1" ]
}

# =============================================================================
# Self-describing results
# =============================================================================

@test "each run writes a self-describing metrics.json" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]

  m="$(run_dir)/runs/1/metrics.json"
  assert_valid_json "$m"
  [ "$(jq -r '.schema_version' "$m")" = "2.1" ]
  [ "$(jq -r '.metrics.a' "$m")" = "1" ]
}

@test "the command's original result.json is kept verbatim" {
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1},"customField":"kept"}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]
  grep -q "customField" "$(run_dir)/runs/1/result.json"
}

@test "unknown result fields are preserved under source" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1},"futureField":{"nested":[1,2]}}'

  run_bench --runs 1 --quiet ./emit.sh
  [ "$status" -eq 0 ]

  m="$(run_dir)/runs/1/metrics.json"
  [ "$(jq -c '.source.futureField.nested' "$m")" = "[1,2]" ]
}

@test "results are readable without bench using jq alone" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"score":0.5}}'

  run_bench --runs 2 --quiet ./emit.sh
  [ "$status" -eq 0 ]

  # The acceptance criterion: everything needed is plain JSON on disk
  [ "$(jq -r '.metrics.score.mean' "$(bench_json)")" = "0.5" ]
  [ "$(jq -r '.metrics' "$(run_dir)/runs/1/metrics.json" | jq -r '.score')" = "0.5" ]
}

# =============================================================================
# Backward compatibility with schema 2.0
# =============================================================================

@test "schema version is 2.1" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.schema_version' "$(bench_json)")" = "2.1" ]
}

@test "every schema 2.0 top-level field is still present" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 2 --quiet --name "compat" --message "m" "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  for field in schema_version tool tool_version name message command \
               runs_requested runs_completed runs_successful runs_failed \
               success_rate interrupted timing environment runs; do
    [ "$(jq "has(\"$field\")" "$json")" = "true" ] || {
      echo "missing schema 2.0 field: $field"
      return 1
    }
  done
}

@test "the schema 2.0 timing object is unchanged" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 3 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  for field in unit min max mean median stddev p95 p99; do
    [ "$(jq ".timing | has(\"$field\")" "$json")" = "true" ] || {
      echo "missing timing field: $field"
      return 1
    }
  done
}

@test "schema 2.0 per-run fields are unchanged" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  for field in run_number exit_code start end duration_seconds duration_ms \
               stdout_bytes stderr_bytes; do
    [ "$(jq ".runs[0] | has(\"$field\")" "$json")" = "true" ] || {
      echo "missing run field: $field"
      return 1
    }
  done
}

@test "schema 2.0 process monitoring output is unchanged" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  create_mock_process 30

  run_bench --runs 1 --quiet --pid "app:$MOCK_PID" "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.processes[0].name' "$json")" = "app" ]
  for field in unit mean min max initial final delta; do
    [ "$(jq ".processes[0].memory | has(\"$field\")" "$json")" = "true" ] || {
      echo "missing memory field: $field"
      return 1
    }
  done

  kill_mock_process "$MOCK_PID"
}

@test "a plain benchmark with no evidence is still valid JSON" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 3 --quiet "echo test"
  [ "$status" -eq 0 ]
  assert_valid_json "$(bench_json)"
}

@test "evidence output does not break JSON escaping" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1}}'

  run_bench --runs 1 --quiet --message 'has "quotes" and \backslash' ./emit.sh
  [ "$status" -eq 0 ]
  assert_valid_json "$(bench_json)"
  [ "$(jq -r '.message' "$(bench_json)")" = 'has "quotes" and \backslash' ]
}

# =============================================================================
# Incomplete runs
# =============================================================================

@test "a completed run carries no INCOMPLETE marker" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 2 --quiet "echo test"
  [ "$status" -eq 0 ]

  [ ! -f "$(run_dir)/runs/1/INCOMPLETE" ]
  [ ! -f "$(run_dir)/runs/2/INCOMPLETE" ]
}

@test "an interrupted run is left visibly incomplete" {
  cd "$TEST_TEMP_DIR"

  "$BENCH_SCRIPT" --runs 20 --quiet "sleep 1" > "$TEST_TEMP_DIR/path.txt" 2>&1 &
  bench_pid=$!

  sleep 3
  kill -TERM "$bench_pid" 2>/dev/null
  wait "$bench_pid" 2>/dev/null || true
  sleep 1

  d=$(cat "$TEST_TEMP_DIR/path.txt")
  [ -d "$d" ]

  # The run that was in flight when the signal arrived is marked, and is not
  # counted among the recorded runs
  marked=$(find "$d/runs" -name INCOMPLETE | wc -l)
  [ "$marked" -eq 1 ]

  recorded=$(jq -r '.runs | length' "$d/benchmark.json")
  dirs=$(find "$d/runs" -maxdepth 1 -mindepth 1 -type d | wc -l)
  [ "$dirs" -eq "$((recorded + 1))" ]
}

@test "an interrupted benchmark does not count the partial run as valid" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  "$BENCH_SCRIPT" --runs 20 --quiet "sleep 1" > "$TEST_TEMP_DIR/path.txt" 2>&1 &
  bench_pid=$!

  sleep 3
  kill -TERM "$bench_pid" 2>/dev/null
  wait "$bench_pid" 2>/dev/null || true
  sleep 1

  d=$(cat "$TEST_TEMP_DIR/path.txt")
  json="$d/benchmark.json"
  assert_valid_json "$json"
  [ "$(jq -r '.interrupted' "$json")" = "true" ]
  [ "$(jq -r '.runs_valid' "$json")" = "$(jq -r '.runs_completed' "$json")" ]
}
