#!/bin/sh
# Subject: run a test suite under the sharding the variant selects.
: "${SHARDS:=1}"
: "${SKIP_SLOW:=0}"
start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')
./suite.sh "$SHARDS" "$SKIP_SLOW" > "$BENCH_ARTIFACTS/results.txt" 2>&1
rc=$?
end=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')

passed=$(grep -c '^PASS' "$BENCH_ARTIFACTS/results.txt" || true)
failed=$(grep -c '^FAIL' "$BENCH_ARTIFACTS/results.txt" || true)
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"wall_ms": $(echo "($end - $start) * 1000" | bc),
             "tests_passed": $passed, "tests_failed": $failed},
 "units": {"wall_ms": "ms"},
 "artifacts": ["artifacts/results.txt"]}
JSON
exit $rc
