#!/bin/bash
# CCEM APM Version Release Notification Hook
# Fires after a git tag is pushed, notifying APM with full version context
# Usage: ./version_notify.sh <version_tag> [project_name]

set -euo pipefail

APM_PORT="${APM_PORT:-3032}"
APM_BASE="http://localhost:${APM_PORT}"
VERSION_TAG="${1:-}"
PROJECT_NAME="${2:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"

if [ -z "$VERSION_TAG" ]; then
  echo "Usage: $0 <version_tag> [project_name]"
  exit 1
fi

# Gather context
COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
AUTHOR=$(git log -1 --format='%an' 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null || echo "")

# Get previous tag for diff context
PREV_TAG=$(git tag --sort=-version:refname | grep -v "^${VERSION_TAG}$" | head -1 2>/dev/null || echo "")
if [ -n "$PREV_TAG" ]; then
  COMMIT_COUNT=$(git rev-list "${PREV_TAG}..${VERSION_TAG}" --count 2>/dev/null || echo "0")
  FILES_CHANGED=$(git diff --stat "${PREV_TAG}..${VERSION_TAG}" --shortstat 2>/dev/null | tail -1 || echo "")
else
  COMMIT_COUNT="unknown"
  FILES_CHANGED=""
fi

# Extract changelog entry if available
CHANGELOG_ENTRY=""
if [ -f "CHANGELOG.md" ]; then
  # Extract section between this version header and the next
  CLEAN_TAG="${VERSION_TAG#v}"
  CHANGELOG_ENTRY=$(awk "/^## \[${CLEAN_TAG}\]/,/^## \[/" CHANGELOG.md | head -20 | tail -n +2 | head -18 || echo "")
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 1. Send intake event (structured event for timeline/audit)
(curl -s -X POST "${APM_BASE}/api/intake" \
  -H "Content-Type: application/json" \
  -d "{
    \"source\": \"git_hooks\",
    \"event_type\": \"version_released\",
    \"metadata\": {
      \"project\": \"${PROJECT_NAME}\",
      \"version\": \"${VERSION_TAG}\",
      \"previous_version\": \"${PREV_TAG}\",
      \"commit_sha\": \"${COMMIT_SHA}\",
      \"branch\": \"${BRANCH}\",
      \"author\": \"${AUTHOR}\",
      \"commit_count\": ${COMMIT_COUNT},
      \"files_changed\": $(echo "$FILES_CHANGED" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null || echo '""'),
      \"timestamp\": \"${TIMESTAMP}\"
    }
  }" >/dev/null 2>&1) &

# 2. Send toast notification (visible in APM dashboard)
(curl -s -X POST "${APM_BASE}/api/notifications/add" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"success\",
    \"title\": \"${PROJECT_NAME} ${VERSION_TAG} Released\",
    \"message\": \"${COMMIT_COUNT} commits since ${PREV_TAG}. ${FILES_CHANGED}\",
    \"category\": \"release\",
    \"project\": \"${PROJECT_NAME}\",
    \"version\": \"${VERSION_TAG}\"
  }" >/dev/null 2>&1) &

# 3. Send UPM event if a formation was active
(curl -s -X POST "${APM_BASE}/api/upm/event" \
  -H "Content-Type: application/json" \
  -d "{
    \"event_type\": \"version_tagged\",
    \"agent_id\": \"release-${PROJECT_NAME}\",
    \"project\": \"${PROJECT_NAME}\",
    \"timestamp\": \"${TIMESTAMP}\",
    \"payload\": {
      \"version\": \"${VERSION_TAG}\",
      \"previous_version\": \"${PREV_TAG}\",
      \"commit_sha\": \"${COMMIT_SHA}\",
      \"commit_count\": ${COMMIT_COUNT},
      \"branch\": \"${BRANCH}\"
    }
  }" >/dev/null 2>&1) &

echo "APM notified: ${PROJECT_NAME} ${VERSION_TAG} (${COMMIT_COUNT} commits since ${PREV_TAG})"
