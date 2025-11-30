#!/usr/bin/env bats
# Phase 0 Helper Tests - Test helper functions with non-trivial logic

load helpers

@test "create_real_server starts a listening server" {
  require_command python3

  pid=$(create_real_server)

  # PID should be numeric
  [[ "$pid" =~ ^[0-9]+$ ]]

  # Process should exist
  kill -0 "$pid" 2>/dev/null

  # Cleanup
  kill_mock_process "$pid"
}

@test "get_server_port returns valid port from running server" {
  require_command python3
  require_command lsof

  pid=$(create_real_server)

  # Give server more time to bind to port
  sleep 0.3

  # Get port
  port=$(get_server_port "$pid")

  # Port should be numeric
  [[ "$port" =~ ^[0-9]+$ ]]

  # Port should be in valid range
  [ "$port" -ge 1 ]
  [ "$port" -le 65535 ]

  # Cleanup
  kill_mock_process "$pid"
}

@test "get_server_port fails for non-listening process" {
  require_command lsof

  # Create a short-lived process that doesn't listen on any port
  pid=$(create_mock_process 1)

  # Should fail (return non-zero)
  # Note: Can't use `run get_server_port` because require_command's skip won't work inside run
  if get_server_port "$pid" >/dev/null 2>&1; then
    kill_mock_process "$pid"
    return 1  # Should have failed
  fi

  # Cleanup
  kill_mock_process "$pid"
}

@test "get_server_port fails for invalid PID" {
  require_command lsof

  # Use a PID that definitely doesn't exist
  # Note: Can't use `run get_server_port` because require_command's skip won't work inside run
  if get_server_port 999999999 >/dev/null 2>&1; then
    return 1  # Should have failed
  fi
}
