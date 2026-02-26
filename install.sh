#!/bin/sh
# bench installer
# Installs bench binary and optionally Claude Code skill + agent
set -e

VERSION="2.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_SOURCE="$SCRIPT_DIR/bench"

# Defaults
INSTALL_DIR=""
INSTALL_CLAUDE=0
SKIP_DEPS=0
UNINSTALL=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN="" RED="" YELLOW="" BOLD="" RESET=""
fi

info()  { printf "${GREEN}[+]${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${RESET} %s\n" "$1"; }
error() { printf "${RED}[x]${RESET} %s\n" "$1" >&2; }
die()   { error "$1"; exit 1; }

usage() {
  cat <<EOF
bench installer v${VERSION}

Usage: ./install.sh [OPTIONS]

Options:
  --dir PATH        Install directory (default: ~/.local/bin or /usr/local/bin)
  --with-claude     Also install Claude Code skill and agent
  --skip-deps       Skip dependency checks
  --uninstall       Remove bench and optional Claude Code files
  --help            Show this help

Examples:
  ./install.sh                          # Install bench only
  ./install.sh --with-claude            # Install bench + Claude Code integration
  ./install.sh --dir ~/bin              # Install to custom directory
  ./install.sh --uninstall              # Remove everything
  ./install.sh --uninstall --with-claude # Remove bench + Claude Code files
EOF
  exit 0
}

# --- Argument parsing ---

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        INSTALL_DIR="$2"; shift 2 ;;
    --with-claude) INSTALL_CLAUDE=1; shift ;;
    --skip-deps)  SKIP_DEPS=1; shift ;;
    --uninstall)  UNINSTALL=1; shift ;;
    --help)       usage ;;
    *)            die "Unknown option: $1" ;;
  esac
done

# --- Resolve install directory ---

resolve_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    return
  fi

  # Prefer ~/.local/bin (no sudo needed)
  if [ -d "$HOME/.local/bin" ]; then
    INSTALL_DIR="$HOME/.local/bin"
  elif [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
}

# --- Dependency checks ---

check_deps() {
  if [ "$SKIP_DEPS" = 1 ]; then
    warn "Skipping dependency checks"
    return
  fi

  missing=""

  # Required
  command -v perl >/dev/null 2>&1 || missing="$missing perl"
  command -v bc >/dev/null 2>&1   || missing="$missing bc"
  command -v ps >/dev/null 2>&1   || missing="$missing ps"

  # Perl Time::HiRes
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes -e '1' 2>/dev/null || missing="$missing perl-Time::HiRes"
  fi

  if [ -n "$missing" ]; then
    die "Missing dependencies:$missing"
  fi

  # Optional (warn only)
  if ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1; then
    warn "Neither lsof nor ss found. --port flag will not work."
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found. Recommended for analyzing benchmark results."
  fi
}

# --- Install bench ---

install_bench() {
  if [ ! -f "$BENCH_SOURCE" ]; then
    die "bench script not found at $BENCH_SOURCE"
  fi

  mkdir -p "$INSTALL_DIR"
  cp "$BENCH_SOURCE" "$INSTALL_DIR/bench"
  chmod +x "$INSTALL_DIR/bench"
  info "Installed bench to $INSTALL_DIR/bench"

  # Check PATH
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      warn "$INSTALL_DIR is not in your PATH"
      warn "Add to your shell profile: export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

# --- Claude Code integration ---

CLAUDE_DIR="$HOME/.claude"
AGENT_FILE="$CLAUDE_DIR/agents/bench.md"
SKILL_DIR="$CLAUDE_DIR/skills/bench"
SKILL_FILE="$SKILL_DIR/SKILL.md"

install_claude() {
  if [ "$INSTALL_CLAUDE" != 1 ]; then
    return
  fi

  if [ ! -d "$CLAUDE_DIR" ]; then
    die "~/.claude directory not found. Is Claude Code installed?"
  fi

  # Install agent
  mkdir -p "$CLAUDE_DIR/agents"
  cp "$SCRIPT_DIR/.claude/agents/bench.md" "$AGENT_FILE"
  info "Installed agent to $AGENT_FILE"

  # Install skill
  mkdir -p "$SKILL_DIR"
  cp "$SCRIPT_DIR/.claude/skills/bench/SKILL.md" "$SKILL_FILE"
  info "Installed skill to $SKILL_FILE"
}

# --- Uninstall ---

uninstall() {
  resolve_install_dir

  if [ -f "$INSTALL_DIR/bench" ]; then
    rm "$INSTALL_DIR/bench"
    info "Removed $INSTALL_DIR/bench"
  else
    warn "bench not found at $INSTALL_DIR/bench"
  fi

  if [ "$INSTALL_CLAUDE" = 1 ]; then
    if [ -f "$AGENT_FILE" ]; then
      rm "$AGENT_FILE"
      info "Removed $AGENT_FILE"
    fi
    if [ -d "$SKILL_DIR" ]; then
      rm -rf "$SKILL_DIR"
      info "Removed $SKILL_DIR"
    fi
  fi

  info "Uninstall complete"
  exit 0
}

# --- Main ---

if [ "$UNINSTALL" = 1 ]; then
  uninstall
fi

resolve_install_dir
check_deps
install_bench
install_claude

info "bench v${VERSION} installed successfully"
if [ "$INSTALL_CLAUDE" = 1 ]; then
  info "Claude Code skill and agent installed"
fi
