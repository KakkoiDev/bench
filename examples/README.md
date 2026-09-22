# Examples

Each directory is a worked adapter for one domain. They exist to answer the
question the protocol claims to answer: *can the same runner produce comparable
evidence across unrelated domains without domain knowledge moving into bench?*

Every example uses only the documented protocol in [../PROTOCOL.md](../PROTOCOL.md)
— environment variables in, JSON out. None of them required a change to bench.

| Example | Domain | What the evaluator checks |
|---|---|---|
| [`command-performance/`](command-performance) | Runtime performance of a CLI | Output is correct, not just fast |
| [`web-service/`](web-service) | HTTP service latency + correctness | Response body and status, not just timing |
| [`ci-configuration/`](ci-configuration) | Build/test configuration comparison | No tests were skipped to go faster |
| [`agent-task/`](agent-task) | An agent solving a coding task | Held-out tests the agent never saw |
| [`algorithm-tuning/`](algorithm-tuning) | Deterministic optimizer comparison | The solution is admissible, not just cheap |

## The shape they share

Each has a `run.sh` (the subject), a `grade.sh` (the independent evaluator) and
an `experiment.yaml` (the manifest). Run any of them from its own directory:

```sh
cd examples/agent-task
../../bench run experiment.yaml
../../bench compare bench-results/*/*/variants/baseline \
                    bench-results/*/*/variants/candidate
```

## Why every example has a separate evaluator

The evaluator is not a formality. In each of these domains the subject has an
obvious way to look successful without being correct:

- a CLI that exits zero having produced truncated output;
- a service that returns 200 with an error page in the body;
- a CI configuration that is faster because it skipped tests;
- an agent that reports success while the tests fail;
- an optimizer that returns a cheap but infeasible solution.

`agent-task` is the sharpest case, and the one existing experiment trackers do
not defend against: the subject writes its own `result.json` claiming
`"valid": true`, and bench ignores the claim. Validity comes from `grade.sh`
running tests the subject never saw.
