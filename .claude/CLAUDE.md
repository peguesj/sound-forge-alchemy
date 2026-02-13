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
