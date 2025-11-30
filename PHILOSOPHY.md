# Design Philosophy

bench follows the Unix philosophy: **do one thing well**.

## Core Principles

### POSIX Shell Syntax

Written in POSIX sh (dash-compatible), not bash-specific. Portable shell code across Linux, macOS, BSD.

```bash
# Validate POSIX compliance
shellcheck -s sh bench
dash -n bench
```

### Unix Tools Required

Depends on common Unix utilities (`perl`, `bc`, `ps`) that aren't strictly POSIX but are universally available. The script is POSIX-compliant, the runtime requires Unix tools.

### Long-Only Flags

No short flags (`--runs`, not `-r`) to avoid namespace conflicts and improve clarity. Follows [clig.dev](https://clig.dev) best practices.

### JSON-Only Output

No summary.txt or human-readable reports. Use jq/llm/scripts for formatting:

```bash
# Human-readable with jq
cat benchmark.json | jq '.timing'

# AI analysis
cat benchmark.json | llm "Analyze performance"
```

This keeps bench focused on data capture, not presentation.

### Millisecond Precision

Uses Perl Time::HiRes (portable, core module since 2002) for microsecond precision timing. More reliable than `date +%s.%N` which varies across systems.

### Timestamp-PID Directories

Output directories use `YYYYMMDD-HHMMSS-PID` format to prevent collisions when running concurrent benchmarks.

```
./bench-results/api-test/
  20251130-143052-12345/   # First run
  20251130-143052-12346/   # Concurrent run (different PID)
```

## What bench Does NOT Do

- **Statistical analysis** - Use jq, Python, or LLMs for analysis
- **Visualization** - Use external tools to graph results
- **HTTP-specific features** - Use ab/wrk/k6 for HTTP load testing
- **Replace specialized tools** - bench complements, not replaces

## Why These Choices?

### Portability Over Features

POSIX sh works everywhere. Bash-specific features would limit where bench can run.

### Data Over Presentation

JSON is machine-readable. Humans can format it however they want. This prevents bench from becoming bloated with formatting options.

### Simplicity Over Completeness

8 flags total. No config files. No plugins. If you need more, use a specialized tool.

### Composability

bench works with other tools:

```bash
# Wrap hyperfine for server monitoring
bench --pid $SERVER "hyperfine 'curl localhost'"

# Pipe to analysis
bench --quiet "cmd" | xargs -I {} cat {}/benchmark.json | jq
```

## References

- [clig.dev](https://clig.dev) - Command Line Interface Guidelines
- [Unix Philosophy](https://en.wikipedia.org/wiki/Unix_philosophy) - Do one thing well
