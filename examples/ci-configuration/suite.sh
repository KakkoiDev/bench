#!/bin/sh
# A stand-in test suite: some tests are slow, all of them must run.
shards="${1:-1}"
skip_slow="${2:-0}"
while IFS= read -r t; do
  case "$t" in
    slow-*)
      [ "$skip_slow" = "1" ] && continue
      sleep 0.05
      ;;
  esac
  echo "PASS $t"
done < expected-tests.txt
# Sharding only affects how long it takes, not what runs
[ "$shards" -gt 1 ] && exit 0
exit 0
