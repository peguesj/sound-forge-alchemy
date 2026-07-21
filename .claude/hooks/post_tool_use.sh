#!/usr/bin/env bash
# post_tool_use.sh — APM post-tool telemetry
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('exit_code',0))" 2>/dev/null || echo "0")

curl -s -X POST "$APM/api/telemetry/post-tool" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"tool\":\"$TOOL\",\"exit_code\":$EXIT_CODE,\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
