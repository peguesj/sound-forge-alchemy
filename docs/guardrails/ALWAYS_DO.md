---
title: Always Do
nav_order: 1
parent: Guardrails
render_with_liquid: false
---
# ALWAYS DO -- Sound Forge Alchemy

These are mandatory practices for all code contributed to Sound Forge Alchemy. Every one of these has been chosen because the alternative caused bugs, data loss, or architectural drift in the Node.js/TypeScript predecessor or during early Elixir development.

---

## 1. Always use `binary_id` UUIDs for primary keys

Every Ecto schema in this project uses `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id`. This is already established in `Track`, `DownloadJob`, `ProcessingJob`, `AnalysisJob`, `Stem`, and `AnalysisResult`. New schemas must follow the same convention.

**Why**: UUIDs prevent enumeration attacks on API endpoints, allow client-side ID generation for optimistic UI updates, and are safe for distributed ID generation if the app scales horizontally.

```elixir
defmodule SoundForge.Music.NewSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "new_table" do
    # ...
    timestamps(type: :utc_datetime)
  end
end
```

---

## 2. Always validate job status transitions

Job schemas (`DownloadJob`, `ProcessingJob`, `AnalysisJob`) define explicit status enums via `Ecto.Enum`. Status transitions must be validated -- a job cannot go from `:completed` back to `:downloading`, and a `:failed` job cannot transition to `:completed` without re-queuing.

**Why**: Invalid state transitions mask bugs and confuse the UI. The Node.js version had race conditions where completed jobs would get overwritten by stale progress updates.

```elixir
@valid_transitions %{
  queued: [:downloading, :failed],
  downloading: [:processing, :completed, :failed],
  processing: [:completed, :failed],
  completed: [],
  failed: [:queued]
}

def validate_status_transition(changeset) do
  case Ecto.Changeset.get_change(changeset, :status) do
    nil -> changeset
    new_status ->
      current = Ecto.Changeset.get_field(changeset, :status)
      allowed = Map.get(@valid_transitions, current, [])
      if new_status in allowed do
        changeset
      else
        add_error(changeset, :status, "cannot transition from #{current} to #{new_status}")
      end
  end
end
```

---

## 3. Always broadcast progress via PubSub

Every job state change must be followed by a `Phoenix.PubSub.broadcast/3` call on the `"jobs:#{job_id}"` topic. LiveView processes subscribe to these topics to push real-time updates to the client. No broadcast means no UI update.

```elixir
defp broadcast_progress(job_id, status, progress) do
  Phoenix.PubSub.broadcast(
    SoundForge.PubSub,
    "jobs:#{job_id}",
    {:job_progress, %{job_id: job_id, status: status, progress: progress}}
  )
end
```

---

## 4. Always use Oban for background processing

Every operation that involves external I/O (HTTP requests, file downloads, Python Port calls, filesystem operations on large files) must be dispatched through an Oban worker. The queues are configured in `config/config.exs`:

- `download: 3` -- audio file downloads (spotdl)
- `processing: 2` -- stem separation (demucs)
- `analysis: 2` -- audio feature extraction (librosa)

**Why**: Oban provides persistence (jobs survive restarts), retries with backoff, concurrency limits, uniqueness constraints, telemetry, and observability through Oban Web.

---

## 5. Always use Req for HTTP requests

The project depends on `{:req, "~> 0.5"}`. All HTTP requests must use `Req`. Do not add HTTPoison, Tesla, Hackney, or :httpc as dependencies. The `SoundForge.Spotify.HTTPClient` module already demonstrates the correct pattern.

**Why**: Req is the Phoenix-recommended HTTP client, already included in the project, and provides a clean API with built-in JSON decoding, retry, and redirect following.

```elixir
# Correct
Req.get("https://api.spotify.com/v1/tracks/#{id}",
  headers: [{"Authorization", "Bearer #{token}"}]
)

# Wrong: Do not use these
HTTPoison.get(url)
Tesla.get(url)
:httpc.request(url)
```

---

## 6. Always use streams for LiveView collections

All lists of tracks, jobs, stems, or any collection rendered in a LiveView template must use `stream/3` and `stream_insert/3`, never raw assigns of lists. The parent element must have `phx-update="stream"` and each child must use the stream-provided DOM id.

**Why**: Raw list assigns cause the full list to be re-serialized and diffed on every update. With hundreds of tracks, this causes memory bloat and slow renders. Streams send only the changed items.

```elixir
# In mount/3
socket = stream(socket, :tracks, Music.list_tracks())

# In template
<div id="tracks" phx-update="stream">
  <div :for={{id, track} <- @streams.tracks} id={id}>
    {track.title}
  </div>
</div>
```

---

## 7. Always handle Port crashes gracefully

The `AnalyzerPort` and `DemucsPort` GenServers communicate with Python processes via Erlang Ports. Python processes can crash (segfault in native libs, out of memory, corrupt audio input). The GenServer must handle `{port, {:exit_status, code}}` for non-zero codes, log the failure with context, and reply to the caller with a meaningful error.

**Why**: An unhandled Port crash will crash the GenServer, which will crash the supervisor, which may cascade. Graceful error handling keeps the system running and provides diagnostic information.

```elixir
@impl true
def handle_info({port, {:exit_status, code}}, %{port: port, caller: caller, buffer: buffer} = state)
    when code != 0 do
  error = parse_error(buffer, code)
  Logger.error("Analyzer port exited with code #{code}: #{inspect(error)}")
  GenServer.reply(caller, {:error, error})
  {:noreply, reset_state(state)}
end
```

---

## 8. Always clean up files on job failure

When an Oban worker fails after creating files on disk (partial downloads, temp files, intermediate processing artifacts), the error handling path must delete those files. Use `File.rm/1` for single files and `File.rm_rf/1` for directories.

```elixir
case execute_download(spotify_url, quality, track_id) do
  {:ok, result} ->
    :ok

  {:error, reason} ->
    # Clean up partial download
    output_path = SoundForge.Storage.file_path("downloads", "#{track_id}.mp3")
    File.rm(output_path)
    {:error, reason}
end
```

---

## 9. Always use `Ecto.Multi` for multi-step operations

When a single user action requires multiple database writes (e.g., creating a track and its associated download job, or completing a job and creating an analysis result), wrap the operations in an `Ecto.Multi` transaction. This ensures atomicity -- either all writes succeed or none do.

**Why**: Without `Multi`, a crash between the first and second write leaves the database in an inconsistent state. The Node.js version had orphaned job records because track creation succeeded but job creation failed.

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:track, Track.changeset(%Track{}, track_attrs))
|> Ecto.Multi.insert(:download_job, fn %{track: track} ->
  DownloadJob.changeset(%DownloadJob{}, %{track_id: track.id})
end)
|> Repo.transaction()
```

---

## 10. Always test with Mox for external services

The project includes `{:mox, "~> 1.0", only: :test}` and defines the `SoundForge.Spotify.Client` behaviour. All tests that touch external services (Spotify API, spotdl, Python Ports) must use Mox to define expectations rather than making real network calls.

**Why**: Tests that hit real APIs are slow, flaky, rate-limited, and require credentials in CI. Mox enforces that mocks follow the behaviour contract, preventing mock drift.

```elixir
# In test/support/mocks.ex
Mox.defmock(SoundForge.Spotify.MockClient, for: SoundForge.Spotify.Client)

# In test
expect(SoundForge.Spotify.MockClient, :fetch_track, fn id ->
  {:ok, %{"name" => "Test Song", "artists" => [%{"name" => "Test Artist"}]}}
end)
```

---

## 11. Always use ETS for short-lived caches (tokens)

Spotify access tokens (3600-second TTL) and similar short-lived credentials must be cached in ETS tables, not in GenServer state, not in the database, and not in Redis. The `SoundForge.Spotify.HTTPClient` module demonstrates the correct pattern with `:spotify_tokens`.

**Why**: ETS provides concurrent read access without bottlenecking on a single GenServer process. Token lookups happen on every Spotify API call -- they must be fast. ETS tables survive individual process crashes (owned by the application supervisor).

```elixir
:ets.new(:spotify_tokens, [:named_table, :public, :set])
:ets.insert(:spotify_tokens, {:access_token, token, expires_at})

case :ets.lookup(:spotify_tokens, :access_token) do
  [{:access_token, token, expires_at}] when expires_at > now -> {:ok, token}
  _ -> fetch_new_token()
end
```

---

## 12. Always log job failures with context

When an Oban worker fails, the log message must include the job ID, the track ID (if applicable), the queue name, the attempt number, and the error reason. Use structured Logger metadata when possible.

**Why**: "Job failed" is useless in production logs. "Download job abc123 for track def456 failed on attempt 2/3: spotdl exited with code 1: network timeout" is actionable.

```elixir
Logger.error(
  "Download failed",
  job_id: job.id,
  track_id: track_id,
  queue: :download,
  attempt: job.attempt,
  max_attempts: job.max_attempts,
  error: inspect(reason)
)
```

---

## 13. Always use `start_supervised!/1` in tests

Every process started in a test (GenServers, Ports, Oban workers under test) must be started with `start_supervised!/1`. This ensures the process is properly terminated between tests, preventing test pollution and port leaks.

**Why**: Processes started with `start_link` inside a test survive into the next test if the test process does not exit cleanly. This causes flaky tests, port exhaustion, and ETS table conflicts.

```elixir
test "analyzer returns tempo" do
  start_supervised!(SoundForge.Audio.AnalyzerPort)
  # test code...
end
```

---

## 14. Always validate Spotify URLs before processing

Before creating a download job or fetching metadata, validate that the provided URL matches Spotify's URL format. The `SoundForge.Spotify.URLParser` module handles this. Reject URLs that do not match `open.spotify.com/track/`, `open.spotify.com/album/`, or `open.spotify.com/playlist/` patterns.

**Why**: Passing arbitrary URLs to spotdl or the Spotify API wastes resources, creates confusing error messages, and could be a vector for SSRF if URLs are fetched server-side.

```elixir
case SoundForge.Spotify.URLParser.parse(url) do
  {:ok, %{type: :track, id: spotify_id}} ->
    # Proceed with download/metadata fetch
  {:error, :invalid_url} ->
    {:error, "Invalid Spotify URL. Expected format: https://open.spotify.com/track/..."}
end
```

---

## 15. Always use `ilike` for case-insensitive search

All text search queries against track titles, artist names, album names, or any user-facing text field must use `ilike` (case-insensitive LIKE) rather than `like`. The `SoundForge.Music.search_tracks/1` function demonstrates the correct pattern.

**Why**: Users search for "beatles" and expect to find "The Beatles". Case-sensitive search produces confusing empty results. PostgreSQL's `ilike` handles this correctly with no additional dependencies.

```elixir
def search_tracks(query) when is_binary(query) and query != "" do
  pattern = "%#{query}%"

  Track
  |> where([t], ilike(t.title, ^pattern) or ilike(t.artist, ^pattern))
  |> Repo.all()
end
```
