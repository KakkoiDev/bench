#!/usr/bin/env bats
# Install script tests

load helpers

INSTALL_SCRIPT="$ORIGINAL_DIR/install.sh"

# Override HOME so tests never touch real ~/.claude or ~/.local/bin
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR
  ORIGINAL_DIR="$(pwd)"
  export ORIGINAL_DIR
  BENCH_SCRIPT="$ORIGINAL_DIR/bench"
  export BENCH_SCRIPT
  INSTALL_SCRIPT="$ORIGINAL_DIR/install.sh"
  export INSTALL_SCRIPT

  FAKE_HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$FAKE_HOME"
  export HOME="$FAKE_HOME"
}

run_installer() {
  run "$INSTALL_SCRIPT" "$@"
}

# --- Basic flags ---

@test "install.sh exists and is executable" {
  [ -f "$INSTALL_SCRIPT" ]
  [ -x "$INSTALL_SCRIPT" ]
}

@test "install.sh --help shows usage" {
  run_installer --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "--dir" ]]
  [[ "$output" =~ "--with-claude" ]]
  [[ "$output" =~ "--uninstall" ]]
}

@test "install.sh rejects unknown options" {
  run_installer --bogus
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown option" ]]
}

# --- Bench installation ---

@test "install.sh installs bench to custom dir" {
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [ -f "$target/bench" ]
  [ -x "$target/bench" ]
}

@test "installed bench matches source" {
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  diff "$ORIGINAL_DIR/bench" "$target/bench"
}

@test "install.sh creates target dir if missing" {
  local target="$TEST_TEMP_DIR/deep/nested/bin"
  [ ! -d "$target" ]
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [ -f "$target/bench" ]
}

@test "install.sh defaults to ~/.local/bin when it exists" {
  mkdir -p "$FAKE_HOME/.local/bin"
  run_installer --skip-deps
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.local/bin/bench" ]
}

@test "install.sh warns when dir not in PATH" {
  local target="$TEST_TEMP_DIR/not-in-path"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not in your PATH" ]]
}

@test "install.sh no PATH warning when dir is in PATH" {
  local target="$TEST_TEMP_DIR/in-path"
  mkdir -p "$target"
  export PATH="$target:$PATH"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "not in your PATH" ]]
}

# --- Dependency checks ---

@test "install.sh checks dependencies by default" {
  # Should succeed since dev machine has perl, bc, ps
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target"
  [ "$status" -eq 0 ]
}

@test "install.sh --skip-deps skips checks" {
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping dependency checks" ]]
}

@test "install.sh fails on missing dependencies" {
  # Remove perl from PATH to simulate missing dep
  local fake_path="$TEST_TEMP_DIR/fake-path"
  mkdir -p "$fake_path"
  # Create stubs for everything except perl
  for cmd in bc ps; do
    printf '#!/bin/sh\nexit 0\n' > "$fake_path/$cmd"
    chmod +x "$fake_path/$cmd"
  done

  local target="$TEST_TEMP_DIR/bin"
  PATH="$fake_path" run "$INSTALL_SCRIPT" --dir "$target"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing dependencies" ]]
  [[ "$output" =~ "perl" ]]
}

# --- Claude Code integration ---

@test "install.sh --with-claude fails without ~/.claude" {
  local target="$TEST_TEMP_DIR/bin"
  [ ! -d "$FAKE_HOME/.claude" ]
  run_installer --dir "$target" --skip-deps --with-claude
  [ "$status" -ne 0 ]
  [[ "$output" =~ "directory not found" ]]
}

@test "install.sh --with-claude installs agent and skill" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps --with-claude
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/agents/bench.md" ]
  [ -f "$FAKE_HOME/.claude/skills/bench/SKILL.md" ]
}

@test "claude agent file has valid frontmatter" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps --with-claude

  local agent="$FAKE_HOME/.claude/agents/bench.md"
  # Check YAML frontmatter has name and description
  head -5 "$agent" | grep -q "^name: bench"
  head -5 "$agent" | grep -q "^description:"
}

@test "claude skill file has valid frontmatter" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps --with-claude

  local skill="$FAKE_HOME/.claude/skills/bench/SKILL.md"
  head -5 "$skill" | grep -q "^name: bench"
  head -5 "$skill" | grep -q "^description:"
}

@test "install.sh without --with-claude skips claude files" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HOME/.claude/agents/bench.md" ]
  [ ! -f "$FAKE_HOME/.claude/skills/bench/SKILL.md" ]
}

# --- Uninstall ---

@test "install.sh --uninstall removes bench" {
  local target="$TEST_TEMP_DIR/bin"
  # Install first
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [ -f "$target/bench" ]

  # Uninstall
  run_installer --dir "$target" --uninstall
  [ "$status" -eq 0 ]
  [ ! -f "$target/bench" ]
}

@test "install.sh --uninstall --with-claude removes claude files" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"

  # Install with claude
  run_installer --dir "$target" --skip-deps --with-claude
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.claude/agents/bench.md" ]
  [ -f "$FAKE_HOME/.claude/skills/bench/SKILL.md" ]

  # Uninstall with claude
  run_installer --dir "$target" --uninstall --with-claude
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_HOME/.claude/agents/bench.md" ]
  [ ! -d "$FAKE_HOME/.claude/skills/bench" ]
}

@test "install.sh --uninstall warns when bench not found" {
  local target="$TEST_TEMP_DIR/empty-bin"
  mkdir -p "$target"
  run_installer --dir "$target" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bench not found" ]]
}

# --- Idempotency ---

@test "install.sh can run twice without error" {
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  run_installer --dir "$target" --skip-deps
  [ "$status" -eq 0 ]
  [ -f "$target/bench" ]
}

@test "install.sh --with-claude can run twice without error" {
  mkdir -p "$FAKE_HOME/.claude"
  local target="$TEST_TEMP_DIR/bin"
  run_installer --dir "$target" --skip-deps --with-claude
  [ "$status" -eq 0 ]
  run_installer --dir "$target" --skip-deps --with-claude
  [ "$status" -eq 0 ]
}

# --- ShellCheck ---

@test "install.sh passes ShellCheck validation" {
  require_command shellcheck
  run shellcheck -s sh "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
}
