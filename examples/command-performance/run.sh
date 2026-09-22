#!/bin/sh
# Subject: sort a generated dataset with the algorithm the variant selects.
set -e
: "${SORT_FLAGS:=}"
seq 1 20000 | awk 'BEGIN{srand(7)} {print int(rand()*100000), $0}' > input.txt

start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')
# shellcheck disable=SC2086
sort $SORT_FLAGS -k1,1n input.txt > "$BENCH_ARTIFACTS/sorted.txt"
end=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')

lines=$(wc -l < "$BENCH_ARTIFACTS/sorted.txt")
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"sort_ms": $(echo "($end - $start) * 1000" | bc), "lines": $lines},
 "units": {"sort_ms": "ms"},
 "artifacts": ["artifacts/sorted.txt"]}
JSON
