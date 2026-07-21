#!/usr/bin/env bash
# agentlock_post_tool.sh — Record tool completion in AgentLock
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
TOOL_USE_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_use_id',''))" 2>/dev/null || echo "")

curl -s -X POST "$APM/api/v2/auth/complete" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"tool_name\":\"$TOOL\",\"tool_use_id\":\"$TOOL_USE_ID\",\"session_id\":\"$SESSION_ID\",\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
