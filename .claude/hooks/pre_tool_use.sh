#!/bin/bash
# CCEM APM Pre-Tool-Use Hook — SFA v4.7.0
# Reports tool invocation to APM heartbeat.
# For Write/Edit/MultiEdit: additionally tracks skill invocation via /api/skills/track.

APM_URL="http://localhost:3032"
AGENT_ID="${CLAUDE_AGENT_ID:-session-unknown}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-unknown}"
FILE_PATH="${CLAUDE_TOOL_FILE_PATH:-}"

# Always: heartbeat
curl -s -X POST "$APM_URL/api/heartbeat" \
  -H "Content-Type: application/json" \
  -d "{
    \"agent_id\": \"$AGENT_ID\",
    \"status\": \"working\",
    \"message\": \"Tool: $TOOL_NAME\"
  }" >/dev/null 2>&1 &

# Write/Edit/MultiEdit: track as skill invocation
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
  curl -s -X POST "$APM_URL/api/skills/track" \
    -H "Content-Type: application/json" \
    -d "{
      \"skill\": \"file-write\",
      \"tool\": \"$TOOL_NAME\",
      \"agent_id\": \"$AGENT_ID\",
      \"file_path\": \"$FILE_PATH\",
      \"project\": \"sfa\"
    }" >/dev/null 2>&1 &
fi
