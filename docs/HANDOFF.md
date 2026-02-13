# Sound Forge Alchemy - Agent Handoff Document

## Project Overview

Sound Forge Alchemy (SFA) is an audio stem separation and analysis platform built with Phoenix 1.8 and LiveView 1.1. It replaces a Node.js/TypeScript microservices architecture with a single Elixir OTP release.

**Core workflow**: User pastes Spotify URL -> Fetch metadata -> Download audio -> Separate stems (Demucs) -> Analyze features (librosa) -> Display in real-time dashboard.

### Current Status

- **Compilation**: Zero warnings (`mix compile --warnings-as-errors` passes)
- **Tests**: 125/125 passing (`mix test`)
- **Server**: Running on `localhost:4000`
- **Dashboard**: Live and functional with track listing, search, and Spotify URL input
- **Database**: PostgreSQL with all migrations applied (tracks, download_jobs, processing_jobs, analysis_jobs, stems, analysis_results, oban_jobs)

## Documentation Index

| Document | Location | Purpose |
|----------|----------|---------|
| Project CLAUDE.md | `.claude/CLAUDE.md` | AI agent coding instructions |
| This handoff | `docs/HANDOFF.md` | Agent collaboration and project state |
| README | `README.md` | Getting started and project overview |
| AGENTS.md | `AGENTS.md` | Phoenix/Elixir/LiveView coding guidelines |
| API docs | `docs/api/` | API endpoint documentation (to be populated) |
| Architecture | `docs/architecture/` | Architecture decision records (to be populated) |
| Decisions | `docs/decisions/` | Technical decision log (to be populated) |
| Design | `docs/design/` | UI/UX design notes (to be populated) |
| Guardrails | `docs/guardrails/` | Quality and safety constraints (to be populated) |
| Plans | `docs/plans/` | Implementation plans (to be populated) |

## Implementation Workflow (Ralph Methodology)

This project follows the Ralph methodology for iterative development:

1. **PRD**: Define the product requirement for the feature
2. **User Stories**: Break down into user stories with acceptance criteria
3. **Red-Green-Refactor**: Write failing tests first, then implement, then refactor
4. **Iterate**: Ship incrementally, verify with `mix precommit` after each step

### Pre-Commit Checklist

Every change must pass before being considered complete:

```bash
mix precommit
# Runs: compile --warnings-as-errors -> deps.unlock --unused -> format -> test
```

## What Is Built

### Contexts and Schemas

| Module | Status | Notes |
|--------|--------|-------|
| `SoundForge.Music` | Complete | Full CRUD for Track, DownloadJob, ProcessingJob, AnalysisJob, Stem, AnalysisResult |
| `SoundForge.Spotify` | Complete | URL parsing, metadata fetching with behaviour + Mox mock |
| `SoundForge.Spotify.URLParser` | Complete | Parses track/album/playlist URLs |
| `SoundForge.Spotify.HTTPClient` | Complete | Req-based client with ETS token caching |
| `SoundForge.Spotify.Client` | Complete | Behaviour definition for mocking |
| `SoundForge.Storage` | Complete | Local file management (store, delete, stats, cleanup) |
| `SoundForge.Audio.AnalyzerPort` | Complete | GenServer wrapping librosa Python script |
| `SoundForge.Audio.DemucsPort` | Complete | GenServer wrapping Demucs stem separation |
| `SoundForge.Jobs.Download` | Complete | Download job context (create, get, enqueue) |
| `SoundForge.Jobs.Processing` | Complete | Processing job context (create, get) |
| `SoundForge.Jobs.Analysis` | Complete | Analysis job context (create, get) |
| `SoundForge.Jobs.DownloadWorker` | Complete | Oban worker for spotdl downloads |

### Web Layer

| Module | Status | Notes |
|--------|--------|-------|
| `SoundForgeWeb.DashboardLive` | Complete | Track list with streams, search, Spotify fetch |
| `SoundForgeWeb.AudioPlayerLive` | Stub | Template exists, no playback logic |
| `SoundForgeWeb.API.SpotifyController` | Complete | POST `/api/spotify/fetch` |
| `SoundForgeWeb.API.DownloadController` | Complete | POST `/api/download/track`, GET `/api/download/job/:id` |
| `SoundForgeWeb.API.ProcessingController` | Complete | POST `/api/processing/separate`, GET `/api/processing/job/:id`, GET `/api/processing/models` |
| `SoundForgeWeb.API.AnalysisController` | Complete | POST `/api/analysis/analyze`, GET `/api/analysis/job/:id` |
| `SoundForgeWeb.FileController` | Complete | GET `/files/*path` for serving stored files |
| `SoundForgeWeb.HealthController` | Complete | GET `/health` |
| `SoundForgeWeb.JobChannel` | Complete | WebSocket channel for job progress |

### Tests (125 passing)

| Test File | Coverage |
|-----------|----------|
| `test/sound_forge/music_test.exs` | Track, DownloadJob, ProcessingJob, AnalysisJob, Stem, AnalysisResult CRUD |
| `test/sound_forge/spotify_test.exs` | URL parsing, metadata fetching with Mox |
| `test/sound_forge/audio_test.exs` | AnalyzerPort, DemucsPort feature validation |
| `test/sound_forge/jobs_test.exs` | Download, Processing, Analysis contexts |
| `test/sound_forge/storage_test.exs` | Storage operations |
| `test/sound_forge_web/live/dashboard_live_test.exs` | Dashboard mount, search, stream rendering |
| `test/sound_forge_web/live/audio_player_test.exs` | Audio player stub |
| `test/sound_forge_web/controllers/api/` | All API controller endpoints |
| `test/sound_forge_web/controllers/health_controller_test.exs` | Health check |
| `test/sound_forge_web/channels/job_channel_test.exs` | Job channel join/events |

## What Is Remaining

### Phase 1: Complete the Job Pipeline (ProcessingWorker + AnalysisWorker)

**Goal**: Wire up Oban workers that actually call the Erlang Ports.

- [ ] `SoundForge.Jobs.ProcessingWorker` - Oban worker for stem separation
  - Calls `DemucsPort.separate/2` with the downloaded audio file
  - Creates `Stem` records for each output (vocals, drums, bass, other)
  - Broadcasts progress via PubSub
  - Triggers AnalysisWorker on completion
- [ ] `SoundForge.Jobs.AnalysisWorker` - Oban worker for audio analysis
  - Calls `AnalyzerPort.analyze/2` with audio file
  - Creates `AnalysisResult` record with extracted features
  - Broadcasts progress via PubSub
- [ ] Chain workers: Download -> Processing -> Analysis (Oban job dependencies or PubSub triggers)
- [ ] Add Ports to the supervision tree in `application.ex` (currently commented out)

### Phase 2: AudioPlayerLive (Stem Playback)

**Goal**: Interactive audio player with individual stem volume controls.

- [ ] `SoundForgeWeb.AudioPlayerLive` - Full implementation
  - Load stems for a track from the database
  - JS Hook for Web Audio API (multi-track playback)
  - Individual volume sliders per stem (vocals, drums, bass, other)
  - Master playback controls (play/pause, seek, timeline)
  - Waveform visualization per stem
- [ ] Colocated JS hook or external hook in `assets/js/` for Web Audio API
- [ ] File serving for stem audio files via `FileController`

### Phase 3: Track Detail View

**Goal**: Full track detail page with analysis visualization.

- [ ] Track detail LiveView (may extend `DashboardLive` with `:show` action or create new)
- [ ] Display analysis results (tempo, key, energy, spectral features)
- [ ] Waveform visualization (could use WaveSurfer.js via JS hook)
- [ ] Chromagram / spectrogram display
- [ ] Link to audio player for stem playback

### Phase 4: Authentication and Multi-User

**Goal**: User accounts and track ownership.

- [ ] `mix phx.gen.auth` for user authentication
- [ ] Associate tracks with users
- [ ] Private track libraries
- [ ] Rate limiting on API endpoints

## Key Architectural Principles

### DO: Use the Database as Truth

```elixir
# CORRECT: Persist state before broadcasting
def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
  job = Music.get_download_job!(job_id)
  {:ok, job} = Music.update_download_job(job, %{status: :downloading})
  broadcast_progress(job_id, :downloading, 0)
  # ...
end
```

```elixir
# WRONG: Broadcasting without persisting
def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
  broadcast_progress(job_id, :downloading, 0)  # State lost on crash!
  # ...
end
```

### DO: Go Through Contexts

```elixir
# CORRECT: Controller calls context
def create(conn, %{"url" => url}) do
  case Jobs.Download.create_job(url) do
    {:ok, job} -> json(conn, %{job_id: job.id})
    {:error, reason} -> json(conn |> put_status(422), %{error: reason})
  end
end
```

```elixir
# WRONG: Controller calls Repo directly
def create(conn, %{"url" => url}) do
  {:ok, job} = Repo.insert(%DownloadJob{...})  # Bypasses business logic!
end
```

### DO: Use Streams for LiveView Collections

```elixir
# CORRECT: Stream for track list
def mount(_params, _session, socket) do
  {:ok, stream(socket, :tracks, Music.list_tracks())}
end

# In template:
# <div id="tracks" phx-update="stream">
#   <div :for={{id, track} <- @streams.tracks} id={id}>...</div>
# </div>
```

```elixir
# WRONG: Assigning a list
def mount(_params, _session, socket) do
  {:ok, assign(socket, :tracks, Music.list_tracks())}  # Memory balloons!
end
```

### DO: Use Behaviours for Testability

```elixir
# The Spotify client is swappable via config
defp spotify_client do
  Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
end

# In test config:
# config :sound_forge, :spotify_client, SoundForge.Spotify.MockClient
```

### DON'T: Start Python Processes as Microservices

```elixir
# CORRECT: Use Erlang Ports
Port.open({:spawn_executable, python}, [:binary, :exit_status, args: [script | args]])

# WRONG: HTTP calls to a Python service
Req.post!("http://localhost:8000/analyze", json: %{file: path})
```

## Testing Strategy

### Unit Tests (Context Layer)
- Test each context function in isolation
- Use `DataCase` for database-backed tests with sandbox isolation
- Use Mox for external service boundaries (Spotify API)

### Integration Tests (Web Layer)
- Controller tests via `ConnCase` with JSON assertions
- LiveView tests via `Phoenix.LiveViewTest` with `has_element?/2`
- Channel tests via `ChannelCase`

### Worker Tests
- Use `Oban.Testing` with `testing: :manual` mode
- Assert jobs are enqueued with correct args: `assert_enqueued(worker: DownloadWorker)`
- Test worker `perform/1` directly with constructed `%Oban.Job{}` structs

### Fixtures
- `test/support/fixtures/music_fixtures.ex` - Track and job factory functions
- All fixtures use the context layer (e.g., `Music.create_track/1`)

## How to Run

### First-Time Setup
```bash
# Prerequisites: Elixir 1.15+, PostgreSQL running, Python 3 with librosa + demucs
mix setup           # deps.get, ecto.setup, assets.setup, assets.build
```

### Development
```bash
mix phx.server      # Start server on localhost:4000
iex -S mix phx.server  # Start with IEx shell
```

### Testing
```bash
mix test            # Run all 125 tests
mix test --failed   # Re-run only failed tests
mix precommit       # Full pre-commit check (compile + format + test)
```

### Database
```bash
mix ecto.create     # Create database
mix ecto.migrate    # Run migrations
mix ecto.reset      # Drop + recreate + migrate + seed
mix ecto.gen.migration name  # Generate new migration
```

## Schema Summary

```
Track (binary_id)
├── spotify_id, spotify_url, title, artist, album, album_art_url, duration
├── has_many :download_jobs
├── has_many :processing_jobs
├── has_many :analysis_jobs
├── has_many :stems
└── has_many :analysis_results

DownloadJob (binary_id)
├── status (Ecto.Enum: queued|downloading|processing|completed|failed)
├── progress (0-100), output_path, file_size, error
└── belongs_to :track

ProcessingJob (binary_id)
├── model (default: "htdemucs"), status, progress, output_path, options, error
├── belongs_to :track
└── has_many :stems

AnalysisJob (binary_id)
├── status, progress, results (map), error
├── belongs_to :track
└── has_one :analysis_result

Stem (binary_id)
├── stem_type (Ecto.Enum: vocals|drums|bass|other), file_path, file_size
├── belongs_to :track
└── belongs_to :processing_job

AnalysisResult (binary_id)
├── tempo, key, energy, spectral_centroid, spectral_rolloff, zero_crossing_rate, features (map)
├── belongs_to :track
└── belongs_to :analysis_job
```

## PubSub Topics

| Topic | Publisher | Subscriber | Payload |
|-------|-----------|------------|---------|
| `"tracks"` | Context functions | DashboardLive | `{:track_added, %Track{}}` |
| `"jobs:{job_id}"` | Oban workers | LiveViews, JobChannel | `{:job_progress, %{job_id, status, progress}}` |
