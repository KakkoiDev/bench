#!/bin/sh
# Evaluator: a faster sort that does not actually sort is not an improvement.
run_dir="$1"
out="$run_dir/artifacts/sorted.txt"
[ -f "$out" ] || { echo "no output produced" >&2; exit 1; }

if ! sort -c -k1,1n "$out" 2>/dev/null; then
  echo "output is not correctly ordered" >&2
  printf '{"valid":false}' > "$BENCH_RESULT_JSON"
  exit 0
fi
printf '{"valid":true,"metrics":{"ordered":1}}' > "$BENCH_RESULT_JSON"
