# Contributing to bench

## Getting Started

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/bench.git
cd bench
chmod +x bench

# Install dev dependencies
sudo apt-get install shellcheck bats  # Debian/Ubuntu
brew install shellcheck bats-core     # macOS
```

## Development

```bash
# Run tests
bats tests/

# Validate POSIX compliance
shellcheck -s sh bench
dash bench --runs 3 "echo test"

# Manual testing
# See MANUAL-TESTING.md for comprehensive feature verification
```

## Code Style

**POSIX sh only** - no bash-isms. Test with `dash`.

```sh
# Good
[ -n "$var" ] && echo "set"
[ "$a" = "$b" ]

# Bad (bash-specific)
[[ -n "$var" ]] && echo "set"
[[ "$a" == "$b" ]]
```

**Naming**: `snake_case` for variables/functions, `UPPER_CASE` for constants.

## Pull Requests

Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`

Checklist:
- [ ] ShellCheck passes
- [ ] Tests pass (`bats tests/`)
- [ ] Works with dash

## Feature Requests

**bench's scope:**
- Server CPU/memory monitoring during command execution
- Persistent, organized JSON logs
- AI-friendly output
- Wraps other tools (hyperfine, k6, ab, wrk)

**Good requests:** more metrics, better monitoring, improved portability

**Out of scope:** built-in analysis, visualization, config files (use jq/LLM for analysis)

## Bug Reports

Include: `bench --version`, OS, shell, steps to reproduce, expected vs actual behavior.

## License

Contributions licensed under MIT.
