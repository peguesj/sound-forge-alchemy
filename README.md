# Sound Forge Alchemy v4.1.0

Audio stem separation, analysis, and production toolkit built with Elixir, Phoenix 1.8, and LiveView. Import tracks from Spotify, separate stems locally via Demucs or in the cloud via lalal.ai, analyze audio features with librosa, control stems in real-time through MIDI/OSC hardware, and manage it all from a responsive dashboard with full authentication and admin controls.

## Table of Contents

- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Features](#features)
- [Getting Started](#getting-started)
- [Development Commands](#development-commands)
- [Project Structure](#project-structure)
- [API Endpoints](#api-endpoints)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Architecture

```
                         Browser (LiveView WebSocket)
                         PWA (manifest.json + sw.js)
                                    |
                         +----------+----------+
                         |   Phoenix Endpoint   |
                         |  (Bandit / Port 4000) |
                         +----------+----------+
                                    |
              +---------------------+---------------------+
              |                     |                     |
      LiveViews               API Controllers        PubSub
      (Dashboard, Admin,     (JSON REST +            (Real-time
       MIDI, Practice,        rate limiting)          job progress,
       Settings)                                      OSC/MIDI events)
              |                     |                     |
              +---------------------+---------------------+
                                    |
                    +---------------+---------------+
                    |               |               |
               Contexts        Accounts         Admin
               (Music,         (Users, Auth,    (User mgmt,
                Spotify,        Scopes,          audit logs,
                Jobs,           Roles)           analytics)
                Storage)            |
                    |               |
                    +-------+-------+
                            |
                      PostgreSQL
                     (Ecto 3.13)
                            |
                    +-------+-------+
                    |               |
              Oban Workers    Supervised Processes
              (Background)    (GenServers)
                    |               |
          +---------+---------+     +----------+----------+
          |         |         |     |          |          |
     Download  Processing  Analysis  MIDI      OSC     Port
     Worker    Worker      Worker    Device    Server   Supervisor
          |         |         |     Manager            |
          |    +----+----+    |                   +----+----+
          |    |         |    |                   |         |
        spotdl Demucs  LalalAI librosa      DemucsPort  AnalyzerPort
               (local) (cloud)              (Erlang Port) (Erlang Port)
               (Port)                            |         |
                                           Python/Demucs  Python/librosa
```

### OTP Supervision Tree

The application starts the following supervised children in order:

| Child | Type | Purpose |
|-------|------|---------|
| `SoundForgeWeb.Telemetry` | Supervisor | Telemetry metrics and poller |
| `SoundForge.Repo` | GenServer | Ecto/PostgreSQL connection pool |
| `DNSCluster` | GenServer | Distributed Erlang clustering |
| `Phoenix.PubSub` | Supervisor | PubSub for real-time broadcasts |
| `SoundForge.TaskSupervisor` | Task.Supervisor | Async LiveView operations |
| `SoundForge.Audio.PortSupervisor` | DynamicSupervisor | Erlang Port lifecycle management |
| `SoundForge.Notifications` | GenServer | ETS-backed notification store |
| `Oban` | Supervisor | Background job processing |
| `SoundForge.Telemetry.ObanHandler` | GenServer | Structured Oban job logging and PubSub failure broadcasts |
| `SoundForge.MIDI.DeviceManager` | GenServer | USB/Network MIDI device discovery and hotplug monitoring |
| `SoundForgeWeb.Endpoint` | Supervisor | HTTP server (Bandit) |

### PubSub Topics

| Topic | Events | Purpose |
|-------|--------|---------|
| `"jobs:{job_id}"` | Job progress updates | Workers broadcast download/processing/analysis status |
| `"tracks"` | Track additions | DashboardLive subscribes for new track inserts |
| `"track_pipeline:{track_id}"` | Pipeline stage failures | ObanHandler broadcasts stage failures for dashboard |
| `"debug:worker_status"` | Worker lifecycle | Worker start/stop/exception events for debug panel |
| `"osc:messages"` | `{:osc_message, msg, sender}` | OSC messages from UDP server |
| `"midi:bridge"` | `{:midi_from_osc, msg}` | MIDI messages from OSC translation |
| `"track_playback"` | Play/stop, stem volume/mute/solo | Unified playback actions from all control surfaces |

### Oban Queues

| Queue | Concurrency | Worker | Purpose |
|-------|-------------|--------|---------|
| `download` | 3 | `DownloadWorker` | Audio downloads via spotdl |
| `processing` | 2 | `ProcessingWorker`, `LalalAIWorker` | Stem separation (Demucs local or lalal.ai cloud) |
| `analysis` | 2 | `AnalysisWorker` | Audio feature extraction via librosa |

Plugins: `Pruner` (7-day retention), `Lifeline` (30-min rescue), `Cron` (daily storage cleanup at 03:00 UTC).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.15+ / Erlang OTP 26+ |
| Web Framework | Phoenix 1.8 |
| Real-Time UI | LiveView 1.1 |
| Database | PostgreSQL via Ecto 3.13 |
| Background Jobs | Oban 2.18 |
| HTTP Client | Req |
| HTTP Server | Bandit |
| Authentication | bcrypt_elixir, Phoenix.Token |
| MIDI | Midiex (NIF-based, Rust) |
| Python Interop | Erlang Ports (GenServer wrappers) |
| Stem Separation (local) | Demucs (Python, via Erlang Port) |
| Stem Separation (cloud) | lalal.ai REST API |
| Audio Analysis | librosa (Python, via Erlang Port) |
| CSS | Tailwind CSS v4 + DaisyUI 5 |
| JS Bundler | esbuild |
| Static Analysis | Credo, Dialyxir |
| JSON | Jason |

## Features

### Stem Separation

- **Local processing** via Demucs (htdemucs, htdemucs_ft, htdemucs_6s models) through supervised Erlang Ports
- **Cloud processing** via lalal.ai REST API with support for 11 stem types (vocals, drums, bass, piano, electric guitar, acoustic guitar, synthesizer, strings, winds, noise, mid/side)
- Dual-engine `ProcessingJob` schema with `engine` field (`"demucs"` or `"lalalai"`)
- Real-time progress tracking via PubSub broadcasts
- Extended stem type system supporting both Demucs 4-stem and lalal.ai 11-stem outputs

### Audio Analysis

- librosa-based feature extraction: tempo, key, energy, spectral centroid, MFCCs, chroma, beat positions
- Interactive visualizations via D3.js hooks (radar chart, spectral plot, chroma heatmap, MFCC, beat timeline)
- Analysis results stored as structured maps in PostgreSQL

### MIDI Integration

- USB and Network MIDI device discovery with hotplug monitoring (`SoundForge.MIDI.DeviceManager`)
- Akai MPC controller support: MPC Beats, MPC 2.0, iMPC Pro 2 detection by port name pattern, multi-port (A-D) awareness (`SoundForge.MIDI.MPCController`)
- MIDI message parsing: Note On/Off, CC, Program Change, Pitch Bend, System Exclusive, Clock (`SoundForge.MIDI.Parser`)
- MIDI output for sending note/CC/program data to external devices
- MIDI clock sync (internal/external) with tempo tracking
- CC-to-stem-volume action mapping with configurable CC assignments
- Dedicated MidiLive page for device monitoring and configuration

### OSC / TouchOSC

- UDP-based OSC 1.0 server (default port 8000) with PubSub broadcasting (`SoundForge.OSC.Server`)
- OSC client for sending feedback messages to TouchOSC (`SoundForge.OSC.Client`)
- OSC parser with `f`, `i`, `s`, `b` type tags and bundle support (`SoundForge.OSC.Parser`)
- TouchOSC `.tosc` layout generator: 8 stem faders, mute/solo, transport, BPM, title (`mix sfa.touchosc.generate`)
- OSC action executor routing addresses to SFA playback actions (`/stem/{n}/volume`, `/transport/*`)
- End-to-end pipeline simulation and latency benchmarking (`SoundForge.OSC.Pipeline`)

### MIDI-OSC Bridge

- Bidirectional MIDI-to-OSC protocol translation (`SoundForge.Bridge.MidiOsc`)
- CC 7-14 mapped to `/stem/{n}/volume` with configurable mapping profiles
- Bridge toggle in control surface settings UI

### Melodics Integration

- Import practice sessions from Melodics local data directory
- Session history, accuracy trends, and statistics tracking
- Practice-to-stem difficulty adaptation: simple (<60%), matched (60-85%), complex (>85%)
- Dedicated PracticeLive page with session history and stem recommendations

### Admin Dashboard

- Production-grade admin panel at `/admin` with role-gated access
- Six admin tabs: Overview, Users, Jobs, System, Analytics, Audit
- User management: search, role/status filters, bulk role assignment, user suspension
- 5-tier SaaS role hierarchy: `user` -> `pro` -> `enterprise` -> `admin` -> `super_admin`
- Feature gating per role (stem separation, lalal.ai cloud, OSC/TouchOSC, MIDI, Melodics, full analysis)
- Audit logging for administrative actions (`SoundForge.Admin.AuditLog`)
- System statistics: user counts, track counts, job states, storage usage

### Authentication and Authorization

- Email/password authentication with bcrypt hashing
- Magic link / token-based login
- Session-based auth with CSRF protection
- Role-based authorization via `SoundForge.Accounts.Scope`
- Security headers plug and rate limiting (120 req/min browser, 60 req/min API, 10 req/min heavy operations)
- API key authentication for programmatic access

### Debug Panel and Observability

- Slide-in debug panel on the dashboard with real-time Oban job inspection
- Active and historical job views with state filtering (executing, available, scheduled, retryable, completed, cancelled, discarded)
- Structured Oban telemetry logging with namespace-scoped prefixes (`[oban.WorkerName]`)
- Worker status PubSub broadcasts for live debug panel updates
- Pipeline failure detection and dashboard notification
- Log metadata: `oban_job_id`, `oban_queue`, `oban_worker`, `oban_attempt`, `track_id`, `stage`
- Debug log auto-scroll JS hook

### Responsive UI and PWA

- Mobile-first responsive dashboard with bottom navigation bar (Library/Player/MIDI/Settings)
- Touch-optimized stem mixer with vertical faders, mute/solo buttons, 60fps throttled updates
- Swipe-based tab navigation on track detail views
- Mobile drawer component for sidebar replacement
- Container-aware chart resizing via ResizeObserver hook
- PWA manifest (`manifest.json`) with standalone display mode
- Service worker (`sw.js`) with network-first navigation and cache-first assets
- MPC pad assignment UI with drag-and-drop and touch support (4x4 grid)

### Track and Playlist Management

- Spotify URL import: tracks, albums, playlists
- Spotify OAuth integration for authenticated metadata fetching
- Spotify playback component with embedded player
- Album art display from Spotify metadata
- Playlist schema with manual, Spotify, and import sources
- Track search and filtering
- Stem file export (individual or all stems per track)
- Analysis data export

### Notifications

- ETS-backed in-memory notification store
- Real-time notification bell component with unread count
- Toast stack component for transient alerts

## Getting Started

### Prerequisites

- **Elixir** >= 1.15 and **Erlang/OTP** >= 26
- **PostgreSQL** >= 14
- **Python** >= 3.9 with pip
- **Node.js** (for esbuild/tailwind asset compilation, installed automatically)

### Python Dependencies

```bash
pip install librosa demucs soundfile numpy
```

### Optional Services

- **spotdl** for Spotify audio downloads: `pip install spotdl`
- **lalal.ai API key** for cloud stem separation: set `LALALAI_API_KEY` environment variable
- **Spotify OAuth credentials**: set `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` for authenticated metadata access

### Setup

```bash
# Clone the repository
git clone <repo-url> sound-forge-alchemy
cd sound-forge-alchemy

# Install Elixir dependencies, create database, run migrations, build assets
mix setup

# Start the development server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) in your browser.

To start inside an IEx shell:

```bash
iex -S mix phx.server
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Production | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Production | Phoenix secret key (generate with `mix phx.gen.secret`) |
| `LALALAI_API_KEY` | No | lalal.ai API key for cloud stem separation |
| `SPOTIFY_CLIENT_ID` | No | Spotify OAuth client ID |
| `SPOTIFY_CLIENT_SECRET` | No | Spotify OAuth client secret |
| `PORT` | No | HTTP port (default: 4000) |

## Development Commands

| Command | Description |
|---------|-------------|
| `mix setup` | Install deps, create DB, run migrations, build assets |
| `mix phx.server` | Start the development server on port 4000 |
| `mix test` | Run the full test suite |
| `mix test --failed` | Re-run only previously failed tests |
| `mix test path/to/test.exs:42` | Run a specific test at a line |
| `mix format` | Format all Elixir files |
| `mix precommit` | Compile (warnings-as-errors) + deps.unlock --unused + format + test |
| `mix ecto.migrate` | Run pending database migrations |
| `mix ecto.reset` | Drop, create, migrate, and seed the database |
| `mix ecto.gen.migration name` | Generate a new migration file |
| `mix sfa.touchosc.generate` | Generate TouchOSC layout file at `priv/touchosc/sfa_mixer.tosc` |
| `mix credo` | Run static analysis |
| `mix dialyzer` | Run type checking with Dialyxir |

## Project Structure

```
lib/
├── sound_forge/
│   ├── application.ex              # OTP supervision tree
│   ├── repo.ex                     # Ecto repository
│   ├── accounts.ex                 # Accounts context (registration, auth, sessions)
│   ├── accounts/
│   │   ├── user.ex                 # User schema (email, hashed_password, role, status)
│   │   ├── user_token.ex           # Session/magic-link tokens
│   │   ├── user_settings.ex        # Per-user settings schema
│   │   ├── user_notifier.ex        # Email notifications
│   │   ├── scope.ex                # Role-based authorization (5-tier hierarchy)
│   │   └── spotify_oauth_token.ex  # Spotify OAuth token storage
│   ├── admin.ex                    # Admin context (user mgmt, analytics, audit)
│   ├── admin/
│   │   └── audit_log.ex            # Audit log schema
│   ├── music.ex                    # Music context - CRUD for all schemas
│   ├── music/
│   │   ├── track.ex                # Track schema (spotify metadata, album_art_url)
│   │   ├── download_job.ex         # Download job with Ecto.Enum status
│   │   ├── processing_job.ex       # Stem separation job (engine: demucs/lalalai)
│   │   ├── analysis_job.ex         # Audio analysis job (results map)
│   │   ├── stem.ex                 # Stem schema (11 types, source: local/cloud)
│   │   ├── analysis_result.ex      # Extracted features (tempo, key, energy, ...)
│   │   ├── playlist.ex             # Playlist schema (spotify/manual/import)
│   │   └── playlist_track.ex       # Many-to-many join table
│   ├── spotify.ex                  # Spotify context (fetch_metadata/1)
│   ├── spotify/
│   │   ├── client.ex               # Behaviour for Spotify API (mockable)
│   │   ├── http_client.ex          # Req-based Spotify HTTP client with ETS token cache
│   │   └── url_parser.ex           # Parse Spotify track/album/playlist URLs
│   ├── audio/
│   │   ├── analyzer_port.ex        # GenServer wrapping librosa Python script
│   │   ├── demucs_port.ex          # GenServer wrapping Demucs Python script
│   │   ├── port_supervisor.ex      # DynamicSupervisor for Port processes
│   │   └── lalalai.ex              # lalal.ai REST API client (upload, poll, download)
│   ├── jobs/
│   │   ├── download_worker.ex      # Oban worker for audio downloads (spotdl)
│   │   ├── processing_worker.ex    # Oban worker for Demucs stem separation
│   │   ├── lalalai_worker.ex       # Oban worker for lalal.ai cloud separation
│   │   ├── analysis_worker.ex      # Oban worker for librosa analysis
│   │   └── cleanup_worker.ex       # Cron worker for storage cleanup
│   ├── midi/
│   │   ├── device_manager.ex       # USB/Network MIDI discovery + hotplug
│   │   ├── mpc_controller.ex       # Akai MPC device profiles and modes
│   │   ├── parser.ex               # MIDI message parsing (Note, CC, SysEx, Clock)
│   │   ├── output.ex               # MIDI output (send notes, CCs, programs)
│   │   ├── clock.ex                # MIDI clock sync (internal/external)
│   │   ├── dispatcher.ex           # MIDI message routing
│   │   ├── action_executor.ex      # CC-to-stem action mapping
│   │   ├── message.ex              # MIDI message struct
│   │   ├── mapping.ex              # MIDI mapping struct
│   │   ├── mappings.ex             # Mapping presets
│   │   ├── network_discovery.ex    # Network MIDI device scanning
│   │   └── profiles/
│   │       └── mpc_app.ex          # MPC Beats/MPC 2.0/iMPC Pro 2 profiles
│   ├── osc/
│   │   ├── server.ex               # GenServer UDP listener (port 8000)
│   │   ├── client.ex               # UDP sender for TouchOSC feedback
│   │   ├── parser.ex               # OSC 1.0 encode/decode (f/i/s/b + bundles)
│   │   ├── action_executor.ex      # OSC address to SFA action routing
│   │   ├── touchosc_layout.ex      # .tosc ZIP layout generator
│   │   └── pipeline.ex             # E2E simulation and latency benchmarking
│   ├── bridge/
│   │   └── midi_osc.ex             # Bidirectional MIDI<->OSC translation
│   ├── integrations/
│   │   ├── melodics.ex             # Melodics session import and stats
│   │   └── melodics/
│   │       ├── melodics_session.ex # Ecto schema for practice sessions
│   │       └── practice_adapter.ex # Accuracy-to-stem-difficulty mapping
│   ├── debug/
│   │   ├── jobs.ex                 # Debug queries for Oban job inspector
│   │   └── log_broadcaster.ex      # Live log broadcasting for debug panel
│   ├── telemetry/
│   │   └── oban_handler.ex         # Structured Oban job lifecycle logging
│   ├── processing/
│   │   └── demucs.ex               # Demucs model configuration
│   ├── notifications.ex            # ETS-backed notification store
│   ├── settings.ex                 # Application settings context
│   ├── storage.ex                  # Local file storage management
│   └── release.ex                  # Release tasks (migrate, rollback)
├── sound_forge_web/
│   ├── router.ex                   # Routes (browser + API + admin + auth)
│   ├── user_auth.ex                # Authentication plugs and helpers
│   ├── live/
│   │   ├── dashboard_live.ex       # Main dashboard LiveView
│   │   ├── dashboard_live.html.heex
│   │   ├── admin_live.ex           # Admin dashboard (6 tabs)
│   │   ├── midi_live.ex            # MIDI device monitoring page
│   │   ├── practice_live.ex        # Melodics practice sessions page
│   │   ├── settings_live.ex        # User settings page
│   │   ├── audio_player_live.ex    # Audio player LiveView
│   │   └── components/
│   │       ├── app_header.ex       # Application header bar
│   │       ├── sidebar.ex          # Navigation sidebar
│   │       ├── stem_mixer.ex       # Touch-optimized stem mixer faders
│   │       ├── mobile_nav.ex       # Bottom nav bar (mobile)
│   │       ├── mobile_drawer.ex    # Slide-out mobile drawer
│   │       ├── midi_osc_status_bar.ex  # MIDI/OSC connection status
│   │       ├── control_surfaces_settings.ex # OSC/MIDI/MPC config UI
│   │       ├── pad_assignment.ex   # 4x4 MPC pad grid with drag-and-drop
│   │       ├── track_detail_responsive.ex  # Responsive track detail tabs
│   │       ├── job_progress.ex     # Job progress indicator
│   │       ├── notification_bell.ex # Notification dropdown
│   │       ├── toast_stack.ex      # Toast notifications
│   │       └── spotify_player.ex   # Spotify embedded player
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── spotify_controller.ex
│   │   │   ├── download_controller.ex
│   │   │   ├── processing_controller.ex
│   │   │   └── analysis_controller.ex
│   │   ├── file_controller.ex      # Serve stored audio files
│   │   ├── health_controller.ex    # Health check endpoint
│   │   ├── export_controller.ex    # Stem and analysis export downloads
│   │   ├── spotify_oauth_controller.ex  # Spotify OAuth flow
│   │   ├── user_registration_controller.ex
│   │   ├── user_session_controller.ex
│   │   └── user_settings_controller.ex
│   ├── plugs/
│   │   ├── api_auth.ex             # API token authentication plug
│   │   ├── rate_limiter.ex         # Configurable rate limiting plug
│   │   └── security_headers.ex     # Security headers plug
│   ├── channels/
│   │   ├── user_socket.ex
│   │   └── job_channel.ex          # Real-time job progress channel
│   └── components/
│       ├── core_components.ex      # Shared UI components
│       └── layouts.ex              # App and root layouts
├── mix/tasks/
│   └── sfa.touchosc.generate.ex   # TouchOSC layout generation task
├── assets/
│   ├── js/hooks/
│   │   ├── stem_mixer_hook.js      # Touch + mouse fader control (60fps)
│   │   ├── swipe_hook.js           # Horizontal swipe detection
│   │   ├── resize_observer_hook.js # Container dimension tracking for charts
│   │   ├── pad_assign_hook.js      # Drag-and-drop pad assignment
│   │   ├── audio_player.js         # Audio playback controls
│   │   ├── spotify_player.js       # Spotify embed integration
│   │   ├── debug_log_scroll.js     # Debug panel auto-scroll
│   │   ├── shift_select.js         # Shift-click multi-select
│   │   ├── auto_dismiss.js         # Auto-dismiss notifications
│   │   ├── analysis_beats.js       # Beat timeline D3 visualization
│   │   ├── analysis_chroma.js      # Chroma heatmap visualization
│   │   ├── analysis_mfcc.js        # MFCC visualization
│   │   ├── analysis_radar.js       # Radar chart visualization
│   │   ├── analysis_spectral.js    # Spectral plot visualization
│   │   └── job_trace_graph.js      # Job trace graph visualization
│   └── css/app.css                 # Tailwind CSS v4 entry point
├── config/
│   ├── config.exs                  # Base config (Oban queues, Ecto, esbuild, Tailwind)
│   ├── dev.exs                     # Development config
│   ├── test.exs                    # Test config (Mox, Oban testing mode)
│   └── runtime.exs                 # Runtime/production config (env vars)
├── priv/
│   ├── python/
│   │   ├── analyzer.py             # librosa audio analysis script
│   │   └── demucs_runner.py        # Demucs stem separation wrapper
│   ├── repo/migrations/            # Ecto migrations
│   ├── static/
│   │   ├── manifest.json           # PWA manifest (standalone, purple theme)
│   │   └── sw.js                   # Service worker (network-first + cache-first)
│   └── touchosc/                   # Generated TouchOSC layouts
└── test/
    ├── sound_forge/                # Context, schema, and worker tests
    ├── sound_forge_web/            # Controller, LiveView, and channel tests
    └── support/                    # Test helpers, fixtures, data cases
```

## API Endpoints

### Browser Routes (authenticated)

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| GET | `/` | `DashboardLive` | Main dashboard |
| GET | `/tracks/:id` | `DashboardLive :show` | Track detail view |
| GET | `/admin` | `AdminLive` | Admin dashboard (admin+ role required) |
| GET | `/midi` | `MidiLive` | MIDI device monitoring |
| GET | `/practice` | `PracticeLive` | Melodics practice sessions |
| GET | `/settings` | `SettingsLive` | User settings |
| GET | `/files/*path` | `FileController` | Serve stored audio files |
| GET | `/export/stem/:id` | `ExportController` | Download individual stem |
| GET | `/export/stems/:track_id` | `ExportController` | Download all stems for a track |
| GET | `/export/analysis/:track_id` | `ExportController` | Export analysis data |

### Authentication Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/users/register` | Registration form |
| POST | `/users/register` | Create account |
| GET | `/users/log-in` | Login form |
| POST | `/users/log-in` | Create session |
| GET | `/users/log-in/:token` | Magic link confirmation |
| DELETE | `/users/log-out` | Destroy session |
| GET | `/users/settings` | Edit user settings |
| GET | `/auth/spotify` | Initiate Spotify OAuth |
| GET | `/auth/spotify/callback` | Spotify OAuth callback |

### JSON API Routes (`/api`, authenticated + rate limited)

| Method | Path | Handler | Rate Limit | Description |
|--------|------|---------|------------|-------------|
| POST | `/api/spotify/fetch` | `SpotifyController.fetch` | 60/min | Fetch Spotify metadata |
| POST | `/api/download/track` | `DownloadController.create` | 10/min | Start audio download |
| GET | `/api/download/job/:id` | `DownloadController.show` | 60/min | Get download job status |
| POST | `/api/processing/separate` | `ProcessingController.create` | 10/min | Start stem separation |
| GET | `/api/processing/job/:id` | `ProcessingController.show` | 60/min | Get processing job status |
| GET | `/api/processing/models` | `ProcessingController.models` | 60/min | List available Demucs models |
| POST | `/api/analysis/analyze` | `AnalysisController.create` | 10/min | Start audio analysis |
| GET | `/api/analysis/job/:id` | `AnalysisController.show` | 60/min | Get analysis job status |

### Utility Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (unauthenticated) |

### Development Routes (dev only)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/dev/dashboard` | Phoenix LiveDashboard |
| GET | `/dev/mailbox` | Swoosh mailbox preview |

## Testing

### Framework

- **ExUnit** with `Ecto.Adapters.SQL.Sandbox` for database isolation
- **Mox** for Spotify API mocking via behaviour (`SoundForge.Spotify.Client`)
- **Oban.Testing** with `testing: :manual` mode
- **Phoenix.LiveViewTest** for LiveView integration testing
- **LazyHTML** for HTML assertions

### Running Tests

```bash
mix test                              # Run all tests
mix test test/sound_forge/            # Run context tests only
mix test test/sound_forge_web/        # Run web tests only
mix test --failed                     # Re-run previously failed tests
mix test path/to/test.exs:42          # Run specific test at line
```

### Pre-Commit Checks

```bash
mix precommit
```

This runs: `compile --warnings-as-errors` + `deps.unlock --unused` + `format` + `test`.

### Mox Setup

The Spotify client uses a behaviour with a mock defined in `test/test_helper.exs`:

```elixir
Mox.defmock(SoundForge.Spotify.MockClient, for: SoundForge.Spotify.Client)
```

Swapped in via `config/test.exs`:

```elixir
config :sound_forge, :spotify_client, SoundForge.Spotify.MockClient
```

## Contributing

1. Create a feature branch from `main`
2. Write tests first (Red-Green-Refactor)
3. Ensure all tests pass: `mix test`
4. Run pre-commit checks: `mix precommit`
5. Open a pull request

### Code Quality

- Zero compiler warnings required (`--warnings-as-errors`)
- All code formatted with `mix format`
- Contexts return `{:ok, _} | {:error, _}` tuples
- All schemas use `binary_id` UUIDs
- External services are mocked via behaviours + Mox in tests
- `@spec` and `@doc` annotations on all public functions
- Static analysis with Credo and Dialyxir

## License

All rights reserved.
