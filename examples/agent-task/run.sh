#!/bin/sh
# Subject: a stand-in "agent" that attempts a coding task and reports on itself.
#
# The point of this example is that the subject's self-report is not trusted.
# The honest variant writes a correct implementation; the overconfident one
# writes a plausible but wrong implementation and still claims success.
: "${AGENT_MODE:=honest}"
mkdir -p "$BENCH_ARTIFACTS"

if [ "$AGENT_MODE" = "honest" ]; then
  cat > "$BENCH_ARTIFACTS/solution.sh" <<'SOLUTION'
#!/bin/sh
# fizzbuzz
i=1
while [ "$i" -le "$1" ]; do
  if [ $((i % 15)) -eq 0 ]; then echo FizzBuzz
  elif [ $((i % 3)) -eq 0 ]; then echo Fizz
  elif [ $((i % 5)) -eq 0 ]; then echo Buzz
  else echo "$i"; fi
  i=$((i + 1))
done
SOLUTION
else
  # Subtly wrong: the 15 case is missing, so multiples of 15 print "Fizz"
  cat > "$BENCH_ARTIFACTS/solution.sh" <<'SOLUTION'
#!/bin/sh
i=1
while [ "$i" -le "$1" ]; do
  if [ $((i % 3)) -eq 0 ]; then echo Fizz
  elif [ $((i % 5)) -eq 0 ]; then echo Buzz
  else echo "$i"; fi
  i=$((i + 1))
done
SOLUTION
fi
chmod +x "$BENCH_ARTIFACTS/solution.sh"

# Both variants declare success and report their own token spend. bench
# records the claim and ignores it; only grade.sh can establish validity.
cat > "$BENCH_RESULT_JSON" <<JSON
{"valid": true,
 "metrics": {"tokens": $(( 1200 + $(od -An -N1 -tu1 < /dev/urandom) )), "rounds": 2},
 "units": {"tokens": "token"},
 "artifacts": ["artifacts/solution.sh"]}
JSON
