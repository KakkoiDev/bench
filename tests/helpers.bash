# BATS test helpers for bench CLI

# Setup function run before each test
setup() {
  # Create temporary directory for test output
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Store original directory
  ORIGINAL_DIR="$(pwd)"
  export ORIGINAL_DIR

  # Path to bench script
  BENCH_SCRIPT="$ORIGINAL_DIR/bench"
  export BENCH_SCRIPT
}

# Teardown function run after each test
teardown() {
  # Clean up temporary directory
  if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
    rm -rf "$TEST_TEMP_DIR"
  fi

  # Return to original directory
  cd "$ORIGINAL_DIR" || true
}

# Helper: Run bench in test temp directory
run_bench() {
  cd "$TEST_TEMP_DIR" || return 1
  run "$BENCH_SCRIPT" "$@"
}

# Helper: Check if file exists
assert_file_exists() {
  [ -f "$1" ] || {
    echo "Expected file does not exist: $1"
    return 1
  }
}

# Helper: Check if directory exists
assert_dir_exists() {
  [ -d "$1" ] || {
    echo "Expected directory does not exist: $1"
    return 1
  }
}

# Helper: Check JSON is valid
assert_valid_json() {
  require_command jq

  jq empty "$1" 2>/dev/null || {
    echo "Invalid JSON in file: $1"
    return 1
  }
}

# Helper: Get JSON value
get_json_value() {
  require_command jq

  local file="$1"
  local path="$2"
  jq -r "$path" "$file"
}

# Helper: Check if command exists
has_command() {
  command -v "$1" >/dev/null 2>&1
}

# Helper: Skip test if dependency missing
require_command() {
  if ! has_command "$1"; then
    skip "$1 not installed"
  fi
}

# Helper: Create lightweight mock process for infrastructure testing
# This process consumes minimal resources (CPU ~0%, memory ~100KB)
# Use for unit tests that just need a valid PID to monitor
# Usage: pid=$(create_mock_process)      # default 10s
#        pid=$(create_mock_process 1)    # 1s for fast tests
create_mock_process() {
  local duration="${1:-10}"
  sleep "$duration" &
  echo $!
}

# Helper: Create realistic server for integration testing
# This server consumes realistic resources (CPU 1-5%, memory 10-20MB)
# Use for integration tests that validate metric accuracy
create_real_server() {
  require_command python3

  # Start Python HTTP server on random available port
  # Suppress output to avoid cluttering test results
  python3 -m http.server 0 >/dev/null 2>&1 &
  local pid=$!

  # Give server time to start (100ms)
  sleep 0.1

  echo "$pid"
}

# Helper: Get port number from server PID
# Usage: port=$(get_server_port $pid)
# Returns: port number or empty string if not found/invalid
get_server_port() {
  require_command lsof

  local pid="$1"
  # Extract port from lsof output: *:8000 -> 8000
  local port
  port=$(lsof -Pan -p "$pid" -i TCP -sTCP:LISTEN 2>/dev/null | \
    awk 'NR>1 {split($9,a,":"); print a[2]; exit}')

  # Validate port is numeric (1-65535)
  case "$port" in
    ''|*[!0-9]*) return 1 ;;  # Empty or non-numeric
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi

  echo "$port"
}

# Helper: Create a stub command that always succeeds
# Usage: create_stub "perl" "$TEST_TEMP_DIR/bin"
# Returns: Path to the stub directory (add to PATH)
create_stub() {
  local cmd="$1"
  local dir="${2:-$TEST_TEMP_DIR/bin}"

  mkdir -p "$dir"
  cat > "$dir/$cmd" << 'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$dir/$cmd"

  echo "$dir"
}

# Helper: Kill mock process (works for both lightweight and real server)
kill_mock_process() {
  local pid="$1"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}
