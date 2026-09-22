#!/bin/sh
# Evaluator: a 200 with an error page in the body is still a failure.
run_dir="$1"
body="$run_dir/artifacts/last.html"
if [ ! -s "$body" ]; then
  printf '{"valid":false}' > "$BENCH_RESULT_JSON"
  echo "empty response body" >&2
  exit 0
fi
if grep -qiE '(internal server error|traceback|exception)' "$body"; then
  printf '{"valid":false}' > "$BENCH_RESULT_JSON"
  echo "error page returned with a success status" >&2
  exit 0
fi
printf '{"valid":true,"metrics":{"body_bytes":%s}}' "$(wc -c < "$body")" > "$BENCH_RESULT_JSON"
