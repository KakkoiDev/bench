# Bench evidence protocol

Version 2.1.

This is the contract between bench and the commands it runs. It is written so
that an adapter can be implemented against this document alone, without reading
bench's source.

An adapter is an ordinary program. There is no library, no SDK, and no
dependency on bench itself: a command participates by writing files into a
directory whose path it is given in an environment variable. A command that
writes nothing is still a valid subject — it is simply timed, as it was under
schema 2.0.

## 1. What bench provides

Before each run, bench creates a fresh run directory and exports:

| Variable | Meaning |
|---|---|
| `BENCH_RUN_DIR` | Absolute path to this run's directory |
| `BENCH_RESULT_JSON` | Path to write a result object (`$BENCH_RUN_DIR/result.json`) |
| `BENCH_METRICS` | Path to append JSON Lines events (`$BENCH_RUN_DIR/metrics.jsonl`) |
| `BENCH_ARTIFACTS` | Directory for files the run produces (`$BENCH_RUN_DIR/artifacts`) |
| `BENCH_RUN_NUMBER` | 1-based index of this run |
| `BENCH_RUNS` | Total number of runs requested |

An evaluator (`--evaluate`) additionally receives the run directory as `$1` and:

| Variable | Meaning |
|---|---|
| `BENCH_EXIT_CODE` | Exit status of the measured command |
| `BENCH_STDOUT` | File containing the command's stdout |
| `BENCH_STDERR` | File containing the command's stderr |

The evaluator's own `BENCH_RESULT_JSON` and `BENCH_METRICS` point at
`evaluation.json` and `evaluation.jsonl`, so its findings never overwrite the
subject's.

## 2. What a command may emit

### 2.1 Result object

Write a single JSON object to `$BENCH_RESULT_JSON`:

```json
{
  "metrics": { "accuracy": 0.94, "tokens": 1842 },
  "units":   { "tokens": "token" },
  "artifacts": ["artifacts/patch.diff"],
  "evidence":  ["artifacts/test-report.xml"],
  "valid": true
}
```

Every field is optional. Fields bench does not recognise are preserved verbatim
under `source` in the run's `metrics.json`, so a newer producer is never
silently truncated.

### 2.2 Event stream

Append JSON Lines to `$BENCH_METRICS`, one object per line:

```json
{"type":"metric","name":"tokens","value":1420,"unit":"token"}
{"type":"metric","name":"accuracy","value":0.94}
{"type":"artifact","path":"artifacts/patch.diff"}
{"type":"evidence","path":"artifacts/test-report.xml"}
{"type":"valid","value":false}
```

Event types are `metric`, `artifact`, `evidence` and `valid`. Any other type is
an error — a typo should fail loudly rather than be dropped. Blank lines are
ignored.

Both channels may be used in one run. The stream is read after the result
object, and a metric emitted twice takes its last value.

## 3. Rules

**Metric names** match `[A-Za-z_][A-Za-z0-9_.-]*`. They become JSON object keys
and are matched across runs, so a name that varies per run is a bug.

**Metric values** must be finite numbers. `NaN`, `Infinity` (note that `1e999`
parses to infinity), booleans, `null` and non-numeric strings are all rejected.
A metric that cannot be measured should be omitted, not reported as zero.

**Units** are optional, at most 32 characters from `[A-Za-z0-9_./%-]`. A metric
may not change unit within a run, or between runs of one benchmark: that means
two different quantities are sharing a name.

**Paths** are relative to the run directory. Absolute paths and paths escaping
the directory are rejected.

**Validity** is not self-assigned. `"valid": false` is honoured — a subject may
veto itself. `"valid": true` is recorded and otherwise ignored; only an
evaluator, the exit requirement and the configured constraints can make a run
valid. See section 5.

Any violation marks the run `invalid_result` and reports an error naming the
metric and, for stream events, the line number. The benchmark continues.

## 4. What bench writes back

Each run directory contains:

```
result.json         as the command wrote it, verbatim
metrics.jsonl       as the command wrote it, verbatim
metrics.json        normalized and validated by bench
artifacts/          files the command produced
evaluation.json     as the evaluator wrote it (with --evaluate)
evaluator.stdout
evaluator.stderr
INCOMPLETE          present only while the run is unfinished
```

`metrics.json` is self-describing and carries its own `schema_version`. The
result directory is readable with `jq` alone; nothing requires bench to
interpret it.

## 5. Validity

A run is valid only if **all** of the following hold:

1. The command's exit status matches `--expect-exit` (default `0`, or `any`).
2. Its emitted evidence passed validation.
3. It did not declare `"valid": false`.
4. The evaluator, if configured, exited zero and did not declare `"valid": false`.
5. Every `--require` constraint held.
6. Every `--require-artifact` path exists.

Each run reports a `status` explaining the outcome:

| Status | Meaning |
|---|---|
| `ok` | Valid |
| `command_failed` | Exit status did not meet the requirement |
| `invalid_result` | Emitted evidence failed validation |
| `declared_invalid` | The subject reported `"valid": false` |
| `evaluator_failed` | The evaluator rejected the run or failed |
| `constraint_failed` | A constraint or required artifact was not satisfied |
| `infrastructure_failed` | Bench could not carry out the run |

The evaluator is not consulted for a run that failed its exit requirement:
there is nothing to grade.

`runs_successful` counts exit codes; `runs_valid` counts validated runs. When an
evaluator or constraints are in use these differ, and `runs_valid` is the one
that matters.

## 6. Constraints

`--require` takes exactly three whitespace-separated terms:

```
<metric> <operator> <number>
```

Operators are `==`, `!=`, `<`, `<=`, `>`, `>=`. The expression is parsed, never
evaluated — nothing from a result file or a command line reaches a shell or an
expression evaluator. A constraint naming a metric the run did not report fails
that run rather than passing silently.

## 7. Aggregation

Metrics are summarized across runs with `count`, `min`, `max`, `mean`,
`median`, `stddev`, and every observation under `values` with the run it came
from under `runs`.

**Observations are never discarded.** Outliers are not trimmed, and metrics from
runs that turned out invalid are still recorded — a run that consumed a resource
and then failed its checks is a real observation, and dropping it would flatter
the result.

Because those two questions differ, each metric also carries `valid_only`,
summarizing just the runs that passed validation. Cost per *verified* unit of
work is usually what matters; cost per attempt is what `mean` reports.

## 8. Provenance

Every result records what produced it: the configuration fingerprint, machine
and kernel, tool versions, and git commit with dirty state. Bench's own results
directory is excluded from the dirty check, so a resume does not report a dirty
tree merely because the previous sitting wrote files.

The environment is **never** dumped. Only variables named with `--capture-env`
are recorded, names matching `KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `CREDENTIAL`,
`AUTH`, `SESSION` or `COOKIE` are refused even when explicitly requested, and
the number of variables left out is recorded so the omission is visible.

## 9. Resumption

`--resume DIR` continues an interrupted benchmark into the same result
directory. Before resuming, bench checks that the configuration fingerprint
still matches; if it does not, the resume is refused unless `--force-resume` is
given, and the override is then recorded in the result.

The fingerprint covers the command, run count, exit requirement, evaluator,
constraints, required artifacts and metrics interval. It deliberately excludes
`--name` and `--message`, which describe the result rather than the experiment,
and the PIDs behind `--pid`/`--port`, which change between sittings.

Runs already recorded are kept exactly as they were, including runs that
completed and were judged invalid: **re-rolling failures until they pass would
bias the sample toward success.** Only a run interrupted mid-flight — marked by
`INCOMPLETE`, with no record written — is discarded and redone.

Every sitting appends to `provenance.resumes`, so the result carries its own
history.

## 10. Writing an adapter

A minimal adapter in POSIX shell:

```sh
#!/bin/sh
./my-tool --input "$1" > out.txt
cp out.txt "$BENCH_ARTIFACTS/"
cat > "$BENCH_RESULT_JSON" <<JSON
{"metrics": {"latency_ms": $(measure), "errors": $(count_errors)},
 "artifacts": ["artifacts/out.txt"]}
JSON
```

And a matching evaluator:

```sh
#!/bin/sh
run_dir="$1"
if ./check-output "$run_dir/artifacts/out.txt"; then
  printf '{"valid":true,"metrics":{"score":%s}}' "$(score)" > "$BENCH_RESULT_JSON"
else
  printf '{"valid":false}' > "$BENCH_RESULT_JSON"
fi
```

The evaluator should be a different program from the subject, written against
the subject's output rather than its internals. That separation is the point:
it is what stops a run being called successful because the thing under test said
so.
