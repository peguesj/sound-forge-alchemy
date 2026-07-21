#!/usr/bin/env bash
# subagent_stop.sh — Record subagent completion in APM
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
AGENT_ID="${CLAUDE_AGENT_ID:-${PARENT_TOOL_USE_ID:-unknown}}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('exit_code',0))" 2>/dev/null || echo "0")

curl -s -X POST "$APM/api/agents/subagent-stop" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"agent_id\":\"$AGENT_ID\",\"exit_code\":$EXIT_CODE,\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
