#!/usr/bin/env bats
# Phase 5 Tests - Provenance capture
#
# A result is only evidence if a reader can tell what produced it. These cover
# what is captured, what is deliberately not captured, and the fingerprint that
# makes a resumed run verifiable.

load helpers

@test "provenance is present in every result" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq 'has("provenance")' "$(bench_json)")" = "true" ]
}

@test "machine facts are captured" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ -n "$(jq -r '.provenance.machine.os' "$json")" ]
  [ -n "$(jq -r '.provenance.machine.arch' "$json")" ]
  [ -n "$(jq -r '.provenance.machine.kernel' "$json")" ]
}

@test "tool versions are captured" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ -n "$(jq -r '.provenance.tools.perl' "$json")" ]
  [ -n "$(jq -r '.provenance.tools.bc' "$json")" ]
}

# Helper: a git repository with one committed file
make_repo() {
  git init -q .
  git config user.email t@example.com
  git config user.name Test
  echo a > a.txt
  git add a.txt
  git commit -qm "first"
}

@test "the git commit is captured inside a repository" {
  require_command jq
  require_command git
  cd "$TEST_TEMP_DIR"
  make_repo

  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.git.commit' "$(bench_json)" | wc -c)" -gt 10 ]
}

@test "a modified tracked file makes the tree dirty" {
  require_command jq
  require_command git
  cd "$TEST_TEMP_DIR"
  make_repo
  echo modified >> a.txt

  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.git.dirty' "$(bench_json)")" = "true" ]
}

@test "bench's own results do not make the tree look dirty" {
  # Otherwise every resume would report dirty purely because the previous
  # sitting left its output on disk, which says nothing about the code.
  require_command jq
  require_command git
  cd "$TEST_TEMP_DIR"
  make_repo

  run_bench --runs 1 --quiet --name r "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.git.dirty' "$(bench_json)")" = "false" ]

  # A second benchmark, with the first one's results already on disk
  run_bench --runs 1 --quiet --name r2 "echo test"
  [ "$status" -eq 0 ]
  second=$(find "$TEST_TEMP_DIR/bench-results/r2" -name benchmark.json | head -1)
  [ "$(jq -r '.provenance.git.dirty' "$second")" = "false" ]
}

@test "git is omitted outside a repository" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq '.provenance | has("git")' "$(bench_json)")" = "false" ]
}

# =============================================================================
# Environment capture
# =============================================================================

@test "the environment is not dumped wholesale" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  export BENCH_TEST_UNLISTED=leak-me
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  ! grep -q "leak-me" "$(bench_json)"
  [ "$(jq -r '.provenance.environment.captured | has("BENCH_TEST_UNLISTED")' "$(bench_json)")" = "false" ]
}

@test "the count of omitted variables is recorded" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.environment.omitted_count' "$(bench_json)")" -gt 0 ]
}

@test "--capture-env records a named variable" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  export BENCH_TEST_REGION=tokyo
  run_bench --runs 1 --quiet --capture-env BENCH_TEST_REGION "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.environment.captured.BENCH_TEST_REGION' "$(bench_json)")" = "tokyo" ]
}

@test "credential-shaped variables are refused even when requested" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  export BENCH_TEST_API_KEY=supersecret
  run_bench --runs 1 --quiet --capture-env BENCH_TEST_API_KEY "echo test"
  [ "$status" -eq 0 ]

  json=$(bench_json)
  ! grep -q "supersecret" "$json"
  [ "$(jq -r '.provenance.environment.redacted[0]' "$json")" = "BENCH_TEST_API_KEY" ]
}

@test "every credential-shaped name pattern is refused" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  export T_TOKEN=a T_SECRET=b T_PASSWORD=c T_CREDENTIAL=d T_AUTH=e T_SESSION=f T_COOKIE=g
  run_bench --runs 1 --quiet \
    --capture-env T_TOKEN --capture-env T_SECRET --capture-env T_PASSWORD \
    --capture-env T_CREDENTIAL --capture-env T_AUTH --capture-env T_SESSION \
    --capture-env T_COOKIE "echo test"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.provenance.environment.redacted | length' "$(bench_json)")" -eq 7 ]
  [ "$(jq -r '.provenance.environment.captured | length' "$(bench_json)")" -lt 7 ]
}

@test "--capture-env rejects an invalid variable name" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --capture-env "not a name" "echo test"
  [ "$status" -eq 1 ]
}

@test "--capture-env requires an argument" {
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet --capture-env
  [ "$status" -eq 1 ]
}

# =============================================================================
# Configuration fingerprint
# =============================================================================

@test "the same configuration produces the same fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name a "echo test"
  [ "$status" -eq 0 ]
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/a" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name b "echo test"
  [ "$status" -eq 0 ]
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/b" -name benchmark.json | head -1)")

  [ "$first" = "$second" ]
}

@test "a different command produces a different fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name a "echo one"
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/a" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name b "echo two"
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/b" -name benchmark.json | head -1)")

  [ "$first" != "$second" ]
}

@test "cosmetic options do not change the fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  run_bench --runs 1 --quiet --name a --message "baseline" "echo test"
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/a" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name b --message "totally different note" "echo test"
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/b" -name benchmark.json | head -1)")

  # --name and --message describe the result, not the experiment
  [ "$first" = "$second" ]
}

@test "constraint order does not change the fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1,"b":2}}'

  run_bench --runs 1 --quiet --name x --require "a == 1" --require "b == 2" ./emit.sh
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/x" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name y --require "b == 2" --require "a == 1" ./emit.sh
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/y" -name benchmark.json | head -1)")

  [ "$first" = "$second" ]
}

@test "a changed constraint does change the fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"a":1}}'

  run_bench --runs 1 --quiet --name x --require "a == 1" ./emit.sh
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/x" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name y --require "a >= 1" ./emit.sh
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/y" -name benchmark.json | head -1)")

  [ "$first" != "$second" ]
}

@test "the evaluator is part of the fingerprint" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script grade.sh '#!/bin/sh
exit 0'

  run_bench --runs 1 --quiet --name x "echo test"
  first=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/x" -name benchmark.json | head -1)")

  run_bench --runs 1 --quiet --name y --evaluate ./grade.sh "echo test"
  second=$(jq -r '.provenance.config_fingerprint' "$(find "$TEST_TEMP_DIR/bench-results/y" -name benchmark.json | head -1)")

  [ "$first" != "$second" ]
}

# =============================================================================
# Valid-only aggregates
# =============================================================================

@test "metrics report a valid-only summary alongside the full one" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script t.sh '#!/bin/sh
printf "{\"metrics\":{\"tokens\":1000}}" > "$BENCH_RESULT_JSON"
[ "$BENCH_RUN_NUMBER" = "3" ] && exit 1
exit 0'

  run_bench --runs 3 --quiet ./t.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  # All three runs burned tokens ...
  [ "$(jq -r '.metrics.tokens.count' "$json")" = "3" ]
  # ... but only two produced a verified result
  [ "$(jq -r '.metrics.tokens.valid_only.count' "$json")" = "2" ]
}

@test "the valid-only summary excludes invalid observations" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script t.sh '#!/bin/sh
if [ "$BENCH_RUN_NUMBER" = "2" ]; then
  printf "{\"metrics\":{\"cost\":100}}" > "$BENCH_RESULT_JSON"
  exit 1
fi
printf "{\"metrics\":{\"cost\":10}}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 3 --quiet ./t.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.metrics.cost.mean' "$json")" = "40" ]
  [ "$(jq -r '.metrics.cost.valid_only.mean' "$json")" = "10" ]
}

@test "a metric seen only in invalid runs reports a zero valid-only count" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_script t.sh '#!/bin/sh
printf "{\"metrics\":{\"wasted\":5}}" > "$BENCH_RESULT_JSON"
exit 1'

  run_bench --runs 2 --quiet ./t.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.wasted.valid_only.count' "$(bench_json)")" = "0" ]
}

# =============================================================================
# PROTOCOL.md conformance
#
# The protocol document is the deliverable an adapter author works from, so it
# is tested rather than trusted.
# =============================================================================

@test "every environment variable PROTOCOL.md documents is exported" {
  cd "$TEST_TEMP_DIR"
  make_script probe.sh '#!/bin/sh
for v in BENCH_RUN_DIR BENCH_RESULT_JSON BENCH_METRICS BENCH_ARTIFACTS \
         BENCH_RUN_NUMBER BENCH_RUNS; do
  eval "val=\$$v"
  [ -n "$val" ] || { echo "$v is unset" >&2; exit 1; }
done'

  run_bench --runs 1 --quiet ./probe.sh
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "every evaluator variable PROTOCOL.md documents is exported" {
  cd "$TEST_TEMP_DIR"
  make_script grade.sh '#!/bin/sh
for v in BENCH_EXIT_CODE BENCH_STDOUT BENCH_STDERR BENCH_RUN_DIR; do
  eval "val=\$$v"
  [ -n "$val" ] || { echo "$v is unset" >&2; exit 1; }
done
[ -f "$BENCH_STDOUT" ] || exit 1
[ -f "$BENCH_STDERR" ] || exit 1'

  run_bench --runs 1 --quiet --evaluate ./grade.sh "echo test"
  [ "$status" -eq 0 ]
  [ "$(run_status 1)" = "ok" ]
}

@test "the evaluator's result path is separate from the subject's" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  make_emitter emit.sh '{"metrics":{"subject":1}}'
  make_script grade.sh '#!/bin/sh
printf "{\"metrics\":{\"grader\":2}}" > "$BENCH_RESULT_JSON"'

  run_bench --runs 1 --quiet --evaluate ./grade.sh ./emit.sh
  [ "$status" -eq 0 ]

  # Neither overwrote the other
  [ "$(jq -r '.metrics.subject.mean' "$(bench_json)")" = "1" ]
  [ "$(jq -r '.metrics.grader.mean' "$(bench_json)")" = "2" ]
  grep -q subject "$(run_dir)/runs/1/result.json"
  grep -q grader "$(run_dir)/runs/1/evaluation.json"
}

@test "every status PROTOCOL.md documents exists in the implementation" {
  for st in ok command_failed invalid_result declared_invalid \
            evaluator_failed constraint_failed infrastructure_failed; do
    grep -q "run_status=\"$st\"" "$BENCH_SCRIPT" || {
      echo "documented status never assigned: $st"
      return 1
    }
    grep -q "\`$st\`" "$ORIGINAL_DIR/PROTOCOL.md" || {
      echo "implemented status missing from PROTOCOL.md: $st"
      return 1
    }
  done
}

@test "the minimal adapter from PROTOCOL.md section 10 works" {
  require_command jq
  cd "$TEST_TEMP_DIR"

  make_script my-tool.sh '#!/bin/sh
echo "tool output" > out.txt'
  make_script adapter.sh '#!/bin/sh
./my-tool.sh
cp out.txt "$BENCH_ARTIFACTS/"
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"latency_ms": 12, "errors": 0},
 "artifacts": ["artifacts/out.txt"]}
JSON'
  make_script evaluator.sh '#!/bin/sh
run_dir="$1"
if grep -q "tool output" "$run_dir/artifacts/out.txt"; then
  printf "{\"valid\":true,\"metrics\":{\"score\":1}}" > "$BENCH_RESULT_JSON"
else
  printf "{\"valid\":false}" > "$BENCH_RESULT_JSON"
fi'

  run_bench --runs 2 --quiet --evaluate ./evaluator.sh \
    --require "errors == 0" --require-artifact "out.txt" ./adapter.sh
  [ "$status" -eq 0 ]

  json=$(bench_json)
  [ "$(jq -r '.runs_valid' "$json")" = "2" ]
  [ "$(jq -r '.metrics.latency_ms.mean' "$json")" = "12" ]
  [ "$(jq -r '.metrics.score.valid_only.count' "$json")" = "2" ]
}

@test "PROTOCOL.md documents the schema version bench emits" {
  require_command jq
  cd "$TEST_TEMP_DIR"
  run_bench --runs 1 --quiet "echo test"
  [ "$status" -eq 0 ]

  emitted=$(jq -r '.schema_version' "$(bench_json)")
  grep -q "Version $emitted" "$ORIGINAL_DIR/PROTOCOL.md"
}
