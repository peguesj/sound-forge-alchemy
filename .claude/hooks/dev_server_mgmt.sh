#!/usr/bin/env bash
# Dev Server Management Hook for SFA
# Detects server status, starts/restarts as needed, reports PID.
# Usage:
#   bash .claude/hooks/dev_server_mgmt.sh [status|start|stop|restart|ensure]
#
# When invoked as a hook (no args or "ensure"), it auto-manages the server.
# PID is stored in .claude/hooks/data/dev_server.json for external consumption.

set -euo pipefail

PROJECT_DIR="/Users/jeremiah/Developer/sfa"
PORT=4000
PID_STATE_FILE="${PROJECT_DIR}/.claude/hooks/data/dev_server.json"
LOG_DIR="${PROJECT_DIR}/.claude/hooks/logs"
LOG_FILE="${LOG_DIR}/dev_server.log"
COOLDOWN_FILE="/tmp/.sfa-dev-server-check-last-run"
COOLDOWN_SECONDS=30

mkdir -p "$(dirname "$PID_STATE_FILE")" "$LOG_DIR"

# --- Helpers ---

get_server_pid() {
  lsof -ti:"${PORT}" 2>/dev/null | head -1 || true
}

is_server_responding() {
  curl -sf -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${PORT}/" 2>/dev/null | grep -qE "^(200|302)$"
}

write_state() {
  local pid="$1"
  local status="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$PID_STATE_FILE" <<EOF
{
  "pid": ${pid:-null},
  "port": ${PORT},
  "status": "${status}",
  "project": "${PROJECT_DIR}",
  "updated_at": "${timestamp}",
  "log_file": "${LOG_FILE}"
}
EOF
}

report() {
  echo "$1" >&2
}

start_server() {
  report "[dev-server-mgmt] Starting Phoenix dev server on port ${PORT}..."
  cd "$PROJECT_DIR"
  nohup bash -c 'cd '"$PROJECT_DIR"' && MIX_ENV=dev mix phx.server' \
    >> "$LOG_FILE" 2>&1 &
  local new_pid=$!
  disown "$new_pid" 2>/dev/null || true

  # Wait briefly for port to bind
  local attempts=0
  while [ $attempts -lt 15 ]; do
    sleep 1
    local bound_pid
    bound_pid=$(get_server_pid)
    if [ -n "$bound_pid" ]; then
      write_state "$bound_pid" "running"
      report "[dev-server-mgmt] Server started. PID=${bound_pid} PORT=${PORT}"
      return 0
    fi
    attempts=$((attempts + 1))
  done

  write_state "null" "failed_to_start"
  report "[dev-server-mgmt] ERROR: Server failed to bind to port ${PORT} within 15s"
  return 1
}

stop_server() {
  local pid
  pid=$(get_server_pid)
  if [ -n "$pid" ]; then
    report "[dev-server-mgmt] Stopping server PID=${pid}..."
    kill "$pid" 2>/dev/null || true
    sleep 2
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    write_state "null" "stopped"
    report "[dev-server-mgmt] Server stopped."
  else
    write_state "null" "stopped"
    report "[dev-server-mgmt] No server running on port ${PORT}."
  fi
}

status_server() {
  local pid
  pid=$(get_server_pid)
  if [ -z "$pid" ]; then
    write_state "null" "stopped"
    report "[dev-server-mgmt] Status: STOPPED (no process on port ${PORT})"
    return 1
  fi

  if is_server_responding; then
    write_state "$pid" "running"
    report "[dev-server-mgmt] Status: RUNNING PID=${pid} PORT=${PORT}"
    return 0
  else
    write_state "$pid" "stalled"
    report "[dev-server-mgmt] Status: STALLED PID=${pid} (process exists but not responding)"
    return 2
  fi
}

restart_server() {
  stop_server
  sleep 1
  start_server
}

ensure_server() {
  # Cooldown check for hook invocations
  if [ -f "$COOLDOWN_FILE" ]; then
    local last_run now elapsed
    last_run=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    elapsed=$((now - last_run))
    if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
      # Still within cooldown, just report current state silently
      local pid
      pid=$(get_server_pid)
      if [ -n "$pid" ]; then
        write_state "$pid" "running"
      fi
      exit 0
    fi
  fi
  date +%s > "$COOLDOWN_FILE"

  local pid
  pid=$(get_server_pid)

  if [ -z "$pid" ]; then
    report "[dev-server-mgmt] Server not running. Starting..."
    start_server
  elif is_server_responding; then
    write_state "$pid" "running"
    report "[dev-server-mgmt] Server healthy. PID=${pid} PORT=${PORT}"
  else
    report "[dev-server-mgmt] Server stalled (PID=${pid}). Restarting..."
    restart_server
  fi
}

# --- Main ---

ACTION="${1:-ensure}"

case "$ACTION" in
  status)
    status_server
    ;;
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    restart_server
    ;;
  ensure|hook)
    ensure_server
    ;;
  pid)
    pid=$(get_server_pid)
    if [ -n "$pid" ]; then
      echo "$pid"
    else
      echo "none"
      exit 1
    fi
    ;;
  *)
    report "Usage: $0 [status|start|stop|restart|ensure|pid]"
    exit 1
    ;;
esac
