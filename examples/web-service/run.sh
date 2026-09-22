#!/bin/sh
# Subject: issue a batch of requests against a local service.
: "${REQUESTS:=20}"
: "${PORT:=8099}"
ok=0; failed=0
start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')
i=1
while [ "$i" -le "$REQUESTS" ]; do
  if curl -fsS "http://localhost:$PORT/" -o "$BENCH_ARTIFACTS/last.html" 2>/dev/null; then
    ok=$((ok + 1))
  else
    failed=$((failed + 1))
  fi
  i=$((i + 1))
done
end=$(perl -MTime::HiRes=time -e 'printf "%.6f", time()')

cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"requests": $REQUESTS, "failed": $failed,
             "ms_per_request": $(echo "scale=4; ($end - $start) * 1000 / $REQUESTS" | bc)},
 "units": {"ms_per_request": "ms"},
 "artifacts": ["artifacts/last.html"]}
JSON
