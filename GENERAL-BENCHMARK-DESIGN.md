# General Benchmark Design

Status: implemented (schema 2.1, manifest schema 1.0)

## Objective

Extend Bench from command timing and process monitoring into a domain-agnostic experiment runner:

> Bench executes repeatable experiments, collects arbitrary measurements, evaluates outcomes, and preserves enough context and evidence to reproduce and compare them.

The existing zero-configuration interface must remain useful:

```sh
bench --runs 10 "command"
```

The general experiment system extends this interface; it does not replace it or require a manifest for simple timing.

## Scope boundaries

Bench should own:

- repeatable execution;
- experimental variants;
- measurement collection;
- independent evaluation;
- constraints and validity;
- comparisons and statistical summaries;
- provenance and reproducibility metadata;
- logs, artifacts, and resumable experiment state.

Bench should not become:

- a project-management or discussion system;
- an optimizer or autonomous agent;
- a domain-specific testing framework;
- a distributed workflow engine;
- a database server;
- an internal plugin ecosystem.

Unix commands and versioned JSON are the extension boundary. Jikko may define and discuss work and reference Bench results; Bench produces experimental evidence.

## Architecture

| Layer | Responsibility |
|---|---|
| Runner | Execute variants repeatedly under controlled conditions |
| Collectors | Measure time, resources, tokens, correctness, quality, or domain metrics |
| Evaluator | Independently validate output and calculate scores |
| Reporter | Compare results and preserve evidence |

Domain knowledge belongs in external commands, collectors, and evaluators. The Bench runtime stores and compares named metrics without needing to understand their meaning.

## Custom measurements

A benchmarked command or evaluator should be able to emit a small standard result:

```json
{
  "metrics": {
    "accuracy": 0.94,
    "tokens": 1842,
    "tests_passed": 37,
    "tests_total": 40,
    "human_review_seconds": 52
  },
  "artifacts": ["report.json", "patch.diff"],
  "valid": true
}
```

For streaming collectors, support JSON Lines events:

```json
{"type":"metric","name":"tokens","value":1420,"unit":"token"}
{"type":"metric","name":"accuracy","value":0.94}
{"type":"artifact","path":"patch.diff"}
{"type":"evidence","path":"test-report.xml"}
```

### Initial metric rules

- Metric names are stable strings.
- Values are finite numbers; reject NaN and infinity.
- Units are optional but must match when values are compared.
- Preserve unknown fields for forward compatibility.
- Store raw per-run measurements as well as aggregates.
- Do not silently discard outliers.

## Independent evaluation

The command being measured and the command judging it must be separable:

```yaml
command: ./run-agent.sh
evaluate: ./grade-result.sh
```

The evaluator receives the run directory and returns validation, metrics, and artifacts. A subject must not be considered successful merely because it declares itself successful.

An execution is valid only if:

- the command satisfies its configured exit requirements;
- the evaluator succeeds;
- emitted result data validates against the schema;
- all hard constraints pass;
- required artifacts exist.

## Optional experiment manifest

Use an optional manifest for complex experiments while retaining command-line mode:

```yaml
schema_version: "1.0"
name: api-cache

setup: ./scripts/reset-db.sh
command: ./scripts/request.sh
evaluate: ./scripts/evaluate.sh
cleanup: ./scripts/cleanup.sh

runs: 30
warmup: 5
timeout: 60s

variants:
  baseline:
    env:
      CACHE: "false"
  candidate:
    env:
      CACHE: "true"

metrics:
  latency_ms:
    goal: minimize
  requests_per_second:
    goal: maximize
  errors:
    goal: minimize
    constraint: "== 0"
```

### Manifest principles

- Keep the schema small and versioned.
- Unknown fields should fail clearly at first; introduce an explicit compatibility policy later.
- Commands run without an implicit shell unless shell execution is explicitly selected.
- Environment values supplement an allowlisted base environment.
- Setup and cleanup behavior must be explicit: once per experiment, once per variant, or once per run.
- Timeouts and interruption behavior must be deterministic.
- Resolve relative paths against the manifest location.

## Variants and execution order

Bench should compare multiple named variants under equivalent conditions.

Do not run every baseline observation followed by every candidate observation by default. Temperature, caches, battery state, background activity, and time can bias that order. Support randomized or balanced interleaving such as:

```text
A B B A A B B A
```

Record the generated order and random seed. Support fixed order only when explicitly requested.

## Correctness and promotion constraints

Metrics may be optimized or constrained:

```yaml
metrics:
  duration_ms:
    goal: minimize
  test_pass_rate:
    constraint: "== 1"
  coverage:
    constraint: ">= baseline"
```

Potential CLI:

```sh
bench compare baseline candidate \
  --require "latency_ms <= baseline * 0.90" \
  --require "errors == 0"
```

Constraints must use a deliberately small expression grammar. Do not evaluate arbitrary code from manifests.

Bench reports evidence; automatic deployment or production promotion remains outside its scope.

## Comparison and statistics

`bench compare` should initially provide:

- sample count;
- failures and invalid-run rate;
- mean, median, minimum, maximum;
- standard deviation or robust spread;
- p50, p95, and p99 where sample size permits;
- absolute difference;
- relative difference;
- confidence interval for the difference;
- paired comparison when runs are paired;
- constraint results.

Reports must distinguish statistical uncertainty from practical significance. A result should not be presented as an improvement merely because a small difference is statistically detectable.

Do not automatically remove outliers. Display them and permit an explicit, recorded exclusion policy.

## Reproducibility metadata

Capture where available:

- Bench and schema version;
- exact command and arguments;
- experiment and variant configuration hashes;
- Git commit and dirty state;
- dataset and input hashes;
- random seed;
- execution order;
- wall-clock timestamps;
- warm-up policy;
- timeout and resource budgets;
- operating system and kernel;
- architecture;
- CPU and memory information;
- relevant tool versions;
- exit code and termination signal;
- stdout, stderr, measurements, and artifacts.

Never dump the full environment. Capture an allowlist, redact configured keys, and record which values were intentionally omitted.

## Result layout

Keep results understandable without the Bench executable:

```text
bench-results/<experiment>/<execution>/
  experiment.json
  environment.json
  comparison.json
  variants/
    baseline/
      runs/
        0001/
          run.json
          metrics.json
          stdout.log
          stderr.log
          artifacts/
    candidate/
      runs/
        0001/
          ...
```

Requirements:

- Every JSON document has a schema version.
- Files are append-safe or atomically replaced.
- Interrupted runs remain visibly incomplete rather than appearing valid.
- Paths stored inside results are relative where possible.
- Result directories are self-describing and portable.
- Existing schema 2.0 results remain readable.

## Resumption

An interrupted experiment should resume without rerunning valid completed observations:

```sh
bench run experiment.yaml --resume <execution>
```

Before resumption, verify that the manifest, command, variants, inputs, and relevant environment fingerprints still match. Require an explicit override if they differ, and record the override.

## CLI direction

Preserve current behavior and add subcommands incrementally:

```sh
bench "command"
bench run experiment.yaml
bench compare <baseline> <candidate>
bench report <execution>
bench validate experiment.yaml
bench resume <execution>
```

`--json` should produce deterministic machine-readable output. Human-readable output remains the default. `--quiet` should continue to print only the result path.

## Implementation strategy

The current POSIX shell implementation is a strength for portability. Do not rewrite it merely because the scope is growing.

First implement the schema and command protocol with shell plus existing system tools. Reconsider a Go core only when concrete failures appear, such as:

- JSON/YAML handling becomes unsafe or dependency-heavy;
- resumable state becomes difficult to make atomic;
- cross-platform process monitoring cannot remain reliable;
- statistical code becomes too large to test confidently;
- shell quoting prevents safe argument-array execution.

If a rewrite becomes necessary, preserve the CLI, result schema, and command-based extension protocol.

## Implementation phases

### Phase 1 — Stable evidence format — implemented

- [x] Specify and version experiment, run, metric, environment, and artifact JSON.
- [x] Preserve raw per-run metrics.
- [x] Add custom numeric metric ingestion.
- [x] Register artifacts and evidence.
- [x] Validate emitted data with useful errors.
- [x] Test backward compatibility with current schema 2.0 results.

Acceptance: a command can emit domain metrics and artifacts, and the saved result is understandable without Bench.

Delivered as schema 2.1. A command writes `result.json` and/or `metrics.jsonl`
into `$BENCH_RUN_DIR`; both are parsed with JSON::PP, not text tools. Metric
names must be stable identifiers and values finite numbers, so NaN, Infinity,
booleans and non-numeric strings are rejected with an error naming the metric
and, for streamed events, the line. Every observation is retained under
`metrics.<name>.values` with the run it came from; outliers are never trimmed.
Unknown fields survive under `metrics.json`'s `source`. Registered paths must
be relative and inside the run directory. In-flight runs carry an `INCOMPLETE`
marker so an interrupted run cannot be mistaken for a finished one.

### Phase 2 — Evaluators and validity — implemented

- [x] Add an independent evaluator command.
- [x] Pass the run directory using a documented interface.
- [x] Record evaluator stdout, stderr, exit status, and result.
- [x] Add hard constraints and required artifacts.
- [x] Distinguish command failure, evaluator failure, constraint failure, and infrastructure failure.

Acceptance: a benchmark subject cannot mark itself successful without independent validation.

`--evaluate CMD` runs after the timing clock has stopped, so evaluation never
inflates the measurement. The evaluator receives the run directory as `$1` and
in `$BENCH_RUN_DIR`, plus `$BENCH_EXIT_CODE`, `$BENCH_STDOUT` and
`$BENCH_STDERR`; its stdout, stderr, exit status and emitted result are all
recorded. `--require "<metric> <op> <number>"` uses a fixed three-term grammar
that is parsed, never evaluated, so nothing from a result file reaches a shell.
Per-run status is one of `ok`, `command_failed`, `invalid_result`,
`declared_invalid`, `evaluator_failed`, `constraint_failed` or
`infrastructure_failed`, and `runs_valid` is reported separately from
`runs_successful`. A subject's own `"valid": true` is recorded and ignored; its
`"valid": false` is honoured.

### Phase 3 — Manifests and variants — implemented

- [x] Define the minimal versioned manifest.
- [x] Add setup, command, evaluate, and cleanup lifecycle.
- [x] Add named variants.
- [x] Add warm-up and timeout behavior.
- [x] Add balanced or seeded randomized execution order.
- [x] Add `bench validate`.

Acceptance: one manifest can reproduce a baseline/candidate experiment with a recorded execution order.

Manifest schema 1.0, in YAML or JSON. YAML::PP is not core Perl, so rather
than take a CPAN dependency bench parses a documented restricted subset —
comments, nested maps, sequences, quoted scalars — and refuses anything
outside it rather than guessing. Unknown fields are errors, not warnings: a
misspelled key that is silently dropped produces an experiment that is not the
one that was written.

Each variant produces a complete, standalone schema 2.1 result directory, so
`compare`, `resume`, `report` and plain `jq` all work on it unchanged rather
than needing to learn a second format. Lifecycle scope is explicit
(`setup_scope`, `cleanup_scope`: experiment, variant or run) and warm-up runs
never enter the recorded sample.

Execution order defaults to `interleaved`, which rotates the variant order each
round. Running every baseline observation and then every candidate one would
attribute drift in machine state — temperature, page cache, background
activity — to whichever variant ran second. `random` shuffles from the recorded
seed; `sequential` exists for cases where switching between variants is itself
expensive, and results from it carry that bias. The order actually executed and
the seed are both written to `experiment.json`.

### Phase 4 — Comparison — implemented

- [x] Add `bench compare`.
- [x] Calculate absolute and relative changes.
- [x] Add failure and invalid-run rates.
- [x] Add confidence intervals and paired comparisons.
- [x] Evaluate constraints.
- [x] Produce both human and JSON reports.

Acceptance: Bench can state the size and uncertainty of a change while showing whether correctness constraints passed.

Confidence intervals are bootstrap percentile intervals rather than
t-intervals: benchmark samples are routinely skewed and multi-modal, and the
bootstrap assumes no distribution. Resampling uses an explicit linear
congruential generator seeded from the command line, so an interval is
reproducible on any machine and any Perl build rather than depending on the
platform's `rand()`.

Comparison uses valid runs only — a run that failed its checks did not do the
work being timed. The report states plainly that an interval excluding zero
means a difference is *detectable in this sample*, and that whether it matters
is a separate question the report does not answer. A violated `--require`
exits non-zero so CI does not have to parse the report to find out.

### Phase 5 — Provenance and resumption — implemented

- [x] Capture Git, input, tool, machine, and configuration fingerprints.
- [x] Add environment allowlisting and redaction.
- [x] Mark interrupted observations incomplete.
- [x] Resume matching experiments without repeating valid runs.
- [x] Detect and record resumption mismatches and overrides.

Acceptance: another person or agent can inspect, resume, and audit an interrupted experiment.

Taken before phases 3 and 4 deliberately. Independent evaluation and
deterministic resumption are the two mechanisms this design is not already
sharing with MLflow, Sacred, DVC and Snakemake; manifests, variants and
comparison statistics are engineering those tools have had for years. Building
the distinguishing half first also defers the question of whether a YAML parser
and inferential statistics belong in POSIX shell at all.

`--resume DIR` continues into the original result directory after verifying the
configuration fingerprint — command, run count, exit requirement, evaluator,
constraints, required artifacts and metrics interval, with `--name`/`--message`
and the PIDs behind `--pid`/`--port` deliberately excluded. A mismatch is
refused unless `--force-resume` records the override. Runs already recorded are
kept, including invalid ones: re-rolling failures until they pass would bias the
sample toward success. Only the `INCOMPLETE` run is redone, and every sitting
appends to `provenance.resumes`.

Provenance never dumps the environment: capture is opt-in via `--capture-env`,
credential-shaped names are refused even when requested, and the count of
omitted variables is recorded. Bench's own results directory is excluded from
the git dirty check, so a resume does not report dirty merely because the
previous sitting wrote files.

### Phase 6 — Domain demonstrations — implemented

Implement examples without adding domain logic to Bench:

- [x] command/runtime performance;
- [x] web service performance plus correctness;
- [x] CI configuration comparison;
- [ ] local-model quality, latency, memory, and token measurements;
- [x] agent task execution with an independent test evaluator;
- [x] deterministic algorithm or optimizer comparison.

Acceptance: each example uses the same Bench protocol and only small external adapters.

Five of the six are in [`examples/`](examples/), each a subject, an evaluator
and a manifest, using only the documented protocol. None required a change to
bench, and a test asserts that every `BENCH_` variable they use is documented
in `PROTOCOL.md`.

The local-model example is deliberately not included: it needs model weights
and hardware that cannot be assumed present, so it would be an example nobody
could run. The agent-task example covers the same shape — a subject that
reports its own token spend and claims success — without the dependency.

Two of the five demonstrate the failure the protocol exists to catch, and both
are asserted in the test suite: the overconfident agent writes `"valid": true`
and exits zero yet scores zero valid runs, and the CI configuration that goes
faster by skipping slow tests is measurably faster and entirely invalid.

**This is demonstration, not evaluation.** All five adapters were written by
the same author as the protocol, which measures that author's adapter-writing
skill rather than the protocol's generality. Adapter effort is only a
meaningful number once somebody else writes one, which is what `PROTOCOL.md`
exists to make possible.

## Testing requirements

- Golden tests for every versioned JSON format.
- Malformed metric and event input tests.
- Unit normalization and mismatch tests.
- Paths and commands containing spaces and special characters.
- Timeout, signal, and interrupted-write tests.
- Setup/evaluator/cleanup failure combinations.
- Reproducible randomized-order tests using fixed seeds.
- Resume after interruption at every lifecycle point.
- Environment-secret redaction tests.
- Backward-compatibility tests for current CLI and schema 2.0 output.
- Linux and macOS CI.

## Research direction

Candidate title:

> Bench: A Domain-Agnostic Protocol for Reproducible, Evidence-Producing Computational Experiments

Research question:

> Can a small command-oriented experiment protocol support reproducible evaluation across heterogeneous domains without requiring domain logic in the benchmark runtime?

A paper needs empirical evaluation beyond implementing the CLI. Evaluate:

- adapter code required across different domains;
- reproducibility across machines;
- overhead relative to direct execution;
- whether independent evaluators prevent false improvements;
- reconstruction from saved artifacts;
- deterministic resumption after interruption;
- use by both humans and agents;
- portability between local machines and CI.

## Non-goals for the first implementation

- Remote worker scheduling
- A hosted result service
- Automatic optimizer integration
- Production deployment
- Arbitrary expression evaluation
- An internal plugin SDK
- A graphical dashboard
- A proprietary binary result format
- Replacing specialized load, test, profiling, or observability tools

Bench should wrap specialized tools, standardize evidence, and make experiments comparable—not reimplement every measurement system.
