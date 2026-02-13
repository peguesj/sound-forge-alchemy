# 04 -- Context Boundaries

## Overview

Sound Forge Alchemy organizes its domain logic into five context boundaries following the Phoenix convention of bounded contexts. Each context owns its schemas, business logic, and external interface. Cross-context communication happens through explicit function calls and PubSub events -- never through shared database queries or implicit coupling.

```
+------------------+     +------------------+     +------------------+
|   Music Context  |     | Spotify Context  |     |  Jobs Context    |
|                  |     |                  |     |                  |
|  Track           |<--->|  URLParser       |---->|  Download        |
|  DownloadJob     |     |  Client (behav.) |     |  Processing      |
|  ProcessingJob   |     |  HTTPClient      |     |  Analysis        |
|  AnalysisJob     |     |                  |     |  DownloadWorker  |
|  Stem            |     +------------------+     +------------------+
|  AnalysisResult  |            |                        |
+------------------+            |                        |
       ^                        v                        v
       |                 +------------------+     +------------------+
       |                 |   Audio Context  |     | Storage Context  |
       |                 |                  |     |                  |
       +---------------->|  AnalyzerPort    |     |  downloads/      |
                         |  DemucsPort      |     |  stems/          |
                         |                  |     |  analysis/       |
                         +------------------+     +------------------+
```

---

## Context Definitions

### Music Context (`SoundForge.Music`)

The Music context is the core data domain. It owns all Ecto schemas and provides CRUD operations for every persistent entity in the system. Other contexts depend on Music for data access but never reach into its schemas directly.

**Module**: `lib/sound_forge/music.ex`

**Schemas owned**:
- `SoundForge.Music.Track` -- core entity, represents a music track
- `SoundForge.Music.DownloadJob` -- tracks download progress and state
- `SoundForge.Music.ProcessingJob` -- tracks stem separation progress
- `SoundForge.Music.AnalysisJob` -- tracks audio analysis progress
- `SoundForge.Music.Stem` -- individual stem file metadata (vocals, drums, bass, other)
- `SoundForge.Music.AnalysisResult` -- extracted audio features (tempo, key, energy, spectral)

**Public API**:

```elixir
# Track operations
Music.list_tracks()                          # => [%Track{}, ...]
Music.search_tracks("beatles")               # => [%Track{artist: "The Beatles", ...}]
Music.get_track!(id)                         # => %Track{} | raises
Music.create_track(%{title: "Song"})         # => {:ok, %Track{}} | {:error, changeset}
Music.update_track(track, %{artist: "..."})  # => {:ok, %Track{}} | {:error, changeset}
Music.delete_track(track)                    # => {:ok, %Track{}} | {:error, changeset}

# Job operations (download, processing, analysis)
Music.get_download_job!(id)
Music.create_download_job(%{track_id: id, status: :queued})
Music.update_download_job(job, %{status: :completed, progress: 100})

Music.get_processing_job!(id)
Music.create_processing_job(%{track_id: id, model: "htdemucs"})
Music.update_processing_job(job, attrs)

Music.get_analysis_job!(id)
Music.create_analysis_job(%{track_id: id, status: :queued})
Music.update_analysis_job(job, attrs)

# Stem and result operations
Music.list_stems_for_track(track_id)
Music.create_stem(%{track_id: id, processing_job_id: jid, stem_type: :vocals})
Music.get_analysis_result_for_track(track_id)
Music.create_analysis_result(%{track_id: id, analysis_job_id: jid, tempo: 120.0})
```

**Boundary rules**:
- Only Music context modules directly `import Ecto.Query` for these schemas
- Controllers and LiveViews call Music context functions, never `Repo.get` directly
- All changeset validation lives inside the schema modules

---

### Spotify Context (`SoundForge.Spotify`)

The Spotify context encapsulates all interaction with the Spotify Web API. It owns URL parsing, OAuth token management, and API request logic. The rest of the application only sees `fetch_metadata/1` -- the implementation details of authentication and HTTP transport are completely hidden.

**Modules**:
- `lib/sound_forge/spotify.ex` -- public API, routing by resource type
- `lib/sound_forge/spotify/url_parser.ex` -- regex-based URL parsing
- `lib/sound_forge/spotify/client.ex` -- behaviour definition
- `lib/sound_forge/spotify/http_client.ex` -- Req-based implementation with ETS token cache

**Public API**:

```elixir
SoundForge.Spotify.fetch_metadata("https://open.spotify.com/track/abc123")
# => {:ok, %{"id" => "abc123", "name" => "Song Name", "artists" => [...]}}

SoundForge.Spotify.fetch_metadata("invalid-url")
# => {:error, :invalid_spotify_url}
```

**Internal architecture**:

```elixir
# The context module dispatches to the configured client implementation
defmodule SoundForge.Spotify do
  def fetch_metadata(url) do
    with {:ok, %{type: type, id: id}} <- URLParser.parse(url) do
      client = spotify_client()  # configurable for testing
      case type do
        "track"    -> client.fetch_track(id)
        "album"    -> client.fetch_album(id)
        "playlist" -> client.fetch_playlist(id)
      end
    end
  end

  defp spotify_client do
    Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
  end
end
```

**Behaviour for testability**:

```elixir
defmodule SoundForge.Spotify.Client do
  @callback fetch_track(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_album(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_playlist(String.t()) :: {:ok, map()} | {:error, term()}
end
```

This allows test configuration to swap in a mock:

```elixir
# config/test.exs
config :sound_forge, :spotify_client, SoundForge.Spotify.MockClient
```

**Boundary rules**:
- No other context touches the Spotify API directly
- Token management is entirely internal to HTTPClient
- URL parsing is the only stateless utility -- everything else requires credentials

---

### Jobs Context (`SoundForge.Jobs`)

The Jobs context orchestrates background work. It provides higher-level coordination on top of the Music context's CRUD operations and Oban's worker infrastructure. Each sub-module (Download, Processing, Analysis) handles the lifecycle of creating a job record, enqueuing the Oban worker, and providing status lookups.

**Modules**:
- `lib/sound_forge/jobs/download.ex` -- download job orchestration
- `lib/sound_forge/jobs/download_worker.ex` -- Oban worker for spotdl execution
- `lib/sound_forge/jobs/processing.ex` -- stem separation job orchestration
- `lib/sound_forge/jobs/analysis.ex` -- audio analysis job orchestration

**Orchestration pattern** (Download as canonical example):

```elixir
defmodule SoundForge.Jobs.Download do
  alias SoundForge.Music
  alias SoundForge.Repo

  def create_job(url) when is_binary(url) do
    with {:ok, track} <- find_or_create_track(url),
         {:ok, job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
      enqueue_worker(job, track, url)
      {:ok, job}
    end
  end

  def get_job(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} ->
        case Repo.get(Music.DownloadJob, id) do
          nil -> {:error, :not_found}
          job -> {:ok, job}
        end
      :error ->
        {:error, :not_found}
    end
  end

  defp find_or_create_track(url) do
    case Repo.get_by(Music.Track, spotify_url: url) do
      nil -> Music.create_track(%{title: "Pending download", spotify_url: url})
      track -> {:ok, track}
    end
  end

  defp enqueue_worker(job, track, url) do
    %{track_id: track.id, spotify_url: url, quality: "320k", job_id: job.id}
    |> SoundForge.Jobs.DownloadWorker.new()
    |> Oban.insert()
  end
end
```

**Boundary rules**:
- Jobs context depends on Music context for all persistence
- Workers broadcast progress via PubSub -- they never push to WebSocket channels directly
- Controllers call Jobs context functions (e.g., `Jobs.Download.create_job/1`), not workers

---

### Audio Context (`SoundForge.Audio`)

The Audio context wraps Python interop through Erlang Ports. It provides two GenServer processes: `AnalyzerPort` for librosa-based feature extraction and `DemucsPort` for neural stem separation. These are infrastructure services, not domain entities -- they manage the OS-level process lifecycle, JSON protocol, and timeout handling.

**Modules**:
- `lib/sound_forge/audio/analyzer_port.ex` -- GenServer wrapping `priv/python/analyzer.py`
- `lib/sound_forge/audio/demucs_port.ex` -- GenServer wrapping `priv/python/demucs_runner.py`

**Public API**:

```elixir
# Analysis (2-minute timeout)
{:ok, results} = SoundForge.Audio.AnalyzerPort.analyze("/path/to/audio.mp3")
{:ok, results} = SoundForge.Audio.AnalyzerPort.analyze("/path/to/audio.mp3", ["tempo", "key"])
{:ok, results} = SoundForge.Audio.AnalyzerPort.analyze("/path/to/audio.mp3", ["all"])

# Stem separation (5-minute timeout)
{:ok, result} = SoundForge.Audio.DemucsPort.separate("/path/to/audio.mp3")
{:ok, result} = SoundForge.Audio.DemucsPort.separate("/path/to/audio.mp3",
  model: "htdemucs_ft",
  output_dir: "/custom/output",
  progress_callback: fn pct, msg -> IO.puts("#{pct}%: #{msg}") end
)
```

**Boundary rules**:
- Only Oban workers (or tests) call AnalyzerPort/DemucsPort directly
- These GenServers are NOT added to the supervision tree by default -- they are started on demand or supervised by workers
- The JSON protocol is an internal detail; callers receive Elixir maps

---

### Storage Context (`SoundForge.Storage`)

The Storage context manages the local filesystem layout for all persisted audio files. It provides a consistent interface for storing, retrieving, and cleaning up files across subdirectories.

**Module**: `lib/sound_forge/storage.ex`

**Directory layout**:

```
priv/uploads/
  downloads/     # Raw audio files from spotdl
  stems/         # Separated stem files from Demucs
  analysis/      # Analysis output artifacts
```

**Public API**:

```elixir
SoundForge.Storage.base_path()                           # => "priv/uploads"
SoundForge.Storage.downloads_path()                      # => "priv/uploads/downloads"
SoundForge.Storage.stems_path()                          # => "priv/uploads/stems"
SoundForge.Storage.analysis_path()                       # => "priv/uploads/analysis"

SoundForge.Storage.ensure_directories!()                 # Creates all dirs
SoundForge.Storage.store_file(src, "downloads", "a.mp3") # => {:ok, dest_path}
SoundForge.Storage.file_path("downloads", "a.mp3")       # => "priv/uploads/downloads/a.mp3"
SoundForge.Storage.file_exists?("downloads", "a.mp3")    # => true | false
SoundForge.Storage.delete_file("downloads", "a.mp3")     # => :ok | {:error, reason}
SoundForge.Storage.stats()                               # => %{file_count: 42, total_size_mb: 1.23}
```

**Boundary rules**:
- Workers and contexts call Storage for path resolution -- they never hardcode paths
- The base path is configurable via `Application.get_env(:sound_forge, :storage_path)`
- Cleanup operations will integrate with Music context to find orphaned files

---

## Service Orchestration: Spotify URL Flow

When a user submits a Spotify URL, the request flows through multiple context boundaries in a well-defined sequence:

```
User submits URL
      |
      v
[SoundForgeWeb.API.DownloadController]
      |  POST /api/download/track  {"url": "https://open.spotify.com/track/..."}
      |
      v
[SoundForge.Jobs.Download.create_job/1]       <-- Jobs Context
      |
      |-- find_or_create_track(url)            <-- Music Context (Repo lookup/insert)
      |-- Music.create_download_job(attrs)     <-- Music Context (job record)
      |-- enqueue_worker(job, track, url)       <-- Oban insertion
      |
      v
[Oban picks up job from :download queue]
      |
      v
[SoundForge.Jobs.DownloadWorker.perform/1]    <-- Jobs Context (worker)
      |
      |-- Music.get_download_job!(job_id)      <-- Music Context
      |-- Music.update_download_job(job, ...)  <-- Music Context
      |-- broadcast_progress(job_id, ...)      <-- PubSub
      |-- execute_download(spotify_url, ...)   <-- spotdl CLI (Storage)
      |-- Music.update_download_job(job, ...)  <-- Music Context (final state)
      |-- broadcast_progress(job_id, ...)      <-- PubSub
      |
      v
[Phoenix.PubSub "jobs:{job_id}" topic]
      |
      +----> [SoundForgeWeb.JobChannel]        <-- pushes to WebSocket client
      +----> [SoundForgeWeb.DashboardLive]     <-- updates LiveView assigns
```

The key observation is that no context reaches into another's internals. The DownloadWorker calls `Music.update_download_job/2` rather than building its own changeset. It broadcasts to PubSub rather than pushing directly to a channel. The controller calls `Jobs.Download.create_job/1` rather than inserting records and enqueuing workers itself.

---

## Transaction Boundaries

### Simple Transactions

Most operations use implicit single-row transactions through `Repo.insert/1` and `Repo.update/1`. These are sufficient when creating or updating a single record.

### Multi-step Transactions with Ecto.Multi

When a workflow must atomically modify multiple records, `Ecto.Multi` provides explicit transaction boundaries. This is the planned pattern for the download completion flow:

```elixir
defmodule SoundForge.Jobs.DownloadWorker do
  # Planned: atomic completion with track metadata update
  defp complete_download(job, track, output_path, file_size, metadata) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:job, DownloadJob.changeset(job, %{
      status: :completed,
      progress: 100,
      output_path: output_path,
      file_size: file_size
    }))
    |> Ecto.Multi.update(:track, Track.changeset(track, %{
      title: metadata["name"],
      artist: metadata["artists"] |> List.first() |> Map.get("name"),
      album: metadata["album"]["name"],
      duration: metadata["duration_ms"]
    }))
    |> Repo.transaction()
    |> case do
      {:ok, %{job: job, track: _track}} ->
        broadcast_progress(job.id, :completed, 100)
        :ok

      {:error, failed_operation, changeset, _changes} ->
        Logger.error("Transaction failed at #{failed_operation}: #{inspect(changeset.errors)}")
        {:error, "Transaction failed at #{failed_operation}"}
    end
  end
end
```

### Current Transaction Pattern

The existing `Jobs.Download.create_job/1` uses `with` chains with individual database calls. This means partial failure is possible -- a track could be created without its corresponding job. The planned migration to `Ecto.Multi` addresses this:

```elixir
# Planned: atomic job creation
def create_job(url) when is_binary(url) do
  Ecto.Multi.new()
  |> Ecto.Multi.run(:track, fn _repo, _changes ->
    case Repo.get_by(Music.Track, spotify_url: url) do
      nil -> Music.create_track(%{title: "Pending download", spotify_url: url})
      track -> {:ok, track}
    end
  end)
  |> Ecto.Multi.run(:job, fn _repo, %{track: track} ->
    Music.create_download_job(%{track_id: track.id, status: :queued})
  end)
  |> Ecto.Multi.run(:oban, fn _repo, %{job: job, track: track} ->
    %{track_id: track.id, spotify_url: url, quality: "320k", job_id: job.id}
    |> SoundForge.Jobs.DownloadWorker.new()
    |> Oban.insert()
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{job: job}} -> {:ok, job}
    {:error, _step, reason, _changes} -> {:error, reason}
  end
end
```

---

## Error Handling Patterns

### Tagged Tuples

Every public context function returns `{:ok, result}` or `{:error, reason}`. This is enforced by convention and typespecs:

```elixir
@spec create_job(String.t()) :: {:ok, map()} | {:error, term()}
@spec get_job(String.t()) :: {:ok, struct()} | {:error, :not_found}
@spec fetch_metadata(String.t()) :: {:ok, map()} | {:error, term()}
```

### Controller-Level Error Handling

Controllers use `Code.ensure_loaded?/1` with `try/rescue` as a defensive pattern for modules that may not yet be compiled or available:

```elixir
# From SoundForgeWeb.API.DownloadController
defp start_download_job(url) do
  if Code.ensure_loaded?(SoundForge.Jobs.Download) do
    SoundForge.Jobs.Download.create_job(url)
  else
    {:ok, %{id: generate_job_id(), status: "pending", url: url}}
  end
rescue
  UndefinedFunctionError ->
    {:ok, %{id: generate_job_id(), status: "pending", url: url}}
end
```

This pattern allows the web layer to operate with stub responses during incremental development, falling back gracefully when a context module is not yet implemented.

### LiveView Error Handling

LiveView modules use `try/rescue` to protect against database or context errors, ensuring the UI remains responsive even if a backing service is unavailable:

```elixir
# From SoundForgeWeb.DashboardLive
defp list_tracks do
  try do
    SoundForge.Music.list_tracks()
  rescue
    _ -> []
  end
end
```

### Oban Worker Retry

Workers return `{:error, reason}` to trigger Oban's built-in retry mechanism:

```elixir
use Oban.Worker,
  queue: :download,
  max_attempts: 3,
  priority: 1

def perform(%Oban.Job{args: args}) do
  case execute_download(args) do
    {:ok, _result} -> :ok          # Oban marks job as completed
    {:error, reason} ->
      broadcast_progress(job_id, :failed, 0)
      {:error, reason}             # Oban retries up to max_attempts
  end
end
```

### Port Error Handling

Erlang Port GenServers handle errors through exit status codes and JSON error parsing:

```elixir
# Non-zero exit status from Python process
def handle_info({port, {:exit_status, code}}, %{port: port, caller: caller, buffer: buffer} = state) do
  error = parse_error(buffer, code)
  GenServer.reply(caller, {:error, error})
  {:noreply, reset_state(state)}
end

defp parse_error(buffer, exit_code) do
  case Jason.decode(String.trim(buffer)) do
    {:ok, %{"error" => error_type, "message" => message}} ->
      {:error_from_script, error_type, message}
    {:ok, %{"error" => error}} ->
      {:error_from_script, error}
    _ ->
      {:exit_code, exit_code, String.trim(buffer)}
  end
end
```

---

## PubSub Event Patterns

Phoenix.PubSub is the sole mechanism for cross-context real-time communication. No context directly calls into another context's LiveView or Channel.

### Topics

| Topic Pattern | Publisher | Subscribers | Events |
|---------------|-----------|-------------|--------|
| `"tracks"` | Music context | DashboardLive | `{:track_added, track}` |
| `"jobs:{job_id}"` | DownloadWorker | JobChannel, DashboardLive | `{:job_progress, payload}`, `{:job_completed, payload}`, `{:job_failed, payload}` |

### Publishing Events

Workers broadcast progress updates using a consistent pattern:

```elixir
# From SoundForge.Jobs.DownloadWorker
defp broadcast_progress(job_id, status, progress) do
  Phoenix.PubSub.broadcast(
    SoundForge.PubSub,
    "jobs:#{job_id}",
    {:job_progress, %{job_id: job_id, status: status, progress: progress}}
  )
end
```

### Subscribing to Events

**WebSocket Channel** (for JavaScript clients):

```elixir
defmodule SoundForgeWeb.JobChannel do
  use SoundForgeWeb, :channel

  def join("jobs:" <> job_id, _payload, socket) do
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job_id}")
    {:ok, assign(socket, :job_id, job_id)}
  end

  def handle_info({:job_progress, payload}, socket) do
    push(socket, "job:progress", payload)
    {:noreply, socket}
  end
end
```

**LiveView** (for server-rendered UI):

```elixir
defmodule SoundForgeWeb.DashboardLive do
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "tracks")
    end
    {:ok, socket}
  end

  def handle_info({:track_added, track}, socket) do
    {:noreply, stream_insert(socket, :tracks, track, at: 0)}
  end

  def handle_info({:job_progress, payload}, socket) do
    jobs = Map.put(socket.assigns.active_jobs, payload.job_id, payload)
    {:noreply, assign(socket, :active_jobs, jobs)}
  end
end
```

### Event Flow Diagram

```
DownloadWorker.perform/1
    |
    |  Phoenix.PubSub.broadcast("jobs:abc123", {:job_progress, %{...}})
    |
    +-------> [PubSub "jobs:abc123" topic]
                   |
                   +---> JobChannel.handle_info/2 ---> push("job:progress", payload) ---> JS client
                   |
                   +---> DashboardLive.handle_info/2 ---> assign(:active_jobs, ...) ---> re-render
```

### Planned Events

| Topic | Event | Purpose |
|-------|-------|---------|
| `"tracks"` | `{:track_updated, track}` | Metadata updates after Spotify fetch |
| `"tracks"` | `{:track_deleted, track_id}` | Track removal propagation |
| `"jobs:{id}"` | `{:job_started, payload}` | Worker pickup notification |
| `"processing:{id}"` | `{:stem_ready, stem}` | Individual stem completion |
| `"analysis:{id}"` | `{:feature_extracted, feature}` | Incremental analysis results |
