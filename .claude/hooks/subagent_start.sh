#!/usr/bin/env bash
# subagent_start.sh — Register subagent spawn with APM
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
AGENT_ID="${CLAUDE_AGENT_ID:-${PARENT_TOOL_USE_ID:-unknown}}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
AGENT_TYPE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('subagent_type','unknown'))" 2>/dev/null || echo "unknown")

curl -s -X POST "$APM/api/agents/subagent-start" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"agent_id\":\"$AGENT_ID\",\"agent_type\":\"$AGENT_TYPE\",\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
