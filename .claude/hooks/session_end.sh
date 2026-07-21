#!/usr/bin/env bash
# session_end.sh — Notify APM of session end
set -uo pipefail

APM="http://localhost:3032"
SESSION_ID="${CLAUDE_SESSION_ID:-$(hostname)-$$}"
PROJECT=$(python3 -c "import json; print(json.load(open('/Users/jeremiah/Developer/viki/apm/apm_config.json')).get('active_project','unknown'))" 2>/dev/null || echo "unknown")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat 2>/dev/null || echo "{}")
STOP_REASON=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_reason','unknown'))" 2>/dev/null || echo "unknown")
USAGE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); u=d.get('usage',{}); print(u.get('input_tokens',0)+u.get('output_tokens',0))" 2>/dev/null || echo "0")

curl -s -X POST "$APM/api/sessions/end" \
  -H "Content-Type: application/json" \
  -H "X-Hook-Version: v9" \
  -d "{\"session_id\":\"$SESSION_ID\",\"project\":\"$PROJECT\",\"stop_reason\":\"$STOP_REASON\",\"total_tokens\":$USAGE,\"timestamp\":\"$TS\"}" \
  >/dev/null 2>&1 &

exit 0
