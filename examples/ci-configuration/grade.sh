#!/bin/sh
# Evaluator: a configuration is only faster if it ran the same tests.
#
# This is the failure this example exists to catch: sharding that goes faster
# by quietly skipping the slow tests is not a faster pipeline.
run_dir="$1"
results="$run_dir/artifacts/results.txt"
expected=$(wc -l < expected-tests.txt)
actual=$(grep -cE '^(PASS|FAIL)' "$results" || true)

if [ "$actual" -ne "$expected" ]; then
  echo "ran $actual tests, expected $expected -- coverage was lost" >&2
  printf '{"valid":false,"metrics":{"tests_run":%s}}' "$actual" > "$BENCH_RESULT_JSON"
  exit 0
fi
printf '{"valid":true,"metrics":{"tests_run":%s}}' "$actual" > "$BENCH_RESULT_JSON"
