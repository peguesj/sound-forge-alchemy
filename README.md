# Sound Forge Alchemy

**Professional audio engineering platform for DJs and producers — built on Elixir/Phoenix.**

[![Version](https://img.shields.io/badge/version-4.3.0-blue.svg)](CHANGELOG.md)
[![Elixir](https://img.shields.io/badge/elixir-~%3E1.15-purple.svg)](https://elixir-lang.org)
[![Phoenix](https://img.shields.io/badge/phoenix-~%3E1.8-orange.svg)](https://phoenixframework.org)
[![Tests](https://img.shields.io/badge/tests-707%20passing-brightgreen.svg)](test/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> [!WARNING]
> **NOT FOR COMMERCIAL USE — USE AT YOUR OWN RISK.** This is a personal creative project provided as-is with no warranty, no support, and no guarantees of any kind. Running this will likely require you to wrangle Python environments, Spotify OAuth credentials, and at minimum one existential crisis about why you're doing this at all. If it breaks, eats your API quota, or separates your stems into unrecognizable noise — that's on you. **This is mostly for vibe guys.**

Sound Forge Alchemy (SFA) transforms Spotify tracks into a professional production toolkit. Import playlists, download audio, separate stems with local Demucs or cloud lalal.ai, analyze harmonic content with D3.js visualizations, and orchestrate AI agents that understand your music — all from a real-time Phoenix LiveView dashboard.

![Sound Forge Alchemy Dashboard](docs/assets/screenshots/dashboard-authenticated.png)
*The main library view showing track cards with album art, sidebar navigation, pipeline controls, and Spotify player integration.*

<details>
<summary><strong>Table of Contents</strong></summary>

- [Features](#features)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [API Reference](#api-reference)
- [Deployment](#deployment)
- [Changelog](#changelog)
- [Contributing](#contributing)

</details>

---

## Features

<details>
<summary><strong>Core Pipeline</strong></summary>

The SFA pipeline is a chained Oban job graph that executes asynchronously with real-time LiveView progress via Phoenix PubSub.

| Stage | Worker | Description |
|-------|--------|-------------|
| Import | — | Spotify OAuth playlist import, track metadata resolution |
| Download | `DownloadWorker` | SpotDL primary + yt-dlp fallback when Spotify API is unavailable |
| Stem Separation | `ProcessingWorker` | Routes to Demucs (local) or lalal.ai (cloud) based on user setting |
| Audio Analysis | `AnalysisWorker` | Python/librosa port: BPM, key, energy, chroma, MFCC, spectral |
| Auto-Cue | `AutoCueWorker` | Drop detection and cue point generation |
| Export | `ExportController` | Individual stem or bundled `.zip` download |

**Pipeline behavior:**
- Each stage broadcasts progress via `SoundForge.Jobs.PipelineBroadcaster`
- Failed jobs display retry button with exponential backoff display
- `pipeline_complete?/1` checks only triggered stages — skipped stages do not block completion
- Deduplication guards with unique database indexes prevent duplicate stems and analysis records

**Oban queue configuration:**

| Queue | Concurrency | Workers |
|-------|-------------|---------|
| `download` | 3 | `DownloadWorker` |
| `processing` | 2 | `ProcessingWorker`, `LalalaiWorker`, `MultistemWorker` |
| `analysis` | 2 | `AnalysisWorker`, `AutoCueWorker` |

Plugins: `Pruner` (7-day retention), `Lifeline` (30-min rescue), `Cron` (daily storage cleanup at 03:00 UTC).

</details>

<details>
<summary><strong>AI Agent System</strong></summary>

`SoundForge.Agents.Orchestrator` is the single entry point for all AI work. It routes tasks to specialist agents based on instruction keyword patterns or explicit `:task` hints, then dispatches to the best available LLM via `SoundForge.LLM.Router`.

**6 Specialist Agents:**

| Agent | Capabilities |
|-------|-------------|
| `TrackAnalysisAgent` | Key detection, BPM, energy profiling, harmonic analysis |
| `MixPlanningAgent` | Set sequencing, transition advice, key compatibility, harmonic mixing |
| `StemIntelligenceAgent` | Stem quality analysis, loop extraction recommendations |
| `CuePointAgent` | Drop detection, loop region detection, cue point placement |
| `MasteringAgent` | Loudness analysis (LUFS), mastering chain recommendations |
| `LibraryAgent` | Semantic library search, track recommendations, playlist curation |

**Usage:**

```elixir
# Direct dispatch with task hint
Orchestrator.run(%Context{instruction: "Analyse the key", track_id: id}, task: :track_analysis)

# Auto-routing from natural language
Orchestrator.run(%Context{instruction: "Plan a set with these 5 tracks", track_ids: ids})

# Multi-agent pipeline
Orchestrator.pipeline(%Context{...}, [TrackAnalysisAgent, MixPlanningAgent])
```

**Multi-LLM Routing:**

`SoundForge.LLM.Router` selects the best available provider with automatic fallback chains (up to 4 retries):

| Adapter | Provider |
|---------|----------|
| `anthropic.ex` | Anthropic Claude |
| `openai.ex` | OpenAI |
| `azure_openai.ex` | Azure OpenAI |
| `google_gemini.ex` | Google Gemini |
| `ollama.ex` | Ollama (local) |
| `lm_studio.ex` | LM Studio (local) |
| `litellm.ex` | LiteLLM proxy |
| `custom_openai.ex` | Any OpenAI-compatible endpoint |
| `system_providers.ex` | System-level providers |

Task spec controls routing preference:
```elixir
LLM.Router.route(user_id, messages, %{prefer: :quality, task_type: :harmonic_analysis})
```

All provider API keys stored at-rest with AES-256-GCM encryption via `Cloak.Ecto`.

</details>

<details>
<summary><strong>Stem Separation</strong></summary>

Two separation engines with per-user toggle in settings:

**Local — Demucs (htdemucs models)**

| Model | Stems | Notes |
|-------|-------|-------|
| `htdemucs` | 4 (vocals, drums, bass, other) | Fast, good general quality |
| `htdemucs_ft` | 4 | Fine-tuned, slower, higher quality |
| `htdemucs_6s` | 6 (adds guitar, piano) | Best quality, slowest |
| `mdx_extra` | 4 | MDX architecture variant |

Runs via `SoundForge.Audio.DemucsPort` Erlang port, supervised with restart strategy in `PortSupervisor`.

**Cloud — lalal.ai API v1.1.0**

Additional stem types: electric guitar, acoustic guitar, piano, synthesizer, strings, wind instruments, noise, mid/side

- `SoundForge.Audio.Lalalai` API client with polling/backoff
- `LalalaiWorker` Oban job with configurable retry intervals
- 60-second **preview mode** — evaluate separation quality before committing to full processing
- Source badges on stems indicate which engine produced each file
- Per-user lalal.ai API key support (encrypted at rest)

**Batch processing:** `BatchProcessor` and `MultistemWorker` for parallel multi-track operations.

</details>

<details>
<summary><strong>Audio Analysis</strong></summary>

Analysis runs via `SoundForge.Audio.AnalyzerPort` — an Erlang port wrapping a Python 3.11 script using `librosa` and `numpy`.

**Extracted features:**

- Tempo (BPM) and beat grid
- Musical key (Camelot notation)
- Energy and loudness profile
- Chroma features (12-bin harmonic content)
- MFCC coefficients (timbre fingerprint)
- Spectral centroid, rolloff, contrast
- Audio structure segmentation

**7 D3.js visualization hooks** registered in `assets/js/app.js`:

| Hook | Visualization |
|------|---------------|
| `AnalysisRadar` | Polar energy/feature radar chart |
| `AnalysisChroma` | 12-bin chroma heat map |
| `AnalysisBeats` | Beat grid timeline |
| `AnalysisMFCC` | MFCC coefficient heat map |
| `AnalysisSpectral` | Spectral centroid/rolloff curve |
| `AnalysisEnergyCurve` | Energy-over-time waveform |
| `AnalysisStructure` | Song section labeling (intro/verse/chorus/outro) |

</details>

<details>
<summary><strong>DJ and DAW Tools</strong></summary>

**DAW Tab (`DawLive` / `daw_editor.js`)**
- Multi-clip WebAudio arrangement editor (700+ lines)
- Clip dragging, loop regions, quantized editing
- Waveform preview (`daw_preview.js`)
- Export arrangements via `POST /api/daw/export`
- Edit operation history persisted to `edit_operations` table

**DJ Deck (`DjLive` / `dj_deck.js`)**
- Virtual 2-deck DJ interface (711 lines)
- BPM sync, pitch/rate controls, crossfader, EQ, filter
- Jog wheel emulation (`jog_wheel.js`)
- DJ preset management (`SoundForge.DJ.Presets`)

**MIDI Integration (`SoundForge.MIDI`)**
- USB MIDI device enumeration via `midiex` (Rust NIF)
- Network MIDI discovery (`NetworkDiscovery`)
- MIDI clock sync (`Clock`)
- Device-agnostic mapping system (`Mapping`, `Mappings`, `Dispatcher`)
- Akai MPC profile: MPC Beats, MPC 2.0, iMPC Pro 2 (`Profiles.Mpc`, `Profiles.MpcApp`)
- Custom mapping UI in `MidiLive`

**OSC / TouchOSC**
- UDP-based OSC 1.0 server on port 8000 (`SoundForge.OSC.Server`)
- OSC client for TouchOSC feedback (`SoundForge.OSC.Client`)
- MIDI-OSC bridge (`SoundForge.Bridge.MidiOsc`)
- TouchOSC layout generator: `mix sfa.touchosc.generate`

**Melodics Integration**
- Practice session import and tracking (`SoundForge.Integrations.Melodics`)
- Accuracy-to-stem-difficulty adaptation (simple / matched / complex)
- `PracticeLive` view for real-time session display

**Auto-Cue Points (`AutoCueWorker`)**
- Drop detection using energy analysis
- Configurable cue point types: intro, drop, outro
- Stem loop extraction recommendations

</details>

<details>
<summary><strong>Admin and Platform</strong></summary>

**5-Tier Role Hierarchy**

| Role | Access Level |
|------|-------------|
| `user` | Own tracks, library, settings |
| `moderator` | View all tracks, flag content |
| `admin` | User management, job queue, system stats |
| `super_admin` | Role assignment, audit log, platform configuration |
| `system` | Internal service account |

![Admin Dashboard](docs/assets/screenshots/admin-authenticated.png)
*The admin dashboard showing system stats (5 users, 230 tracks), job queue depth, and tabbed management controls.*

**Admin Dashboard (`/admin`) — 6 tabs:**
- **Overview**: active users, job queue depth, system stats
- **Users**: role promotion/demotion, account status, bulk operations
- **Jobs**: all Oban jobs with retry/cancel/inspect controls
- **System**: Phoenix LiveDashboard integration
- **Analytics**: track/stem/analysis volume trends
- **Audit**: full action audit log with actor/target/timestamp

**Audit Log:** Every privileged action recorded to `audit_logs` table.

![Platform Library](docs/assets/screenshots/platform-library-authenticated.png)
*The platform library view showing all 230 tracks across all users in a paginated table, accessible to admins and super_admins.*

**Provider Health:** `ProviderHealthWorker` polls configured LLM providers on a schedule and updates `ModelRegistry` availability status.

**Debug Inspector (users with `debug_mode` enabled):**
- Real-time log streaming with color coding and severity filtering
- Error and event tracing tab with dependency graph visualization
- Worker status collapsible with async PubSub updates
- Job queue panel with active/history tabs

**Security:**
- Rate limiting: 120 req/min browser, 60 req/min API, 10 req/min heavy operations
- Security headers plug: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, CSP
- CSRF protection on all browser routes
- IDOR ownership checks on all track/stem/analysis resources

</details>

---

## Quick Start

```bash
# Clone and install
git clone https://github.com/peguesj/sound-forge-alchemy.git sfa
cd sfa
mix setup

# Configure
cp .env.example .env
# Edit .env: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SECRET_KEY_BASE

# Start
source .env && mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

![Login page](docs/assets/screenshots/login.png)
*The login page supports magic link and password-based authentication against a dark navy background.*

<details>
<summary><strong>Full Setup Guide</strong></summary>

### Prerequisites

| Dependency | Version | Installation |
|------------|---------|-------------|
| Elixir | ~> 1.15 | `brew install elixir` or `asdf install` |
| Erlang/OTP | 26+ | Installed with Elixir |
| PostgreSQL | 14+ | `brew install postgresql` or Docker |
| Python | 3.11.7 | Required for SpotDL, Demucs, analyzer |
| Node.js | 18+ | Asset compilation only (auto-installed) |
| FFmpeg | 6+ | Required by SpotDL and Demucs |

> **Python version note:** Must be exactly 3.11.7 for SpotDL/Demucs compatibility.

### Python Environment

```bash
python3.11 -m venv priv/python/venv
source priv/python/venv/bin/activate
pip install spotdl demucs librosa numpy torch torchaudio soundfile
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY_BASE` | Yes (prod) | 64-char secret — `mix phx.gen.secret` |
| `DATABASE_URL` | Yes (prod) | PostgreSQL connection string |
| `SPOTIFY_CLIENT_ID` | Yes | Spotify app client ID |
| `SPOTIFY_CLIENT_SECRET` | Yes | Spotify app client secret |
| `LALALAI_API_KEY` | Optional | Enables cloud stem separation |
| `SYSTEM_LALALAI_ACTIVATION_KEY` | Optional | System-level lalal.ai key |
| `LLM_ENCRYPTION_KEY` | Optional | Base64-encoded 32-byte key for LLM API key encryption |
| `PHX_HOST` | Prod | Public hostname for URL generation |
| `PORT` | Optional | HTTP port (default: 4000) |
| `PHX_SERVER` | Prod | Set `true` to start HTTP server in release |
| `POOL_SIZE` | Optional | Ecto connection pool size (default: 10) |
| `DATABASE_SSL` | Optional | Set `true` to require SSL for database |

![User Settings](docs/assets/screenshots/settings-authenticated.png)
*The settings page showing Spotify OAuth integration status, SpotDL/FFmpeg tool health, stem engine selection, and LLM provider configuration.*

### Database Setup

```bash
mix ecto.create && mix ecto.migrate
```

### First Admin User

```bash
# Register an account via the web UI, then:
mix promote_admin your@email.com
```

### Development Commands

| Command | Description |
|---------|-------------|
| `mix phx.server` | Start dev server on port 4000 |
| `mix test` | Run full test suite (707 tests) |
| `mix precommit` | Compile + format + test (pre-PR check) |
| `mix credo` | Static analysis |
| `mix dialyzer` | Type checking |
| `mix ecto.reset` | Drop, create, migrate, seed |
| `mix sfa.touchosc.generate` | Generate TouchOSC `.tosc` layout |

</details>

---

## Architecture

<details>
<summary><strong>Stack Overview</strong></summary>

```mermaid
flowchart TD
    Browser["Browser / PWA\n(manifest + sw.js)\nPhoenix LiveView · D3.js · Web Audio API"]

    subgraph PhoenixLayer["Phoenix / Bandit 1.5"]
        LiveViews["LiveViews\nDashboardLive · AdminLive · DjLive · DawLive · MidiLive"]
        JSONAPI["JSON API\nSpotifyController · DownloadController\nProcessingCtrl · AnalysisCtrl"]
        PubSubLayer["PubSub\npipeline:{uid} · debug:{uid} · notifications"]
    end

    subgraph CtxLayer["Domain Contexts"]
        CoreCtx["Music · Accounts · Admin · Agents · LLM"]
        ExtCtx["DJ · DAW · Sampler · MIDI/OSC · Integrations"]
    end

    subgraph ObanLayer["Oban Workers"]
        Workers["Download · Processing · Analysis · LalalAI · AutoCue"]
    end

    subgraph PortLayer["Erlang Ports"]
        Ports["AnalyzerPort · DemucsPort · SpotDL"]
    end

    subgraph LLMLayer["LLM Adapters"]
        LLMs["Anthropic · OpenAI · Azure OpenAI · Gemini\nOllama · LM Studio · LiteLLM · Custom"]
    end

    DB[("PostgreSQL — Ecto 3.13\ntracks · stems · analysis_results · processing_jobs\nusers · user_settings · spotify_oauth_tokens · playlists\nmidi_mappings · dj_tables · edit_operations\nllm_providers · audit_logs · stem_loops · cue_points")]

    Browser -->|"WebSocket (Phoenix Channels)"| PhoenixLayer
    PhoenixLayer --> CtxLayer
    CtxLayer --> ObanLayer
    CtxLayer --> PortLayer
    CtxLayer --> LLMLayer
    ObanLayer --> DB
```

**Technology choices:**

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Web framework | Phoenix 1.8 + LiveView 1.1 | Real-time UI without a custom JS framework |
| HTTP server | Bandit 1.5 | Modern Elixir-native HTTP/1.1 + HTTP/2 |
| Background jobs | Oban 2.18 | PostgreSQL-backed, reliable, observable |
| Audio separation | Demucs + lalal.ai | Best-in-class open source + cloud option |
| Audio analysis | librosa + numpy | Industry-standard Python audio library |
| Download | SpotDL + yt-dlp | Spotify metadata with YouTube audio fallback |
| MIDI | midiex 0.6 | Elixir NIF wrapping RtMidi (Rust) |
| CSS | Tailwind + daisyUI | Utility-first with component presets |
| Encryption | Cloak.Ecto + AES-GCM | Transparent at-rest field encryption |

</details>

<details>
<summary><strong>OTP Supervision Tree</strong></summary>

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

</details>

<details>
<summary><strong>Agent System</strong></summary>

```mermaid
flowchart TD
    Input["User Request"] --> Orch["Orchestrator"]

    Orch -->|"task: hint"| Direct["Direct dispatch"]
    Orch -->|"keyword NLP"| AutoR["Auto-route"]
    Orch -->|"agent list"| Pipeline["Pipeline"]

    subgraph Agents["Specialist Agents"]
        SA["TrackAnalysis · MixPlanning · StemIntelligence\nCuePoint · Mastering · Library"]
    end

    Direct --> Agents
    AutoR --> Agents
    Pipeline --> Agents

    Agents --> Router["LLM.Router\n(build provider chain)"]

    Router --> Primary["Primary\n(LiteLLM)"]
    Router --> FB1["Fallback 1\n(Anthropic)"]
    Router --> FB2["Fallback 2\n(Ollama)"]
```

**Context and Result structs:**

```elixir
%SoundForge.Agents.Context{
  instruction: String.t(),
  track_id: integer() | nil,
  track_ids: [integer()] | nil,
  user_id: integer(),
  metadata: map()
}

%SoundForge.Agents.Result{
  output: term(),
  agent: module(),
  model: String.t(),
  provider: atom(),
  tokens_used: integer(),
  latency_ms: integer()
}
```

</details>

<details>
<summary><strong>PubSub Topics</strong></summary>

| Topic | Events | Subscribers |
|-------|--------|-------------|
| `"jobs:{job_id}"` | Stage progress updates | `DashboardLive`, `JobProgress` component |
| `"track_pipeline:{track_id}"` | Pipeline stage failures | `ObanHandler` → dashboard |
| `"debug:worker_status"` | Worker lifecycle events | Debug Inspector panel |
| `"osc:messages"` | `{:osc_message, msg, sender}` | OSC pipeline |
| `"midi:bridge"` | `{:midi_from_osc, msg}` | MIDI-OSC bridge |
| `"track_playback"` | Play/stop, stem volume/mute/solo | All control surfaces |
| `"notifications:{user_id}"` | User notifications | `AppHeader` bell component |

</details>

<details>
<summary><strong>Database Schema</strong></summary>

**Core Tables**

| Table | Key Columns |
|-------|-------------|
| `tracks` | `id`, `title`, `artist`, `spotify_id`, `file_path`, `user_id` |
| `stems` | `id`, `track_id`, `stem_type`, `file_path`, `engine`, `preview` |
| `analysis_results` | `id`, `track_id`, `bpm`, `key`, `energy`, `chroma`, `mfcc`, `spectral` |
| `processing_jobs` | `id`, `track_id`, `stage`, `status`, `engine`, `options` |
| `playlists` | `id`, `user_id`, `name`, `spotify_id`, `source` |
| `playlist_tracks` | `playlist_id`, `track_id`, `position` |

**User Tables**

| Table | Key Columns |
|-------|-------------|
| `users` | `id`, `email`, `hashed_password`, `role`, `status` |
| `user_settings` | `user_id`, `debug_mode`, `stem_engine`, `lalalai_api_key` (encrypted) |
| `spotify_oauth_tokens` | `user_id`, `access_token`, `refresh_token`, `expires_at` |
| `audit_logs` | `id`, `actor_id`, `target_type`, `target_id`, `action`, `inserted_at` |

**Integration Tables**

| Table | Description |
|-------|-------------|
| `midi_mappings` | MIDI CC/note to action mappings per device |
| `dj_presets` | Saved DJ deck configurations |
| `edit_operations` | DAW clip edit history |
| `melodics_sessions` | Melodics practice session records |
| `llm_providers` | Per-user LLM provider configs (API keys encrypted at rest) |
| `stem_loops` | Extracted loop regions from stems |
| `cue_points` | Track cue points with auto-cue metadata |
| `batch_jobs` | Batch processing job groups |
| `voice_packs` | Voice pack definitions for voice change worker |

</details>

<details>
<summary><strong>Project Structure</strong></summary>

```
lib/
├── sound_forge/
│   ├── agents/             # AI agent system (orchestrator + 6 specialists)
│   ├── llm/                # Multi-provider LLM router + 9 adapters
│   ├── audio/              # Erlang ports: AnalyzerPort, DemucsPort, lalal.ai client
│   ├── jobs/               # Oban workers: Download, Processing, Analysis, AutoCue, etc.
│   ├── music/              # Core schemas: Track, Stem, AnalysisResult, ProcessingJob
│   ├── accounts/           # User auth, sessions, OAuth tokens, role scopes
│   ├── admin/              # Admin context, audit log
│   ├── midi/               # MIDI device manager, parser, MPC profiles
│   ├── osc/                # OSC server, client, parser, TouchOSC layout generator
│   ├── bridge/             # MIDI-OSC bidirectional translation
│   ├── dj/                 # DJ presets
│   ├── daw/                # DAW state management
│   ├── sampler/            # Sampler context
│   ├── debug/              # Debug jobs inspector, log broadcaster
│   ├── telemetry/          # Oban telemetry handler
│   ├── integrations/       # Melodics session import
│   └── processing/         # Demucs model configuration
└── sound_forge_web/
    ├── live/               # LiveViews: Dashboard, Admin, DJ, DAW, MIDI, Practice, Settings
    ├── controllers/        # API controllers + auth controllers
    ├── plugs/              # APIAuth, RateLimiter, SecurityHeaders
    └── components/         # Shared UI components (stem mixer, debug panel, etc.)

assets/js/hooks/
├── dj_deck.js              # 711-line virtual DJ deck
├── daw_editor.js           # 700-line WebAudio arrangement editor
├── audio_player.js         # Stem switching audio player
├── stem_mixer_hook.js      # Touch + mouse fader control (60fps)
├── analysis_*.js           # 7 D3.js visualization hooks
├── jog_wheel.js            # Hardware jog wheel emulation
└── pad_assign_hook.js      # Drag-and-drop MPC pad assignment

priv/python/
├── analyzer.py             # librosa audio analysis script
└── demucs_runner.py        # Demucs stem separation wrapper
```

</details>

---

## API Reference

<details>
<summary><strong>REST Endpoints</strong></summary>

**Public**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | System health check |

**Authenticated** — rate limit: 60 req/min

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/spotify/fetch` | Fetch Spotify track metadata |
| `GET` | `/api/download/job/:id` | Poll download job status |
| `GET` | `/api/processing/job/:id` | Poll processing job status |
| `GET` | `/api/processing/models` | List available Demucs models |
| `GET` | `/api/analysis/job/:id` | Poll analysis job status |
| `GET` | `/api/lalalai/quota` | Get lalal.ai account quota |

**Heavy** — rate limit: 10 req/min

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/download/track` | Create download job |
| `POST` | `/api/processing/separate` | Enqueue stem separation |
| `POST` | `/api/analysis/analyze` | Enqueue audio analysis |
| `POST` | `/api/daw/export` | Export DAW arrangement |
| `POST` | `/api/lalalai/cancel` | Cancel lalal.ai job |
| `POST` | `/api/lalalai/cancel-all` | Cancel all lalal.ai jobs |

**File / Export (browser, authenticated)**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/files/*path` | Serve audio files |
| `GET` | `/export/stem/:id` | Download single stem |
| `GET` | `/export/stems/:track_id` | Download all stems as `.zip` |
| `GET` | `/export/analysis/:track_id` | Export analysis as JSON |

**Spotify OAuth**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/auth/spotify` | Initiate OAuth PKCE flow |
| `GET` | `/auth/spotify/callback` | Handle callback, store tokens |

</details>

<details>
<summary><strong>LiveView Routes</strong></summary>

| Path | LiveView | Description |
|------|----------|-------------|
| `/` | `DashboardLive` | Main dashboard — Library, Player, DJ, DAW, Debug tabs |
| `/settings` | `SettingsLive` | User preferences, LLM providers, stem engine |
| `/admin` | `AdminLive` | Admin panel (admin role required) |
| `/midi` | `MidiLive` | MIDI device configuration |
| `/practice` | `PracticeLive` | Melodics practice session display |

</details>

<details>
<summary><strong>Testing</strong></summary>

```bash
mix test                    # All 707 tests
mix test test/sound_forge/  # Context/worker tests only
mix test test/sound_forge_web/ # Web/LiveView tests
mix test --failed           # Re-run previously failed
mix test path/to_test.exs:42 # Specific test by line
```

**Test infrastructure:**
- `ExUnit` with `Ecto.Adapters.SQL.Sandbox` for database isolation
- `Mox` for Spotify API mocking via behaviour (`SoundForge.Spotify.Client`)
- `Oban.Testing` with `testing: :manual` mode
- `Phoenix.LiveViewTest` for LiveView integration testing
- `Req.Test` stubs for HTTP client testing

</details>

---

## Deployment

<details>
<summary><strong>Azure Container Apps (live production)</strong></summary>

**Live:** `https://sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io`

**Build** (amd64 only — BEAM cannot run under QEMU on Apple Silicon):

```bash
az acr build \
  --registry <your-acr> \
  --image sfa:latest \
  --platform linux/amd64 \
  .
```

**Deploy:**

```bash
az containerapp update \
  --name sfa-app \
  --resource-group <rg> \
  --image <your-acr>.azurecr.io/sfa:latest
```

**Required environment variables:**

```
DATABASE_URL          = ecto://user:pass@host/db
SECRET_KEY_BASE       = <64-char secret>
SPOTIFY_CLIENT_ID     = <from Spotify developer portal>
SPOTIFY_CLIENT_SECRET = <from Spotify developer portal>
PHX_HOST              = sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io
PHX_SERVER            = true
DATABASE_SSL          = true
```

> **Build constraints:** Do not use `ARG` interpolation in `FROM` directives. Combine all `COPY` + compile steps into a single `RUN` layer to avoid "MixProject already compiled" errors. Image is ~4.8 GB due to Python dependencies.

</details>

<details>
<summary><strong>Docker (local / self-hosted)</strong></summary>

```yaml
# docker-compose.yml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: sound_forge
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data

  app:
    image: sfa:latest
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://postgres:postgres@db/sound_forge
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"
      SPOTIFY_CLIENT_ID: "${SPOTIFY_CLIENT_ID}"
      SPOTIFY_CLIENT_SECRET: "${SPOTIFY_CLIENT_SECRET}"
      PHX_SERVER: "true"
    depends_on:
      - db

volumes:
  pgdata:
```

```bash
docker compose up
```

</details>

<details>
<summary><strong>Mix Release (bare metal / VPS)</strong></summary>

```bash
# Build
MIX_ENV=prod mix do assets.deploy, release

# Migrate
_build/prod/rel/sound_forge/bin/migrate

# Start
_build/prod/rel/sound_forge/bin/server
```

Release scripts are in `rel/overlays/bin/`.

</details>

---

## Changelog

Full history: [CHANGELOG.md](CHANGELOG.md)

| Version | Date | Highlights |
|---------|------|-----------|
| [v4.3.0](CHANGELOG.md#430---2026-02-25) | 2026-02-25 | Multi-LLM routing, 6 specialist AI agents, 707 tests |
| [v4.2.12](CHANGELOG.md#4212---2026-02-25) | 2026-02-25 | Azure Container Apps production deployment |
| [v4.2.11](CHANGELOG.md#4211---2026-02-24) | 2026-02-24 | Analysis expansion + DAW/DJ tabs (PR #9) |
| [v4.2.10](CHANGELOG.md#4210---2026-02-24) | 2026-02-24 | Full lalal.ai API v1.1.0 + DAW/DJ hooks (PR #7) |
| [v4.2.8](CHANGELOG.md#428---2026-02-19) | 2026-02-19 | SaaS role hierarchy + audit log (PR #6) |
| [v4.2.7](CHANGELOG.md#427---2026-02-19) | 2026-02-19 | Melodics, OSC, TouchOSC, responsive layout (PR #2) |
| [v4.2.5](CHANGELOG.md#425---2026-02-19) | 2026-02-19 | USB/network MIDI + MPC controller (PR #1) |
| [v4.2.3](CHANGELOG.md#423---2026-02-19) | 2026-02-19 | lalal.ai cloud stem separation |
| [v4.2.2](CHANGELOG.md#422---2026-02-18) | 2026-02-18 | 5 D3.js analysis visualization hooks |
| [v4.2.1](CHANGELOG.md#421---2026-02-17) | 2026-02-17 | yt-dlp fallback + debug panel (10 user stories) |
| [v4.0.0](CHANGELOG.md#400---2026-02-14) | 2026-02-14 | Spotify OAuth, playlists, settings, notifications |
| [v3.0.0](CHANGELOG.md#300---2026-02-13) | 2026-02-13 | Security hardening, rate limiting, IDOR guards |
| [v2.0.0](CHANGELOG.md#200---2026-02-13) | 2026-02-13 | SpotDL replaces direct Spotify API |
| [v1.0.0](CHANGELOG.md#100---2026-02-13) | 2026-02-13 | Feature-complete MVP, 653 tests |
| [v0.1.0](CHANGELOG.md#010---2026-02-12) | 2026-02-12 | Initial Phoenix scaffold |

---

## Contributing

Pull requests welcome. For substantial changes, open an issue first.

![Prototype Sandbox](docs/assets/screenshots/prototype-authenticated.png)
*The prototype sandbox with the Components tab open, showcasing the daisyUI/Tailwind design system elements used throughout the application.*

**Before submitting:**

```bash
mix precommit    # compile --warnings-as-errors + format + test
```

**Standards:**
- Strict Elixir typespecs on all public functions
- `@moduledoc` on all modules
- Credo compliance (`.credo.exs` in repo root)
- Dialyzer clean on all new modules
- Contexts return `{:ok, _} | {:error, _}` tuples
- External services mocked via behaviours + Mox

---

## Built with Claude Code

This project was ported from its original React/Node.js prototype to the current Elixir/Phoenix production stack almost entirely using [Claude Code](https://github.com/anthropics/claude-code) (Anthropic's CLI for Claude). Two custom Claude Code skills were central to the process:

- **`/elixir-architect`** — OTP supervision tree design, Phoenix context boundaries, domain model definition, and comprehensive architecture documentation generation
- **`/ralph`** — Autonomous fix loop methodology: PRD-driven user story decomposition, wave-based parallel agent execution, and TDD enforcement across all 707 tests

The vast majority of implementation — schemas, Oban workers, LiveViews, JS hooks, Python audio ports, tests, docs, and deployment configs — was authored through Claude Code sessions. If you're curious how an AI-assisted Elixir port works at this scale, the [git history](https://github.com/peguesj/sound-forge-alchemy/commits/main) tells the story.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
