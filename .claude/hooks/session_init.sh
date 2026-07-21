#!/usr/bin/env bash
# session_init.sh — Register session with APM on SessionStart
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
PROJECT=$(python3 -c "import json; print(json.load(open('/Users/jeremiah/Developer/viki/apm/apm_config.json')).get('active_project','unknown'))" 2>/dev/null || echo "unknown")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_BRANCH=$(git -C "${PWD}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Start APM server if not running
if ! curl -s --max-time 1 "$APM/health" >/dev/null 2>&1; then
  if [ -f "$HOME/Developer/ccem/apm-v4/mix.exs" ]; then
    cd "$HOME/Developer/ccem/apm-v4" && \
      nohup mix phx.server >> "$HOME/Developer/ccem/apm/hooks/apm_server.log" 2>&1 &
    sleep 2
  fi
fi

curl -s -X POST "$APM/api/sessions/register" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"project\":\"$PROJECT\",\"git_branch\":\"$GIT_BRANCH\",\"working_dir\":\"$PWD\",\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

curl -s -X POST "$APM/api/notify" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"type\":\"info\",\"title\":\"Session Started\",\"message\":\"Branch: $GIT_BRANCH | Project: $PROJECT\",\"category\":\"session\",\"session_id\":\"$SESSION_ID\"}" \
  >/dev/null 2>&1 &

exit 0
