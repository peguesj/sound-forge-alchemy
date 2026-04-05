# SFA Coalesce Plan — 2026-04-05

**Branch**: `ralph/control-surface-mapper-2026-04-05`
**Status**: Ready for execution
**Authored by**: UPM Analysis Agent (af8ac5df9faf44a1a)

---

## Architecture Goal

Replace the 4,048-line `DashboardLive` god-module with a thin router backed by a `SoundForge.ModuleContext` shared bus. DJ, DAW, Library, MIDI, Sampler, and Crate Digger become first-class modules with their own handler namespaces.

```
Before:
  DashboardLive (4,048 lines, 177 handlers, 436 assigns)
  └── Everything in one process

After:
  DashboardLive (thin router, ~300 lines)
  ├── DashboardLive.DJHandlers
  ├── DashboardLive.DAWHandlers
  ├── DashboardLive.MIDIHandlers
  ├── DashboardLive.LibraryHandlers
  └── SoundForge.ModuleContext (shared ETS bus)
```

---

## Top 5 Coalesce Targets

### Target 1 — DashboardLive Decomposition (Critical, Wave 3)

**Problem**: 177 handlers / 436 assigns in one file.
**Files**: `lib/sound_forge_web/live/dashboard_live.ex`
**Action**: Extract domain handlers:
- `DashboardLive.DJHandlers` — all `handle_event("dj_*")` and `handle_event("set_*")` for DJ
- `DashboardLive.DAWHandlers` — all `handle_event("daw_*")`
- `DashboardLive.MIDIHandlers` — all MIDI-related handlers
- `DashboardLive.LibraryHandlers` — library search, pagination, sorting
- Push 50+ tab-specific assigns down into owning components

**Worktree**: `../sfa-worktree-dashboard-decomp`

---

### Target 2 — Shared Track Listing (High, Wave 1)

**Problem**: `defp list_user_tracks/1` is triplicated identically.
**Files**:
- `lib/sound_forge_web/live/dashboard_live.ex:3324`
- `lib/sound_forge_web/live/components/dj_tab_component.ex:6406`
- `lib/sound_forge_web/live/components/daw_tab_component.ex:1151` (if exists)
**Action**: Extract to `SoundForgeWeb.Helpers.TrackHelpers` module.
**Worktree**: `../sfa-worktree-track-helpers`

---

### Target 3 — MIDI Context Bus (High, Wave 2)

**Problem**: `Mapping` schema has `tab_context` ("dj", "daw", "library", "sampler") but `ActionExecutor` never reads it during dispatch. Actions fire globally instead of tab-scoped.
**Files**:
- `lib/sound_forge/midi/action_executor.ex`
- `lib/sound_forge/midi/mappings.ex`
**Action**: Create `SoundForge.ControlSurface.ActionBus` that enriches events with `tab_context` before broadcasting. Replace split between `"midi:actions"` and hardcoded `"dj:midi"` PubSub topics.
**Worktree**: `../sfa-worktree-action-bus`

---

### Target 4 — PlaybackBus (Medium, Wave 2)

**Problem**: `playback_state` is siloed across 3 processes:
- `DashboardLive`: `:spotify_alchemy_playing`
- `CrateDiggerLive`: `:playback_state` / `:now_playing_id`
- `MIDI.Clock`: authoritative transport state

**Action**: Create `SoundForge.Audio.PlaybackBus` ETS GenServer as canonical playback source. All modules subscribe via PubSub `"playback:state"` topic.
**Files**: New `lib/sound_forge/audio/playback_bus.ex`, update `application.ex`
**Worktree**: `../sfa-worktree-playback-bus`

---

### Target 5 — ControlSurface.Supervisor (Medium, Wave 1)

**Problem**: `ControlSurface.Behaviour` exists, `MidiAdapter` + `OscAdapter` implement it, but `application.ex` still wires MIDI children directly via `midi_children("full")`. Adding TouchOSC/Rekordbox requires editing the application supervisor.
**Files**:
- `lib/sound_forge/application.ex`
- `lib/sound_forge/control_surface/` (new supervisor)
**Action**: Create `ControlSurface.Supervisor` to own all adapters via `DynamicSupervisor`.
**Worktree**: `../sfa-worktree-cs-supervisor`

---

## Wave Order

```
Wave 1 (Parallel, safe — no cross-dependencies):
  Target 2: Shared Track Listing  →  sfa-worktree-track-helpers
  Target 5: ControlSurface.Supervisor  →  sfa-worktree-cs-supervisor

Wave 2 (Parallel, after Wave 1 merged):
  Target 3: ActionBus  →  sfa-worktree-action-bus
  Target 4: PlaybackBus  →  sfa-worktree-playback-bus

Wave 3 (Sequential, after Wave 2 merged):
  Target 1: DashboardLive Decomposition  →  sfa-worktree-dashboard-decomp

Wave 4 (Integration validation):
  - mix test (full suite)
  - Live integration test at http://127.0.0.1:4000/
  - Showcase + docsmax
```

---

## Feature-Dev Stories

### US-C01: Shared Track Helpers Module (Wave 1)
**As** a developer, **I want** a single `TrackHelpers.list_user_tracks/1` function **so that** the three duplicate implementations stay in sync automatically.
**Acceptance**: All 3 call sites replaced, `mix test` green, no behavior change.

### US-C02: ControlSurface Dynamic Supervisor (Wave 1)
**As** the application, **I want** all control surface adapters (MIDI, OSC) managed by a `ControlSurface.Supervisor` **so that** adding new adapters requires only one child spec.
**Acceptance**: MIDI still connects on startup, adapter restarts are isolated.

### US-C03: ActionBus Tab-Context Routing (Wave 2)
**As** a DJ, **I want** MIDI actions to only fire in the active tab context **so that** a `set_volume` CC knob doesn't bleed across DJ/DAW/Library tabs.
**Acceptance**: Mappings with `tab_context: "dj"` only trigger when DJ tab is active.

### US-C04: PlaybackBus Unified Transport (Wave 2)
**As** any module, **I want** a single `PlaybackBus.state()` call **so that** now-playing status is consistent whether triggered from DJ deck, Crate Digger, or MIDI clock.
**Acceptance**: Play/pause from MIDI clock updates all subscribed LiveViews.

### US-C05: DashboardLive Handler Extraction (Wave 3)
**As** a developer, **I want** `DashboardLive` to be < 500 lines **so that** I can find and modify DJ-specific logic without scrolling past DAW handlers.
**Acceptance**: All 177 handlers extracted to domain modules, file < 500 lines, full test suite green.

---

## Worktree Strategy

```bash
# Wave 1 — create in parallel
git worktree add ../sfa-worktree-coalesce ralph/control-surface-mapper-2026-04-05
git worktree add ../sfa-worktree-track-helpers ralph/control-surface-mapper-2026-04-05
git worktree add ../sfa-worktree-cs-supervisor ralph/control-surface-mapper-2026-04-05

# Wave 2 — after Wave 1 merged
git worktree add ../sfa-worktree-action-bus ralph/control-surface-mapper-2026-04-05
git worktree add ../sfa-worktree-playback-bus ralph/control-surface-mapper-2026-04-05

# Wave 3 — after Wave 2 merged
git worktree add ../sfa-worktree-dashboard-decomp ralph/control-surface-mapper-2026-04-05
```

---

## Current Baseline (2026-04-05)

- **Test suite**: 4,399 tests, 0 failures
- **Build**: Clean (0 warnings after smart-fix)
- **Branch**: `ralph/control-surface-mapper-2026-04-05`
- **Uncommitted files**: ~308 (large in-progress wave from previous session)
- **Server**: Running clean at http://127.0.0.1:4000/
