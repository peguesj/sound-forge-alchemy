# Sound Forge Alchemy

Audio stem separation and analysis platform built with Phoenix 1.8 and LiveView. Paste a Spotify URL, download the audio, separate it into stems (vocals, drums, bass, other) using Demucs, analyze audio features with librosa, and explore everything in a real-time dashboard.

<!-- Screenshot placeholder: add a screenshot of the dashboard here -->
<!-- ![Dashboard Screenshot](docs/images/dashboard.png) -->

## Architecture

```
                         Browser (LiveView WebSocket)
                                    |
                         +----------+----------+
                         |   Phoenix Endpoint   |
                         |   (Bandit / Port 4000)|
                         +----------+----------+
                                    |
              +---------------------+---------------------+
              |                     |                     |
      DashboardLive          API Controllers        JobChannel
      (LiveView 1.1)        (JSON REST)           (WebSocket)
              |                     |                     |
              +---------------------+---------------------+
                                    |
                    +---------------+---------------+
                    |               |               |
               Music Context   Spotify Context  Jobs Contexts
               (CRUD + Search)  (URL Parse +    (Download,
                    |            API Fetch)     Processing,
                    |               |           Analysis)
                    |               |               |
                    +-------+-------+               |
                            |                       |
                      PostgreSQL              Oban Workers
                     (Ecto 3.13)             (Background Jobs)
                                                    |
                                          +---------+---------+
                                          |                   |
                                    DemucsPort          AnalyzerPort
                                   (GenServer)          (GenServer)
                                          |                   |
                                    Python/Demucs       Python/librosa
                                   (Erlang Port)        (Erlang Port)
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.15+ |
| Web Framework | Phoenix 1.8 |
| Real-Time UI | LiveView 1.1 |
| Database | PostgreSQL via Ecto 3.13 |
| Background Jobs | Oban 2.18 |
| HTTP Client | Req |
| HTTP Server | Bandit |
| Python Interop | Erlang Ports (GenServer wrappers) |
| Stem Separation | Demucs (Python) |
| Audio Analysis | librosa (Python) |
| CSS | Tailwind CSS v4 |
| JS Bundler | esbuild |
| JSON | Jason |

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

### Optional Tools

- **spotdl** for Spotify audio downloads: `pip install spotdl`

### Setup

```bash
# Clone the repository
git clone <repo-url> sound-forge-alchemy
cd sound-forge-alchemy

# Install Elixir dependencies, create database, build assets
mix setup

# Start the development server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) in your browser.

To start inside an IEx shell:

```bash
iex -S mix phx.server
```

## Development Commands

| Command | Description |
|---------|-------------|
| `mix setup` | Install deps, create DB, run migrations, build assets |
| `mix phx.server` | Start the development server on port 4000 |
| `mix test` | Run all tests (125 passing) |
| `mix test --failed` | Re-run only previously failed tests |
| `mix format` | Format all Elixir files |
| `mix precommit` | Compile (warnings-as-errors) + format + test |
| `mix ecto.migrate` | Run pending database migrations |
| `mix ecto.reset` | Drop, create, migrate, and seed the database |
| `mix ecto.gen.migration name` | Generate a new migration file |

## Project Structure

```
lib/
├── sound_forge/
│   ├── application.ex              # OTP supervision tree (Repo, PubSub, Oban)
│   ├── repo.ex                     # Ecto repository
│   ├── music.ex                    # Music context - CRUD for all schemas
│   ├── music/
│   │   ├── track.ex                # Track schema (spotify_id, title, artist, ...)
│   │   ├── download_job.ex         # Download job with Ecto.Enum status
│   │   ├── processing_job.ex       # Stem separation job (model, progress)
│   │   ├── analysis_job.ex         # Audio analysis job (results map)
│   │   ├── stem.ex                 # Individual stem (vocals/drums/bass/other)
│   │   └── analysis_result.ex      # Extracted features (tempo, key, energy, ...)
│   ├── spotify.ex                  # Spotify context (fetch_metadata/1)
│   ├── spotify/
│   │   ├── client.ex               # Behaviour for Spotify API (mockable)
│   │   ├── http_client.ex          # Req-based Spotify HTTP client
│   │   └── url_parser.ex           # Parse Spotify track/album/playlist URLs
│   ├── audio/
│   │   ├── analyzer_port.ex        # GenServer wrapping librosa Python script
│   │   └── demucs_port.ex          # GenServer wrapping Demucs Python script
│   ├── jobs/
│   │   ├── download.ex             # Download job context
│   │   ├── download_worker.ex      # Oban worker for audio downloads
│   │   ├── processing.ex           # Processing job context
│   │   └── analysis.ex             # Analysis job context
│   ├── processing/
│   │   └── demucs.ex               # Demucs model configuration
│   └── storage.ex                  # Local file storage management
├── sound_forge_web/
│   ├── router.ex                   # Routes (browser + API)
│   ├── live/
│   │   ├── dashboard_live.ex       # Main dashboard LiveView
│   │   ├── dashboard_live.html.heex
│   │   ├── audio_player_live.ex    # Audio player (stub)
│   │   └── components/             # LiveView components
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── spotify_controller.ex
│   │   │   ├── download_controller.ex
│   │   │   ├── processing_controller.ex
│   │   │   └── analysis_controller.ex
│   │   ├── file_controller.ex      # Serve stored audio files
│   │   └── health_controller.ex    # Health check endpoint
│   ├── channels/
│   │   ├── user_socket.ex
│   │   └── job_channel.ex          # Real-time job progress
│   └── components/
│       ├── core_components.ex      # Shared UI components
│       └── layouts.ex              # App and root layouts
├── config/
│   ├── config.exs                  # Base config (Oban queues, Ecto, esbuild)
│   ├── dev.exs                     # Development config
│   ├── test.exs                    # Test config (Mox, Oban testing mode)
│   └── runtime.exs                 # Runtime/production config
├── priv/
│   ├── python/
│   │   ├── analyzer.py             # librosa audio analysis script
│   │   └── demucs_runner.py        # Demucs stem separation wrapper
│   ├── repo/migrations/            # Ecto migrations
│   └── static/                     # Compiled assets
└── test/
    ├── sound_forge/                # Context and schema tests
    ├── sound_forge_web/            # Controller, LiveView, channel tests
    └── support/                    # Test helpers, fixtures, cases
```

## API Endpoints

### Browser Routes

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| GET | `/` | `DashboardLive` | Main dashboard |
| GET | `/tracks/:id` | `DashboardLive :show` | Track detail view |
| GET | `/files/*path` | `FileController` | Serve stored files |
| GET | `/health` | `HealthController` | Health check |

### JSON API Routes (`/api`)

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| POST | `/api/spotify/fetch` | `SpotifyController.fetch` | Fetch Spotify metadata |
| POST | `/api/download/track` | `DownloadController.create` | Start audio download |
| GET | `/api/download/job/:id` | `DownloadController.show` | Get download job status |
| POST | `/api/processing/separate` | `ProcessingController.create` | Start stem separation |
| GET | `/api/processing/job/:id` | `ProcessingController.show` | Get processing job status |
| GET | `/api/processing/models` | `ProcessingController.models` | List available Demucs models |
| POST | `/api/analysis/analyze` | `AnalysisController.create` | Start audio analysis |
| GET | `/api/analysis/job/:id` | `AnalysisController.show` | Get analysis job status |

### Development Routes (dev only)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/dev/dashboard` | Phoenix LiveDashboard |
| GET | `/dev/mailbox` | Swoosh mailbox preview |

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

## License

All rights reserved.
