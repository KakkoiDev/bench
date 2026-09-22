#!/bin/sh
# Evaluator: a higher-value solution that exceeds the capacity is not a
# better solution, it is an invalid one.
run_dir="$1"
sol="$run_dir/artifacts/solution.txt"
capacity="${CAPACITY:-100}"
weight=$(awk '/^weight /{print $2}' "$sol")

if [ "$weight" -gt "$capacity" ]; then
  echo "solution weighs $weight, over the capacity of $capacity" >&2
  printf '{"valid":false,"metrics":{"over_capacity":1}}' > "$BENCH_RESULT_JSON"
  exit 0
fi
printf '{"valid":true,"metrics":{"over_capacity":0}}' > "$BENCH_RESULT_JSON"
