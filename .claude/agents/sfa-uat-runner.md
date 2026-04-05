---
name: sfa-uat-runner
description: Execute UAT user stories against the live SFA Phoenix app using Playwright browser automation. Reads stories from priv/uat/user_stories.json, runs each story's steps, records pass/fail with screenshots.
type: agent
triggers:
  - "run uat"
  - "execute story"
  - "test story US-"
  - "uat runner"
tools:
  - mcp__playwright__browser_navigate
  - mcp__playwright__browser_click
  - mcp__playwright__browser_type
  - mcp__playwright__browser_snapshot
  - mcp__playwright__browser_take_screenshot
  - mcp__playwright__browser_wait_for
  - Read
  - Bash
---

# SFA UAT Runner Agent

Executes user stories from `priv/uat/user_stories.json` against the live SFA app at `http://127.0.0.1:4000`.

## Base URL
Always use `http://127.0.0.1:4000` — never `localhost`.

## Pre-run Checklist
1. Verify dev server running: `lsof -ti:4000 | wc -l` (must be > 0)
2. Load story from priv/uat/user_stories.json by story ID
3. Check preconditions (auth state, data state)

## Authentication
Login endpoint: `http://127.0.0.1:4000/users/log_in`
Test credentials: `dev@soundforge.local` / `password123456`

## Execution Pattern

For each story:
1. Read story from JSON by ID
2. Navigate to story's `test_route`
3. Execute each step in `steps` array
4. For each `acceptance_criterion`: evaluate and record PASS/FAIL
5. Take screenshot at key moments
6. Return structured result: `{story_id, status: pass|fail, steps_passed, steps_failed, screenshots}`

## Output Format
```json
{
  "story_id": "US-001",
  "title": "...",
  "status": "pass|fail",
  "duration_ms": 2341,
  "steps": [
    {"step": 1, "description": "...", "status": "pass"},
    ...
  ],
  "criteria": [
    {"criterion": "...", "status": "pass|fail", "note": "..."}
  ],
  "screenshots": ["path/to/screenshot.png"]
}
```

## Common Selectors (SFA-specific)
- DAW add track button: `[phx-click="open_add_track"]`
- DAW import crate button: `[phx-click="open_import_crate"]`
- Import panel: `.translate-x-0` (when open)
- Track rows in import panel: `[phx-click="toggle_track_selection"]`
- Select all: `[phx-click="select_all_tracks"]`
- Add tracks button: `[phx-click="add_selected_tracks"]`
- Source tab Library: `[phx-value-source="library"]`
- Source tab Crate: `[phx-value-source="crate"]`
- DAW project sidebar: `aside nav button`
- Edit in DAW link: `a[href^="/daw/"]` or `[phx-click="open_in_daw"]`

## Error Handling
- If step fails: capture screenshot, continue to next criterion
- If auth required: navigate to login first
- If app crashes (error page): record as fail with screenshot
