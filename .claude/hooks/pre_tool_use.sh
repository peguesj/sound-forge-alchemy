#!/usr/bin/env bash
# pre_tool_use.sh — APM pre-tool telemetry
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
TOOL=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")

curl -s -X POST "$APM/api/telemetry/pre-tool" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"tool\":\"$TOOL\",\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
