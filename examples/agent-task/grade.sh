#!/bin/sh
# Evaluator: run held-out tests the agent never saw.
run_dir="$1"
sol="$run_dir/artifacts/solution.sh"
[ -x "$sol" ] || { echo "no solution produced" >&2; exit 1; }

"$sol" 30 > "$run_dir/artifacts/actual.txt" 2>/dev/null
if diff -q held-out-expected.txt "$run_dir/artifacts/actual.txt" >/dev/null 2>&1; then
  passed=1
else
  passed=0
fi
failures=$(diff held-out-expected.txt "$run_dir/artifacts/actual.txt" 2>/dev/null | grep -c '^<' || true)

cat > "$BENCH_RESULT_JSON" <<JSON
{"valid": $( [ "$passed" -eq 1 ] && echo true || echo false ),
 "metrics": {"tests_failed": $failures},
 "artifacts": ["artifacts/actual.txt"]}
JSON
