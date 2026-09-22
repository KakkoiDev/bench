#!/bin/sh
# Lifecycle helper: start and stop the service under test.
PORT="${PORT:-8099}"
PIDFILE=.server.pid
case "$1" in
  start)
    python3 -m http.server "$PORT" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    # Wait for the port to accept connections rather than sleeping blindly
    i=0
    while [ "$i" -lt 50 ]; do
      curl -fsS "http://localhost:$PORT/" -o /dev/null 2>/dev/null && exit 0
      i=$((i + 1))
      sleep 0.1
    done
    echo "server did not start" >&2
    exit 1
    ;;
  stop)
    [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
    ;;
esac
