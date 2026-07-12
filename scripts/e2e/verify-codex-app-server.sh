#!/bin/bash
set -euo pipefail
PORT="${1:-14500}"
LOG="${TMPDIR:-/tmp}/morphling-codex-app-server.log"
codex app-server --listen "ws://127.0.0.1:$PORT" >"$LOG" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true' EXIT
ready=0
for _ in {1..100}; do
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.05
done
if [[ "$ready" != 1 ]]; then cat "$LOG" >&2; exit 1; fi
.build/debug/CodexInitializeProbe "ws://127.0.0.1:$PORT"
echo "Codex app-server initialize: PASS"
