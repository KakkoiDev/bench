# Contributing to bench

Thank you for your interest in contributing to bench! This document provides guidelines for contributing to the project.

## Code of Conduct

- Be respectful
- Focus on constructive feedback
- Help maintain a welcoming environment

## Getting Started

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/bench.git
cd bench

# Make the script executable
chmod +x bench

# Install development dependencies
sudo apt-get install perl bc shellcheck bats  # Debian/Ubuntu
brew install perl bc shellcheck bats-core     # macOS
```

## Development Workflow

1. **Create a feature branch**
   ```bash
   git switch -c feature/your-feature-name
   ```

2. **Make your changes**
   - Follow POSIX sh syntax (dash-compatible)
   - Add tests for new features
   - Update documentation as needed

3. **Test your changes**
   ```bash
   # Run ShellCheck
   shellcheck -s sh bench

   # Run BATS tests
   bats tests/

   # Test manually with dash
   dash bench --runs 5 "echo test"
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add descriptive commit message"
   ```

5. **Push and create a Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Code Style Guidelines

### POSIX Compliance

- **Use POSIX sh syntax only** - no bash-isms
- Test with `dash` to ensure compatibility
- Use `shellcheck -s sh` to validate

**Good (POSIX)**:
```sh
if [ -n "$var" ]; then
  echo "var is set"
fi

[ "$a" = "$b" ]
```

**Bad (bash-specific)**:
```bash
if [[ -n "$var" ]]; then
  echo "var is set"
fi

[[ "$a" == "$b" ]]
```

### Naming Conventions

- Variables: `snake_case` (e.g., `results_dir`)
- Functions: `snake_case` (e.g., `check_dependencies`)
- Constants: `UPPER_CASE` (e.g., `VERSION`)

### Error Handling

- Always check command success with `$?` or `if command; then`
- Provide clear error messages to stderr
- Include installation instructions for missing dependencies
- Exit with appropriate codes: 0 (success), 1 (error), 130 (interrupt)

### Comments

- Use comments to explain **why**, not **what**
- Document complex algorithms with formula references
- Add section headers for major code blocks

## Testing Guidelines

### Test Structure

Tests are organized in `tests/` directory:
- `helpers.bash` - Shared test utilities
- `01-foundation.bats` - Basic functionality
- `02-core.bats` - Core benchmarking features
- `03-output.bats` - JSON output and statistics
- `04-monitoring.bats` - Server monitoring
- `05-integration.bats` - End-to-end tests

### Writing Tests

```bash
@test "descriptive test name" {
  # Arrange
  setup_test_environment

  # Act
  run_bench --runs 5 "echo test"

  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" =~ "expected pattern" ]]
}
```

### Test Coverage

- Add tests for all new features
- Test error conditions and edge cases
- Ensure POSIX compliance with dash tests
- Validate JSON output schema

## Pull Request Guidelines

### PR Title Format

Use conventional commits:
- `feat: add new feature`
- `fix: resolve bug in X`
- `docs: update README`
- `test: add tests for Y`
- `refactor: improve Z implementation`

### PR Description

Include:
- **What**: Brief description of changes
- **Why**: Motivation and context
- **How**: Implementation approach
- **Testing**: How you tested the changes
- **Breaking changes**: If any (prefix title with `BREAKING:`)

### PR Checklist

- [ ] Code follows POSIX sh syntax
- [ ] ShellCheck passes (`shellcheck -s sh bench`)
- [ ] All tests pass (`bats tests/`)
- [ ] Tested with dash (`dash bench --version`)
- [ ] Documentation updated (if needed)
- [ ] Commit messages follow conventional commits

## Feature Requests

**Before requesting a feature**, consider bench's philosophy:
- **Minimal scope** - does one thing well (capture benchmark data)
- **Unix philosophy** - compose with other tools
- **No built-in analysis** - use jq/LLM/scripts for that

**Good feature requests**:
- Add more timing metrics (p90, p999)
- Support additional monitoring sources
- Improve error messages
- Better POSIX portability

**Out of scope**:
- Built-in comparison/analysis tools
- Graphical output formats
- Built-in visualization
- Configuration files

Create an issue with:
- Clear use case description
- Example usage
- Why existing tools (jq/scripts) can't solve it

## Bug Reports

Include:
- bench version (`bench --version`)
- Operating system and version
- Shell (`echo $SHELL`)
- Steps to reproduce
- Expected vs actual behavior
- Error messages (full output)

## Documentation

- Update README.md for user-facing changes
- Update SPECIFICATIONS.md for design decisions (local reference only)
- Add inline comments for complex logic
- Update examples if behavior changes

## Questions?

- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For questions and general discussion

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
