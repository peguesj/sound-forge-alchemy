#!/bin/bash
# CCEM APM Session Init Hook — SFA project
# Registers SFA session with APM at localhost:3032
# Routes: POST /api/register, POST /api/notify, PATCH /api/projects

SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
VERSION=$(grep 'version:' /Users/jeremiah/Developer/sfa/mix.exs 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "unknown")

# Register session agent
curl -s -X POST http://localhost:3032/api/register \
  -H "Content-Type: application/json" \
  -d "{
    \"agent_id\": \"sfa-session-$SESSION_ID\",
    \"project\": \"SFA\",
    \"role\": \"session\",
    \"status\": \"active\",
    \"session_id\": \"$SESSION_ID\",
    \"task_subject\": \"SFA session on $BRANCH\",
    \"metadata\": {\"branch\": \"$BRANCH\", \"version\": \"$VERSION\", \"port\": 4000}
  }" >/dev/null 2>&1 &

# Update project context
curl -s -X PATCH http://localhost:3032/api/projects \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"SFA\",
    \"root\": \"/Users/jeremiah/Developer/sfa\",
    \"port\": 4000,
    \"branch\": \"$BRANCH\",
    \"version\": \"$VERSION\"
  }" >/dev/null 2>&1 &

# Toast: session started
curl -s -X POST http://localhost:3032/api/notify \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"info\",
    \"title\": \"SFA Session Started\",
    \"message\": \"Branch: $BRANCH | v$VERSION\",
    \"category\": \"skill\"
  }" >/dev/null 2>&1 &
