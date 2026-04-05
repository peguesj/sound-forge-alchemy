# Import Pipeline Runbook

**Application**: Sound Forge Alchemy (SFA)
**Stack**: Elixir / Phoenix / Oban
**Last reviewed**: 2026-03-30

---

## 1. Overview

The import pipeline converts a Spotify track URL into a locally stored audio file with full metadata, analysis, and optional stems. It runs as a chain of Oban background jobs.

Stages in order:
```
1. Spotify Metadata Fetch   — resolve track ID, pull title/artist/album from Spotify API
2. SpotDL Download          — download audio via spotdl (wraps yt-dlp)
3. Audio Analysis           — Python analyzer extracts BPM, key, MFCC, chroma, spectral features
4. Stem Separation          — optional; Demucs (local) or lalal.ai (cloud)
```

---

## 2. Architecture

### Oban Workers

| Worker Module | Queue | Max Attempts | Purpose |
|---|---|---|---|
| `SoundForge.Workers.SpotifyMetadata` | `metadata` | 3 | Fetch track metadata from Spotify API |
| `SoundForge.Workers.TrackDownload` | `downloads` | 3 | Run spotdl, store audio file |
| `SoundForge.Workers.AudioAnalysis` | `analysis` | 3 | Run Python analyzer, store features |
| `SoundForge.Workers.StemSeparation` | `stems` | 2 | Run Demucs or lalal.ai |

### Job Flow

```
User submits Spotify URL
        ↓
SpotifyMetadata (metadata queue)
        ↓ success
TrackDownload (downloads queue)
        ↓ success
AudioAnalysis (analysis queue)
        ↓ success (if stems enabled)
StemSeparation (stems queue)
```

---

## 3. Starting a Manual Import

### Via IEx

```elixir
# Insert a single track
%{spotify_url: "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"}
|> SoundForge.Workers.SpotifyMetadata.new()
|> Oban.insert()

# Re-run a specific stage for an existing track
%{track_id: 123}
|> SoundForge.Workers.AudioAnalysis.new()
|> Oban.insert()
```

### Via HTTP API

```bash
curl -X POST http://localhost:4000/api/tracks/import \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"spotify_url": "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh"}'
```

---

## 4. Monitoring

### IEx Queries

```elixir
import Ecto.Query
alias Oban.Job

# Jobs currently executing
SoundForge.Repo.all(from j in Job, where: j.state == "executing")

# Discarded jobs in the last 24 hours
SoundForge.Repo.all(from j in Job,
  where: j.state == "discarded" and j.inserted_at > ago(24, "hour"),
  order_by: [desc: j.inserted_at]
)
```

### Log Lines to Watch

```bash
tail -f /var/log/sfa/app.log | grep -E "(TrackDownload|SpotifyMetadata|AudioAnalysis|spotdl|ERROR)"
```

Key patterns:
- `[info] Track downloaded: /files/tracks/` — SpotDL completed
- `[info] Analysis complete` — Python analyzer finished
- `[error] spotdl exited with code 1` — download failure
- `[error] Spotify token expired` — auth refresh needed
- `[error] Job discarded after N attempts` — needs manual action

---

## 5. Common Failures

### SpotDL Not Found / Python Environment Missing

```bash
which spotdl
# If missing:
pip install spotdl
```

Ensure the Phoenix process inherits the PATH that includes the Python bin directory. If using systemd, set `Environment=PATH=...` in the unit file.

### Spotify Auth Expired

1. Check credentials: `echo $SPOTIFY_CLIENT_ID`
2. Force refresh from IEx: `SoundForge.Spotify.refresh_token()`
3. If refresh token is dead: reconnect Spotify in Settings UI.

### Disk Space Exhausted

```bash
df -h /
du -sh /var/lib/sfa/files/tracks/
find /tmp -name "spotdl-*" -mtime +1 -delete
```

### Job Stuck in "Executing" State

```elixir
Oban.rescue_stale_jobs(:all)
# or cancel and re-enqueue a specific job:
Oban.cancel_job(job_id)
%{track_id: track_id} |> SoundForge.Workers.SpotifyMetadata.new() |> Oban.insert()
```

---

## 6. Recovery Procedures

```elixir
# Retry all discarded jobs in a queue
Oban.retry_all_jobs(queue: :downloads, state: :discarded)

# Retry all discarded jobs
Oban.retry_all_jobs(state: :discarded)

# Retry a single job
Oban.retry_job(job_id)

# Pause a queue
Oban.pause_queue(:downloads)
Oban.resume_queue(:downloads)
```

---

## 7. Configuration

| Variable | Required | Description |
|---|---|---|
| `SPOTIFY_CLIENT_ID` | Yes | Spotify app client ID |
| `SPOTIFY_CLIENT_SECRET` | Yes | Spotify app client secret |
| `LALALAI_API_KEY` | No | lalal.ai API key for cloud stem separation |
| `STORAGE_PATH` | No | Base directory for audio files (default: `priv/static/files`) |
| `PYTHON_EXECUTABLE` | No | Path to Python 3 binary (default: `python3`) |
| `SPOTDL_PATH` | No | Full path to spotdl binary if not on PATH |
