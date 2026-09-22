#!/bin/sh
# Subject: a deterministic knapsack search under the strategy the variant picks.
: "${STRATEGY:=greedy}"
: "${CAPACITY:=100}"
start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')
./solve.pl "$STRATEGY" "$CAPACITY" items.txt > "$BENCH_ARTIFACTS/solution.txt"
end=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')

value=$(awk '/^value /{print $2}' "$BENCH_ARTIFACTS/solution.txt")
weight=$(awk '/^weight /{print $2}' "$BENCH_ARTIFACTS/solution.txt")
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"value": $value, "weight": $weight,
             "solve_ms": $(echo "($end - $start) * 1000" | bc)},
 "units": {"solve_ms": "ms"},
 "artifacts": ["artifacts/solution.txt"]}
JSON
