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
| `lib/sound_forge/admin.ex` | Admin context: user mgmt, system stats, analytics, audit logging |
| `lib/sound_forge/admin/audit_log.ex` | AuditLog Ecto schema (binary_id PK, actor FK, action/resource/changes) |
| `lib/sound_forge/accounts/scope.ex` | Scope struct with role hierarchy, permission checks, feature gating |
| `lib/sound_forge_web/live/admin_live.ex` | Admin dashboard LiveView (6 tabs: overview/users/jobs/system/analytics/audit) |
| `lib/sound_forge_web/user_auth.ex` | Auth plugs incl. require_admin_user, require_role, require_active_user, require_feature |
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

## Feature: Admin Dashboard with SaaS Role Hierarchy (feature/admin-dashboard)

### New Modules

#### Admin Context (`lib/sound_forge/admin.ex`)
| Function | Purpose |
|----------|---------|
| `list_users/1` | Paginated user listing with search, role filter, status filter. Returns `%{users, total, page, per_page}`. |
| `update_user_role/3` | Change a single user's role. Audit-logged with old/new values. |
| `suspend_user/2` | Set user status to `:suspended`. Audit-logged. |
| `ban_user/2` | Set user status to `:banned`. Audit-logged. |
| `reactivate_user/2` | Set user status to `:active`. Audit-logged. |
| `bulk_update_role/3` | Batch role change via `Repo.update_all`. Audit-logged with user ID list. |
| `system_stats/0` | Aggregate counts: users, tracks, Oban job states, users by role, users by status. |
| `all_jobs/1` | Paginated Oban job listing with state filter. |
| `storage_stats/0` | Disk usage via `du -sh` on the storage directory. |
| `user_registrations_by_day/1` | 30-day user signup trend (DATE grouping). |
| `tracks_by_day/1` | 30-day track import trend (DATE grouping). |
| `pipeline_throughput/0` | Oban queue stats grouped by queue and state (download/processing/analysis). |
| `log_action/6` | Insert an `AuditLog` record. Called automatically by mutation functions. |
| `list_audit_logs/1` | Paginated audit log listing with action filter and search. |

#### AuditLog Schema (`lib/sound_forge/admin/audit_log.ex`)
| Field | Type | Notes |
|-------|------|-------|
| `id` | `:binary_id` | Auto-generated UUID PK |
| `actor_id` | `:id` (FK to users) | Who performed the action (nilable -- system actions have no actor) |
| `action` | `:string` | One of: `create`, `update`, `delete`, `suspend`, `ban`, `reactivate`, `role_change`, `bulk_role_change`, `config_update`, `feature_flag_toggle`, `login`, `logout` |
| `resource_type` | `:string` | e.g. `"user"` |
| `resource_id` | `:string` | ID of the affected resource |
| `changes` | `:map` | JSON payload with before/after values (e.g. `%{from: "user", to: "admin"}`) |
| `ip_address` | `:string` | Optional client IP for audit trail |

#### Scope Changes (`lib/sound_forge/accounts/scope.ex`)
| Addition | Purpose |
|----------|---------|
| `@role_hierarchy` | Ordered list: `[:user, :pro, :enterprise, :admin, :super_admin]` |
| `admin?` field | Boolean on Scope struct, true when role is `:admin` or `:super_admin` |
| `role_level/1` | Numeric index for role comparison |
| `has_role?/2` | Checks if scope meets minimum required role level |
| `can_manage_users?/1` | Requires `:admin` or above |
| `can_view_analytics?/1` | Requires `:admin` or above |
| `can_configure_system?/1` | Requires `:super_admin` only |
| `can_use_feature?/2` | Feature gating map: `:admin_dashboard` requires `:admin+`, `:feature_flags` and `:billing` require `:super_admin` |

#### AdminLive (`lib/sound_forge_web/live/admin_live.ex`)
| Tab | Data Source | Features |
|-----|-------------|----------|
| Overview | `Admin.system_stats/0` | Stat cards (users, tracks, active jobs, failed jobs), users by role/status breakdowns |
| Users | `Admin.list_users/1` | Search, role/status filters, inline role dropdown, suspend/ban/reactivate buttons, checkbox bulk selection, bulk role change, pagination |
| Jobs | `Admin.all_jobs/1` | State filter tabs (all/executing/available/retryable/discarded/completed), retry button |
| System | `Admin.storage_stats/0`, `Admin.system_stats/0` | Storage path and size, Oban queue breakdown, role distribution grid |
| Analytics | `Admin.user_registrations_by_day/1`, `Admin.tracks_by_day/1`, `Admin.pipeline_throughput/0` | 30-day bar charts for registrations and track imports, pipeline throughput by queue |
| Audit | `Admin.list_audit_logs/1` | Search, action filter dropdown, timestamped log table with actor email, action badge, resource reference, change payload |

#### UserAuth Additions (`lib/sound_forge_web/user_auth.ex`)
| Plug | Purpose |
|------|---------|
| `require_admin_user/2` | Checks `current_scope.admin?` -- redirects non-admins to `/` with flash error |
| `require_role/2` | Parameterized minimum role check via `Scope.has_role?/2`. Usage: `plug :require_role, :admin` |
| `require_active_user/2` | Checks `user.status == :active` -- logs out suspended/banned users |
| `require_feature/2` | Feature gate via `Scope.can_use_feature?/2`. Usage: `plug :require_feature, :stem_separation` |

### Role Hierarchy

The SaaS role system uses a linear hierarchy enforced by `Scope.role_level/1`:

```
super_admin (4) > admin (3) > enterprise (2) > pro (1) > user (0)
```

- **user**: Free tier. Basic track import and playback.
- **pro**: Stem separation, MIDI control, Melodics integration, full analysis.
- **enterprise**: All pro features plus OSC/TouchOSC and LaLaLai cloud separation.
- **admin**: All features plus admin dashboard, user management, analytics.
- **super_admin**: All features plus system configuration, feature flags, billing.

### Database Changes

| Migration | Table | Changes |
|-----------|-------|---------|
| `20260220040000_expand_roles_add_status.exs` | `users` | Expanded role constraint to `user/pro/enterprise/admin/super_admin`. Added `status` column (`active/suspended/banned`, default `active`). Added composite index on `[:role, :status]`. |
| `20260220040001_create_audit_logs.exs` | `audit_logs` | New table with `binary_id` PK, FK to users (`actor_id`, on_delete: nilify_all), `action`, `resource_type`, `resource_id`, `changes` (map), `ip_address`. Indexes on `actor_id`, `action`, `[resource_type, resource_id]`, `inserted_at`. |

### Key Routes

| Route | Scope | Pipeline | Module |
|-------|-------|----------|--------|
| `/admin` | `/admin` | `browser + require_authenticated_user + require_admin_user` | `AdminLive` (`:index`) |
| `/admin?tab=users` | (same) | (same) | AdminLive users tab |
| `/admin?tab=jobs` | (same) | (same) | AdminLive jobs tab |
| `/admin?tab=system` | (same) | (same) | AdminLive system tab |
| `/admin?tab=analytics` | (same) | (same) | AdminLive analytics tab |
| `/admin?tab=audit` | (same) | (same) | AdminLive audit tab |

Tab switching uses `push_patch` to update the `?tab=` query param, handled by `handle_params/3`.

### Audit Logging Architecture

All admin mutations are automatically audit-logged by the `Admin` context. The pattern:

1. Context function receives `actor_id` (the admin performing the action).
2. Mutation executes (e.g. `Repo.update`).
3. On success, `Admin.log_action/6` inserts an `AuditLog` record with the actor, action name, resource reference, and a changes map containing before/after values.
4. The audit tab in AdminLive queries `Admin.list_audit_logs/1` with optional action and search filters.
5. Logs join on `users` to display actor email. System-initiated actions show "system" as the actor.

Audited actions: `role_change`, `bulk_role_change`, `suspend`, `ban`, `reactivate`, `config_update`, `feature_flag_toggle`, `login`, `logout`, `create`, `update`, `delete`.

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

### Feature: Admin Dashboard with SaaS Role Hierarchy (feature/admin-dashboard)

- [x] **CP-01**: Admin dashboard with role hierarchy, user management, audit logging, analytics, job monitoring, and auth plugs (PR #6)
- After CP-01: `mix compile --warnings-as-errors` passes, admin routes protected by `require_admin_user` plug, audit log records created on all admin mutations

### Feature: DAW Stem Editor + DJ Loop Deck (feature/daw-dj)

#### Wave 1 - Schemas
- [x] **CP-02**: Add DAW edit_operations schema and migration (US-001)
- [x] **CP-03**: Add DJ cue_points and deck_sessions schemas (US-002)
- After CP-03: `mix compile --warnings-as-errors` PASS

#### Wave 2 - Contexts
- [x] **CP-04**: Create DAW context module with edit operation CRUD (US-003)
- [x] **CP-05**: Create DJ context module with deck and cue management (US-004)
- After CP-05: `mix compile --warnings-as-errors` PASS

#### Wave 3 - Core LiveViews
- [x] **CP-06**: Create DAW LiveView with WaveSurfer regions plugin (US-005)
- [x] **CP-07**: Create DJ LiveView with dual deck layout (US-006)
- After CP-07: `mix compile --warnings-as-errors` PASS

#### Wave 4 - Feature Implementation
- [x] **CP-08**: Implement DAW crop and trim operations (US-007)
- [x] **CP-09**: Implement DAW fade in/out and gain operations (US-008)
- [x] **CP-10**: Implement DAW split operation (US-009)
- [x] **CP-11**: Implement DJ loop playback engine with beat quantization (US-010)
- [x] **CP-12**: Implement DJ crossfader and per-deck volume (US-011)
- [x] **CP-13**: Implement DJ cue point placement and hotcue triggers (US-012)
- [x] **CP-14**: Implement DJ pitch/tempo control with pitch slider (US-013)
- After CP-14: `mix compile --warnings-as-errors` PASS

#### Wave 5 - Advanced Features
- [x] **CP-15**: Add SMPTE timecode generation and MIDI clock sync for DJ (US-014)
- [x] **CP-16**: Add MIDI mapping for DJ controls (US-015)
- [x] **CP-17**: Build DJ virtual controller UI (US-016)
- [x] **CP-19**: DAW playback preview with operations applied (US-018)
- [x] **CP-21**: DJ WaveSurfer overview with beat grid and zoom (US-020)
- After CP-21: `mix compile --warnings-as-errors` PASS

#### Wave 6 - Integration & Export
- [x] **CP-18**: DAW export: render edited stem to file (US-017)
- [x] **CP-20**: Add DAW and DJ to navigation and integrate with track detail (US-019)
- After CP-20: `mix compile --warnings-as-errors` PASS (all 20 stories complete)

### Feature: Full lalal.ai API v1.1.0 Integration (feature/lalalai-full-integration)

#### Wave 1 - Foundation (HTTP Client + Schemas + Settings)
- [x] **CP-22**: Expand LalalAI HTTP client with all 15 v1.1 endpoints (US-001)
- [x] **CP-23**: Add UserSettings fields for splitter, dereverb, extraction_level, output_format (US-002)
- [x] **CP-24**: Add batch_jobs and voice_packs schema tables (US-003)
- After CP-24: `mix compile --warnings-as-errors` PASS

#### Wave 2 - Workers + API Routes
- [x] **CP-25**: MultiStem worker for multi-stem extraction (US-004)
- [x] **CP-26**: Demuser worker for voice+music separation (US-005)
- [x] **CP-27**: VoiceClean worker for noise removal (US-006)
- [x] **CP-28**: VoiceChange worker with voice packs (US-007)
- [x] **CP-29**: Batch processing orchestrator (US-008)
- [x] **CP-31**: Quota checking and task cancellation API routes (US-010)
- [x] **CP-32**: Voice packs listing API route (US-011)
- [x] **CP-37**: Lead/backing vocal separation multivocal support (US-016)
- [x] **CP-39**: Idempotency key support for all split operations (US-018)
- After CP-39: `mix compile --warnings-as-errors` PASS

#### Wave 3 - Integration + UI
- [x] **CP-30**: ProcessingWorker delegation for new modes (US-009)
- [x] **CP-33**: SettingsLive advanced lalal.ai options UI (US-012)
- [x] **CP-34**: DashboardLive multistem and mode selection UI (US-013)
- [x] **CP-35**: Batch processing UI with track selection (US-014)
- [x] **CP-36**: Task cancellation UI for processing jobs (US-015)
- [x] **CP-38**: Fix Stem.source tracking bug and source_id persistence (US-017)
- After CP-38: `mix compile --warnings-as-errors` PASS (all 18 stories complete)

## Agentic Complexity Tree View Requirement

When any request involves agentic complexity (UPM, Formation, agent deployment), ALWAYS display a `tree`-style hierarchical view of the planned structure BEFORE execution. This applies to /upm build, /formation deploy, /deploy:agents-v2, /ralph story mapping, /plane-pm issue creation, and any todo/task list with concurrent work. No exceptions.

Referenced systems: UPM, Plane PM, Plan mode, Ralph PRD, Formation, Todo/TaskList.

## Plane Project
- **Project**: Sound Forge Alchemy (SFA)
- **Project ID**: `6f35c181-4a86-476d-bb2a-fba869f68918`
- **Workspace**: lgtm
- **URL**: https://plane.lgtm.build/lgtm/projects/6f35c181-4a86-476d-bb2a-fba869f68918/
