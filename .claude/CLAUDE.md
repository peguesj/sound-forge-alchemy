# Sound Forge Alchemy - Project CLAUDE.md

## Project Context

Sound Forge Alchemy (SFA) is an audio stem separation and analysis tool built with Phoenix 1.8. Users paste Spotify URLs, the app fetches metadata from Spotify's Web API, downloads audio via spotdl, separates stems using Demucs (Python), analyzes audio features via librosa (Python), and displays everything in a real-time LiveView dashboard.

**Domain**: Audio engineering / music production tooling.
**Origin**: Ported from a Node.js/TypeScript microservices architecture to a single Phoenix OTP release.

## Tech Stack

- **Elixir 1.15+** / **Phoenix 1.8** / **LiveView 1.1**
- **Ecto 3.13** with PostgreSQL (binary_id UUIDs)
- **Oban 2.18** for background job processing (replaces Redis + custom job queue)
- **Erlang Ports** for Python interop (Demucs, librosa)
- **Req** for HTTP requests (Spotify API, downloads)
- **Tailwind CSS v4** (no tailwind.config.js, uses `@import "tailwindcss"` syntax in app.css)
- **Bandit** HTTP server
- **Mox** for test mocking
- **Jason** for JSON encoding/decoding

## Key Architectural Decisions

### Database as Source of Truth
All job state lives in PostgreSQL, not in memory. Every status transition is persisted via Ecto before broadcasting via PubSub. If the server crashes, job state survives in the database.

### Oban for Background Jobs
Oban replaces the Redis-based job queue from the TypeScript backend. Three queues are configured:
- `download` (concurrency: 3) - Audio downloads via spotdl
- `processing` (concurrency: 2) - Stem separation via Demucs
- `analysis` (concurrency: 2) - Audio feature extraction via librosa

### Erlang Ports for Python
Python tools (Demucs, librosa) run as supervised Erlang Ports via GenServer wrappers, NOT as HTTP microservices. The Port protocol uses JSON over stdin/stdout:
- `SoundForge.Audio.AnalyzerPort` - librosa-based audio analysis
- `SoundForge.Audio.DemucsPort` - Demucs stem separation

### Phoenix.PubSub for Real-Time Updates
PubSub replaces Socket.IO from the Node.js backend. Workers broadcast job progress on topic `"jobs:{job_id}"`, and the DashboardLive subscribes to `"tracks"` for new track additions.

### Contexts as Boundaries
Phoenix contexts (`Music`, `Spotify`, `Jobs.*`, `Storage`) encapsulate business logic. Controllers and LiveViews never call `Repo` directly.

## Code Conventions

### Schema Conventions
- **All schemas use `binary_id` UUIDs** as primary keys:
  ```elixir
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  ```
- **Status fields use `Ecto.Enum`**:
  ```elixir
  field :status, Ecto.Enum, values: [:queued, :downloading, :processing, :completed, :failed]
  ```
- **Timestamps use `:utc_datetime`**:
  ```elixir
  timestamps(type: :utc_datetime)
  ```

### Return Value Conventions
All context functions return tagged tuples:
```elixir
{:ok, %Track{}}        # Success
{:error, %Changeset{}} # Validation failure
{:error, :not_found}   # Missing resource
{:error, reason}       # Other failures
```

The only exception is bang functions (`get_track!`) which raise on failure.

### Naming Conventions
- Contexts: `SoundForge.Music`, `SoundForge.Spotify`, `SoundForge.Jobs.Download`
- Schemas: `SoundForge.Music.Track`, `SoundForge.Music.Stem`
- LiveViews: `SoundForgeWeb.DashboardLive` (with `Live` suffix)
- Controllers: `SoundForgeWeb.API.SpotifyController` (under `API` namespace for JSON endpoints)
- Workers: `SoundForge.Jobs.DownloadWorker`
- Ports: `SoundForge.Audio.AnalyzerPort`, `SoundForge.Audio.DemucsPort`

### File Organization
```
lib/sound_forge/           # Business logic (contexts + schemas)
  music.ex                 # Music context (CRUD for all schemas)
  music/                   # Schema modules (Track, Stem, etc.)
  spotify.ex               # Spotify context (fetch_metadata/1)
  spotify/                 # URL parser, HTTP client, Client behaviour
  audio/                   # Erlang Port GenServers
  jobs/                    # Job contexts (Download, Processing, Analysis) + Oban workers
  processing/              # Demucs model configuration
  storage.ex               # File management
lib/sound_forge_web/       # Web layer
  router.ex                # All routes
  live/                    # LiveView modules
  controllers/api/         # JSON API controllers
  channels/                # WebSocket channels
  components/              # CoreComponents, Layouts
```

## Testing

### Test Framework
- **ExUnit** with `Ecto.Adapters.SQL.Sandbox` for database isolation
- **Mox** for Spotify API mocking (defined in `test/test_helper.exs`)
- **Oban.Testing** with `testing: :manual` mode (configured in `config/test.exs`)
- **Phoenix.LiveViewTest** for LiveView testing
- **LazyHTML** for HTML assertions

### Mox Setup
The Spotify client uses a behaviour (`SoundForge.Spotify.Client`) with a mock defined in `test/test_helper.exs`:
```elixir
Mox.defmock(SoundForge.Spotify.MockClient, for: SoundForge.Spotify.Client)
```
The mock is swapped in via `config/test.exs`:
```elixir
config :sound_forge, :spotify_client, SoundForge.Spotify.MockClient
```

### Oban Testing
Workers are tested with `Oban.Testing`:
```elixir
use Oban.Testing, repo: SoundForge.Repo

assert_enqueued(worker: SoundForge.Jobs.DownloadWorker, args: %{track_id: track.id})
```

### Running Tests
```bash
mix test                          # Run all tests
mix test test/sound_forge/        # Run context tests only
mix test test/sound_forge_web/    # Run web tests only
mix test --failed                 # Re-run previously failed tests
mix test path/to/test.exs:42     # Run specific test at line
```

### Pre-Commit
```bash
mix precommit  # compile --warnings-as-errors, deps.unlock --unused, format, test
```

## Common Mistakes to Avoid

### DO NOT
- Call `Repo` from controllers or LiveViews -- always go through contexts
- Use `any` types -- Elixir is dynamically typed but be explicit with `@spec` and `@type`
- Use `String.to_atom/1` on user input (memory leak risk)
- Use `Process.sleep/1` in tests -- use `Process.monitor/1` + `assert_receive`
- Use `phx-update="append"` or `phx-update="prepend"` -- use streams
- Write inline `<script>` tags in HEEx -- use colocated JS hooks (`:type={Phoenix.LiveView.ColocatedHook}`)
- Use `@apply` in CSS -- write Tailwind classes directly
- Use `<.form let={f}>` -- use `<.form for={@form}>` with `to_form/2`
- Nest multiple modules in the same file
- Access struct fields with map syntax (`changeset[:field]`) -- use `Changeset.get_field/2` or `struct.field`

### DO
- Always preload associations when they will be accessed in templates
- Use `stream/3` for collections in LiveViews, never assign raw lists
- Return `{:ok, _} | {:error, _}` tuples from context functions
- Use `Ecto.Enum` for status fields with predefined values
- Validate UUIDs with `Ecto.UUID.cast/1` before database lookups
- Use `Phoenix.PubSub.broadcast/3` for real-time updates from workers
- Use `File.mkdir_p!/1` before writing files
- Use `start_supervised!/1` to start processes in tests

## How to Add New Features

Follow this sequence:

1. **Schema** (if new data): `lib/sound_forge/music/new_thing.ex`
   - Define with `binary_id`, `Ecto.Enum` for statuses, `utc_datetime` timestamps
   - Generate migration: `mix ecto.gen.migration create_new_things`

2. **Context** (business logic): Add functions to `lib/sound_forge/music.ex` or create `lib/sound_forge/new_context.ex`
   - CRUD operations returning `{:ok, _} | {:error, _}`
   - Add `@doc` and `@spec` annotations

3. **Worker** (if background job): `lib/sound_forge/jobs/new_worker.ex`
   - `use Oban.Worker, queue: :queue_name, max_attempts: 3`
   - Implement `perform/1` callback
   - Broadcast progress via PubSub

4. **Controller** (if JSON API): `lib/sound_forge_web/controllers/api/new_controller.ex`
   - Route in `router.ex` under `/api` scope
   - Call context functions, never Repo directly

5. **LiveView** (if UI): `lib/sound_forge_web/live/new_live.ex` + `.html.heex`
   - Route in `router.ex` under `/` browser scope
   - Subscribe to PubSub topics in `mount/3` when `connected?/1`
   - Use streams for collections

6. **Tests**: Mirror the lib/ structure under `test/`
   - Context tests in `test/sound_forge/`
   - Controller tests in `test/sound_forge_web/controllers/`
   - LiveView tests in `test/sound_forge_web/live/`

7. **Verify**: `mix precommit` (compile with warnings-as-errors, format, test)

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/sound_forge/application.ex` | OTP supervision tree (Repo, PubSub, Oban, Endpoint) |
| `lib/sound_forge/music.ex` | Central Music context (all CRUD operations) |
| `lib/sound_forge/spotify.ex` | Spotify metadata fetching with behaviour-based client |
| `lib/sound_forge/audio/analyzer_port.ex` | GenServer wrapping librosa Python script |
| `lib/sound_forge/audio/demucs_port.ex` | GenServer wrapping Demucs Python script |
| `lib/sound_forge/jobs/download_worker.ex` | Oban worker for audio downloads |
| `lib/sound_forge/storage.ex` | Local filesystem storage management |
| `lib/sound_forge_web/router.ex` | All routes (browser + API) |
| `lib/sound_forge_web/live/dashboard_live.ex` | Main LiveView dashboard |
| `config/config.exs` | Oban queue config, Ecto settings |
| `config/test.exs` | Mock client config, Oban testing mode |
| `test/test_helper.exs` | Mox mock definitions |
| `priv/python/analyzer.py` | librosa audio analysis script |
| `priv/python/demucs_runner.py` | Demucs stem separation wrapper |

## Hooks (Project-Level)

### Dev Server Management
- **Script**: `.claude/hooks/dev_server_mgmt.sh`
- **Trigger**: PreToolUse hook on `Bash|Task` (configured in `.claude/settings.json`)
- **Behavior**: Detects server status on port 4000. If stopped, starts it. If stalled (process exists but not responding to HTTP), restarts it. If running, writes PID to state file.
- **State file**: `.claude/hooks/data/dev_server.json` -- JSON with `pid`, `port`, `status`, `updated_at`, `log_file`. Readable by external tools and TTY sessions.
- **Cooldown**: 30 seconds between checks to avoid excessive overhead.
- **Skill**: `/dev-server-mgmt` -- manages server lifecycle (status, start, stop, restart, pid, logs, ensure).
- **Authority**: Project-level hook. User-level disk space hook at `~/.claude/hooks/disk_space_check.sh` (referenced in root CLAUDE.md) takes precedence for disk concerns.

## Feature: Melodics/MPC App/TouchOSC/Responsive (feat/melodics-mpc-touchosc-responsive)

### New Modules

#### OSC Layer (`lib/sound_forge/osc/`)
| Module | Purpose |
|--------|---------|
| `SoundForge.OSC.Server` | GenServer UDP listener (default port 8000). Broadcasts `{:osc_message, msg, sender}` on `"osc:messages"` PubSub. |
| `SoundForge.OSC.Client` | Sends OSC messages to TouchOSC via ephemeral UDP socket. `send/4: (host, port, address, args)` |
| `SoundForge.OSC.Parser` | Minimal OSC 1.0 encode/decode. Supports `f`, `i`, `s`, `b` type tags and bundle parsing. |
| `SoundForge.OSC.TouchOSCLayout` | Generates TouchOSC `.tosc` ZIP layout XML (8 stem faders, mute/solo, transport, BPM, title). |
| `SoundForge.OSC.ActionExecutor` | Routes OSC addresses to SFA PubSub actions (`/stem/{n}/volume`, `/transport/*`). Sends feedback OSC back to TouchOSC. |
| `SoundForge.OSC.Pipeline` | E2E simulation: `simulate_osc/3`, `test_pipeline/3`, `benchmark/2`. Used for latency testing. |

#### Bridge (`lib/sound_forge/bridge/`)
| Module | Purpose |
|--------|---------|
| `SoundForge.Bridge.MidiOsc` | Bidirectional MIDI<->OSC translation. CC 7-14 ↔ `/stem/{n}/volume`. Configurable via `set_mapping/1`. |

#### Integrations (`lib/sound_forge/integrations/`)
| Module | Purpose |
|--------|---------|
| `SoundForge.Integrations.Melodics` | Imports practice sessions from Melodics local data dir. `import_sessions/1`, `list_sessions/2`, `get_stats/1`. |
| `SoundForge.Integrations.Melodics.MelodicsSession` | Ecto schema for melodics_sessions table. FK to users (integer, not binary_id). |
| `SoundForge.Integrations.Melodics.PracticeAdapter` | Maps Melodics accuracy → stem difficulty (simple/<60%, matched/60-85%, complex/>85%). `suggest_stems/2`. |

#### MIDI Profiles (`lib/sound_forge/midi/profiles/`)
| Module | Purpose |
|--------|---------|
| `SoundForge.MIDI.Profiles.MPCApp` | Detects MPC Beats/MPC 2.0/iMPC Pro 2 by port name pattern. Multi mode aware (Port A-D). |

#### Mix Tasks (`lib/mix/tasks/`)
| Task | Purpose |
|------|---------|
| `mix sfa.touchosc.generate` | Generates `priv/touchosc/sfa_mixer.tosc` (ZIP with index.xml). Requires no deps. |

### New LiveView Components (`lib/sound_forge_web/live/components/`)
| Component | Purpose |
|-----------|---------|
| `MobileNav` | Bottom nav bar (`md:hidden`) with Library/Player/MIDI/Settings tabs. 44px touch targets. |
| `MobileDrawer` | Slide-out drawer with overlay backdrop for mobile sidebar replacement. |
| `StemMixer` | Touch-optimized vertical faders with mute/solo buttons. Works with `StemMixerHook`. |
| `TrackDetailResponsive` | Tab navigation with swipe support (`SwipeHook`). Accordion stem list on mobile. |
| `PadAssignment` | 4x4 MPC pad grid with drag-and-drop stem assignment via `PadAssignHook`. |
| `ControlSurfacesSettings` | OSC/MIDI/MPC settings tabs added to SettingsLive. Bridge toggle. |
| `MidiOscStatusBar` | Header status bar: MIDI device count, OSC dot, TouchOSC target, activity bars. |

### New Routes
| Route | Module | Notes |
|-------|--------|-------|
| `/practice` | `PracticeLive` | Melodics session history, accuracy trends, stem recommendations, import button |

### New JS Hooks (`assets/js/hooks/`)
| Hook | Purpose |
|------|---------|
| `StemMixerHook` | Touch + mouse fader control, 60fps throttle, orientation detection, `stem_volume_update` event |
| `SwipeHook` | Horizontal swipe detection → pushes `swipe` event with direction |
| `ResizeObserverHook` | Container dimension tracking → pushes `chart_resized` event for D3 redraws |
| `PadAssignHook` | Drag-and-drop + touch for pad assignment → pushes `assign_pad` event |

### New Static Assets
| File | Purpose |
|------|---------|
| `priv/static/manifest.json` | PWA manifest (standalone display, purple theme, 192/512px icons) |
| `priv/static/sw.js` | Service worker: network-first for navigation, cache-first for assets |

### Database Changes
| Migration | Table | Notes |
|-----------|-------|-------|
| `20260219220000_create_melodics_sessions.exs` | `melodics_sessions` | FK to users (integer PK), binary_id own PK |

### PubSub Topics Added
- `osc:messages` — OSC messages from UDP server: `{:osc_message, %{address, args}, {ip, port}}`
- `midi:bridge` — MIDI messages originating from OSC translation: `{:midi_from_osc, msg}`
- `track_playback` — Unified playback actions: `{:action, :play/:stop}`, `{:stem_volume, n, float}`, `{:stem_mute, n, bool}`, `{:stem_solo, n, bool}`

## Implementation Checkpoints

### Feature: Melodics/MPC App/TouchOSC/Responsive (feat/melodics-mpc-touchosc-responsive)

#### Wave 1 - Foundation
- [x] **CP-01**: OSC server and client for TouchOSC communication (US-001)
- [x] **CP-04**: Akai MPC app MIDI profile and controller mode detection (US-004)
- [x] **CP-05**: Melodics practice session data import (US-005)
- [x] **CP-07**: Responsive layout: mobile-first dashboard redesign (US-007)
- After CP-07: `mix compile --warnings-as-errors` passes, all Wave 1 modules compile

#### Wave 2 - Integration Layer
- [x] **CP-02**: MIDI-OSC bridge for bidirectional protocol translation (US-002)
- [x] **CP-03**: TouchOSC layout generator for SFA stem mixer (US-003)
- [x] **CP-06**: Melodics-SFA practice mode with stem difficulty adaptation (US-006)
- [x] **CP-08**: Responsive layout: stem mixer touch interface (US-008)
- [x] **CP-09**: Responsive layout: track detail and analysis views (US-009)
- After CP-09: `mix compile --warnings-as-errors` passes, bridge and responsive views functional

#### Wave 3 - Feature Completion
- [x] **CP-10**: OSC action executor connecting TouchOSC to SFA playback (US-010)
- [x] **CP-11**: MPC pad-stem assignment UI with drag-and-drop (US-011)
- [x] **CP-12**: Melodics practice dashboard LiveView page (US-012)
- [x] **CP-13**: Control surface settings page with OSC/MIDI/MPC config (US-013)
- [x] **CP-16**: PWA manifest and service worker for mobile install (US-016)
- After CP-16: `mix compile --warnings-as-errors` passes, all features wired

#### Wave 4 - Polish & E2E
- [x] **CP-14**: Dashboard MIDI/OSC status bar with activity indicators (US-014)
- [x] **CP-15**: End-to-end integration: TouchOSC fader -> stem volume -> UI update (US-015)
- After CP-15: Full pipeline verified, `mix test` passes (653 tests, 0 failures)

## Agentic Complexity Tree View Requirement

When any request involves agentic complexity (UPM, Formation, agent deployment), ALWAYS display a `tree`-style hierarchical view of the planned structure BEFORE execution. This applies to /upm build, /formation deploy, /deploy:agents-v2, /ralph story mapping, /plane-pm issue creation, and any todo/task list with concurrent work. No exceptions.

Referenced systems: UPM, Plane PM, Plan mode, Ralph PRD, Formation, Todo/TaskList.

## Plane Project
- **Project**: Sound Forge Alchemy (SFA)
- **Project ID**: `6f35c181-4a86-476d-bb2a-fba869f68918`
- **Workspace**: lgtm
- **URL**: https://plane.lgtm.build/lgtm/projects/6f35c181-4a86-476d-bb2a-fba869f68918/
