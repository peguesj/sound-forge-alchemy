#!/bin/bash
# CCEM APM Post-Compile Hook
# Fires after mix compile. Reports success or error to APM.
# Usage: called by mix alias or manually after compile.
# Exit code from compile is passed as first arg (or read from $MIX_EXIT_CODE).

APM_URL="http://localhost:3032"
AGENT_ID="${CLAUDE_AGENT_ID:-sfa-session}"
EXIT_CODE="${1:-${MIX_EXIT_CODE:-0}}"
PROJECT="sfa"

if [ "$EXIT_CODE" -ne 0 ]; then
  # Compile failed — create alert rule and notify
  curl -s -X POST "$APM_URL/api/notify" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"error\",
      \"title\": \"Compile Error — SFA\",
      \"message\": \"mix compile exited with code $EXIT_CODE\",
      \"category\": \"upm\",
      \"agent_id\": \"$AGENT_ID\"
    }" >/dev/null 2>&1 &

  curl -s -X POST "$APM_URL/api/v2/alerts/rules" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"compile-failure-$PROJECT\",
      \"description\": \"mix compile failed (exit $EXIT_CODE)\",
      \"severity\": \"error\",
      \"project\": \"$PROJECT\",
      \"agent_id\": \"$AGENT_ID\",
      \"condition\": \"compile_failure\",
      \"auto_resolve\": true
    }" >/dev/null 2>&1 &
else
  # Compile succeeded
  curl -s -X POST "$APM_URL/api/notify" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"success\",
      \"title\": \"Compile OK — SFA\",
      \"message\": \"mix compile passed\",
      \"category\": \"upm\",
      \"agent_id\": \"$AGENT_ID\"
    }" >/dev/null 2>&1 &
fi
