#!/bin/bash
# CCEM APM Post-Commit Hook
# Fires after git commit. Reports commit event to APM notify + upm/event.
# Install: cp post_commit.sh .git/hooks/post-commit && chmod +x .git/hooks/post-commit

APM_URL="http://localhost:3032"
AGENT_ID="${CLAUDE_AGENT_ID:-sfa-session}"
FORMATION_ID="${UPM_FORMATION_ID:-fmt-20260318-SFA-MOD}"

COMMIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
COMMIT_MSG="$(git log -1 --pretty=%s 2>/dev/null | head -c 120 | sed 's/"/\\"/g')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
FILES_CHANGED="$(git diff-tree --no-commit-id -r --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')"

curl -s -X POST "$APM_URL/api/notify" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"info\",
    \"title\": \"Git Commit — SFA\",
    \"message\": \"[$COMMIT_SHA] $COMMIT_MSG ($FILES_CHANGED files on $BRANCH)\",
    \"category\": \"upm\",
    \"agent_id\": \"$AGENT_ID\"
  }" >/dev/null 2>&1 &

curl -s -X POST "$APM_URL/api/upm/event" \
  -H "Content-Type: application/json" \
  -d "{
    \"event_type\": \"task_complete\",
    \"agent_id\": \"$AGENT_ID\",
    \"formation_id\": \"$FORMATION_ID\",
    \"payload\": {
      \"commit_sha\": \"$COMMIT_SHA\",
      \"branch\": \"$BRANCH\",
      \"files_changed\": $FILES_CHANGED,
      \"message\": \"$COMMIT_MSG\"
    }
  }" >/dev/null 2>&1 &
