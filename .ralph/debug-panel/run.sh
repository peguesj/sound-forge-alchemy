#!/bin/bash
# Runner for Ralph debug-panel feature
# Pattern: symlink prd.json + progress.txt from isolated run dir to project root
# so that spawned Claude Code instances find them at cwd. Cleanup on exit.
set -e

PROJECT_ROOT="/Users/jeremiah/Developer/sfa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Symlink prd.json and progress.txt to project root
ln -sf "$SCRIPT_DIR/prd.json" "$PROJECT_ROOT/prd.json"
touch "$SCRIPT_DIR/progress.txt"
ln -sf "$SCRIPT_DIR/progress.txt" "$PROJECT_ROOT/progress.txt"

# Cleanup symlinks on exit (success or failure)
cleanup() {
  rm -f "$PROJECT_ROOT/prd.json" "$PROJECT_ROOT/progress.txt"
  echo "Cleaned up symlinks from project root"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"
env -u CLAUDECODE "$SCRIPT_DIR/ralph.sh" --tool claude 20

osascript -e 'display notification "SFA Debug Panel + Oban Logging build complete -- 10 user stories" with title "Ralph" sound name "Glass"'
