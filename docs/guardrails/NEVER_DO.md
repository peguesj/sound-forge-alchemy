# NEVER DO -- Sound Forge Alchemy

These prohibitions are absolute. Violating any of these will cause data loss, race conditions, blocked processes, or security vulnerabilities in the Sound Forge Alchemy audio processing pipeline.

---

## 1. Never use GenServers to hold domain entity state

**The database is the single source of truth for tracks, jobs, stems, and analysis results.**

GenServers are appropriate for managing Erlang Ports (`AnalyzerPort`, `DemucsPort`) and short-lived process coordination. They are never appropriate for representing a track, a download job, or any other domain entity. All domain state lives in PostgreSQL via Ecto schemas (`SoundForge.Music.Track`, `SoundForge.Music.DownloadJob`, etc.). If you need to query or mutate domain state, go through the `SoundForge.Music` context and `SoundForge.Repo`.

**Why**: GenServer state is volatile (lost on crash), cannot be queried, and creates single-process bottlenecks. Oban already depends on database-backed job state for retry, uniqueness, and persistence guarantees.

```elixir
# WRONG: Holding track state in a GenServer
defmodule TrackManager do
  use GenServer
  def init(_), do: {:ok, %{tracks: %{}}}
  def handle_call({:add_track, track}, _, state), do: ...
end

# RIGHT: Use Ecto and the Music context
SoundForge.Music.create_track(%{title: "Song", artist: "Artist"})
```

---

## 2. Never block the request path with Python Port calls

**All Python Port interactions (librosa analysis, demucs stem separation) MUST go through Oban workers.**

A Port call to Python for audio analysis or stem separation can take 30 seconds to several minutes. Blocking a LiveView process or controller action on a Port call will freeze the user's UI and exhaust the endpoint's acceptor pool under load.

**Why**: Phoenix processes handle user connections. If they block on Port calls, the entire application becomes unresponsive. Oban workers run in their own processes with timeouts, retries, and backpressure.

```elixir
# WRONG: Calling AnalyzerPort from a LiveView handle_event
def handle_event("analyze", _, socket) do
  {:ok, results} = SoundForge.Audio.AnalyzerPort.analyze(path, features)
  {:noreply, assign(socket, :results, results)}
end

# RIGHT: Enqueue an Oban job, receive results via PubSub
def handle_event("analyze", _, socket) do
  {:ok, job} = Music.create_analysis_job(%{track_id: track_id})
  %{track_id: track_id, job_id: job.id, features: features}
  |> SoundForge.Jobs.Analysis.new()
  |> Oban.insert()
  {:noreply, assign(socket, :analysis_status, :queued)}
end
```

---

## 3. Never store audio files in the database

**Audio files (MP3, WAV, FLAC, stems) belong on the filesystem via `SoundForge.Storage`.**

Audio files range from 3 MB to 500 MB. Storing them as binary blobs in PostgreSQL destroys database performance, bloats WAL logs, makes backups unusable, and prevents streaming playback.

**Why**: PostgreSQL is not a file server. The `SoundForge.Storage` module provides structured filesystem storage with `priv/uploads/` as the sandboxed root, with subdirectories for downloads, stems, and analysis artifacts.

```elixir
# WRONG: Storing audio in the database
field :audio_data, :binary

# RIGHT: Store the path reference, file lives on disk
field :output_path, :string  # e.g., "downloads/abc123.mp3"
```

---

## 4. Never hardcode Spotify credentials

**Spotify `client_id` and `client_secret` MUST come from `config/runtime.exs` via environment variables.**

The project already reads these from `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET` in `config/runtime.exs`. Hardcoding credentials in source code, compile-time config, or test fixtures will leak secrets into version control and prevent per-environment configuration.

**Why**: Credentials are environment-specific and secret. The `SoundForge.Spotify.HTTPClient` module reads them via `Application.get_env(:sound_forge, :spotify)` at runtime, which is the only correct approach.

```elixir
# WRONG: Hardcoded anywhere
@client_id "abc123deadbeef"

# WRONG: In config/config.exs (compile-time, committed to git)
config :sound_forge, :spotify, client_id: "abc123deadbeef"

# RIGHT: In config/runtime.exs reading from environment
config :sound_forge, :spotify,
  client_id: System.get_env("SPOTIFY_CLIENT_ID"),
  client_secret: System.get_env("SPOTIFY_CLIENT_SECRET")
```

---

## 5. Never skip Oban for external calls

**All HTTP requests to external services (Spotify API, spotdl downloads, any third-party API) MUST run inside Oban workers.**

External calls are inherently unreliable: networks fail, APIs rate-limit, services go down. Calling them directly from LiveView processes or controller actions means failures crash the user's session with no retry, no logging, and no recovery.

**Why**: Oban provides automatic retries with backoff, uniqueness constraints (preventing duplicate downloads), max attempt limits, dead-letter inspection via Oban Web, and persistent job history. The queues are already configured: `download: 3, processing: 2, analysis: 2`.

```elixir
# WRONG: Direct HTTP call from a controller
def create(conn, %{"url" => url}) do
  {:ok, data} = Req.get(url)
  json(conn, data)
end

# RIGHT: Enqueue an Oban job
def create(conn, %{"url" => url}) do
  %{url: url, job_id: job_id}
  |> SoundForge.Jobs.Download.new()
  |> Oban.insert()
  json(conn, %{job_id: job_id, status: "queued"})
end
```

---

## 6. Never use synchronous Port calls for long-running operations

**Port calls that take more than 5 seconds MUST be wrapped in an Oban worker with progress reporting.**

Audio analysis via librosa can take 30-120 seconds. Stem separation via demucs can take 2-10 minutes. A synchronous `GenServer.call/3` with a 2-minute timeout still blocks the calling process and provides no progress visibility to the user.

**Why**: Long-running synchronous calls tie up BEAM processes, provide no user feedback, and make timeout tuning fragile. Oban workers with PubSub broadcasting give the user real-time progress updates through LiveView.

```elixir
# WRONG: Synchronous call with long timeout
{:ok, result} = GenServer.call(AnalyzerPort, {:analyze, path}, 300_000)

# RIGHT: Oban worker calls the Port, broadcasts progress
defmodule SoundForge.Jobs.Analysis do
  use Oban.Worker, queue: :analysis, max_attempts: 3

  def perform(%Oban.Job{args: args}) do
    broadcast_progress(args["job_id"], :analyzing, 10)
    {:ok, results} = SoundForge.Audio.AnalyzerPort.analyze(args["path"], args["features"])
    broadcast_progress(args["job_id"], :completed, 100)
    :ok
  end
end
```

---

## 7. Never trust user-provided file paths

**All file operations MUST be sandboxed to `priv/uploads/` (or the configured `SoundForge.Storage.base_path/0`).**

Users can submit Spotify URLs that result in filenames, and API endpoints accept file references. Path traversal attacks (`../../etc/passwd`) or absolute paths (`/tmp/malicious`) must never reach `File.read/1`, `File.write/2`, or `File.rm/1`.

**Why**: Unsandboxed file paths allow arbitrary file read/write/delete on the server. Always construct paths through `SoundForge.Storage.file_path/2` and validate that the resolved path is within the storage root.

```elixir
# WRONG: Using user input directly
def download(conn, %{"filename" => filename}) do
  path = "/some/dir/#{filename}"
  send_download(conn, {:file, path})
end

# RIGHT: Validate and sandbox through Storage
def download(conn, %{"filename" => filename}) do
  sanitized = Path.basename(filename)  # Strip directory traversal
  path = SoundForge.Storage.file_path("downloads", sanitized)

  if File.exists?(path) do
    send_download(conn, {:file, path})
  else
    send_resp(conn, 404, "Not found")
  end
end
```

---

## 8. Never skip PubSub broadcasting after job state changes

**Every job status transition (queued -> downloading -> completed/failed) MUST broadcast via `Phoenix.PubSub`.**

The LiveView frontend subscribes to `"jobs:#{job_id}"` topics to display real-time progress. If a worker updates the database but does not broadcast, the user sees a stale UI with no indication that their job is progressing, completed, or failed.

**Why**: LiveView has no polling mechanism for job state. PubSub is the only channel for pushing updates to the client. Without broadcasts, the UI is broken.

```elixir
# WRONG: Update DB, forget to broadcast
Music.update_download_job(job, %{status: :completed, progress: 100})

# RIGHT: Always broadcast after state change
Music.update_download_job(job, %{status: :completed, progress: 100})
Phoenix.PubSub.broadcast(
  SoundForge.PubSub,
  "jobs:#{job.id}",
  {:job_progress, %{job_id: job.id, status: :completed, progress: 100}}
)
```

---

## 9. Never leave orphaned files when jobs fail

**If a job fails after creating files on disk, the failure handler MUST clean up those files.**

A download worker that fetches 200 MB of audio and then fails during post-processing will leave a 200 MB orphan on disk. Over time, this fills the disk and creates confusion about which files are valid.

**Why**: Disk space is finite. Orphaned files have no database reference, so `SoundForge.Storage.cleanup_orphaned/0` cannot find them unless they follow naming conventions. Proactive cleanup in error handlers is the first line of defense.

```elixir
# WRONG: Let the file sit there on failure
def perform(%Oban.Job{args: %{"track_id" => track_id}} = job) do
  output_path = download_file(track_id)
  process_file(output_path)  # If this crashes, orphan remains
end

# RIGHT: Clean up on failure
def perform(%Oban.Job{args: %{"track_id" => track_id}} = job) do
  output_path = download_file(track_id)
  case process_file(output_path) do
    {:ok, result} -> :ok
    {:error, reason} ->
      File.rm(output_path)
      {:error, reason}
  end
end
```

---

## 10. Never use floats for progress percentages

**Job progress MUST be an integer in the range 0-100. Never use floats.**

The `DownloadJob` schema validates `progress` as an integer with `validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)`. Floating point comparisons are unreliable, JSON serialization of floats is inconsistent across clients, and the UI displays whole percentages.

**Why**: `0.1 + 0.2 != 0.3` in IEEE 754. Progress bars do not need sub-percent precision. Integer math is exact, database storage is smaller, and Ecto validation is straightforward.

```elixir
# WRONG: Float progress
broadcast_progress(job_id, :downloading, 33.333333)

# WRONG: Progress outside 0-100
broadcast_progress(job_id, :downloading, 150)

# RIGHT: Integer 0-100
broadcast_progress(job_id, :downloading, 33)
```
