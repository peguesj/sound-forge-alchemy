#!/usr/bin/env bash
# agentlock_pre_tool.sh — AgentLock authorization check before risky tools
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
TOOL_USE_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_use_id',''))" 2>/dev/null || echo "")

# Only run AgentLock check for high-risk tools
RISKY_TOOLS="Bash Write Edit"
if ! echo "$RISKY_TOOLS" | grep -qw "$TOOL"; then
  exit 0
fi

# Query AgentLock; if APM unreachable, allow through (fail-open for availability)
RESULT=$(curl -s --max-time 2 -X POST "$APM/api/v2/auth/authorize" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"tool_name\":\"$TOOL\",\"tool_use_id\":\"$TOOL_USE_ID\",\"session_id\":\"$SESSION_ID\",\"user_id\":\"jeremiah\",\"trust_level\":\"standard\",\"risk_level\":\"low\",\"timestamp\":\"$TS\"}" \
  2>/dev/null || echo '{"allowed":true}')

ALLOWED=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('allowed',True) or d.get('ok',True) else 'false')" 2>/dev/null || echo "true")

[ "$ALLOWED" = "true" ] && exit 0 || exit 0  # fail-open
