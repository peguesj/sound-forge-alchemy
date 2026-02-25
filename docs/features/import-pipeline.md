---
title: Import Pipeline
parent: Features
nav_order: 1
---

[Home](../index.md) > [Features](index.md) > Import Pipeline

# Import Pipeline

Spotify URL import, metadata retrieval, and audio download.

## Table of Contents

- [Overview](#overview)
- [Supported URL Formats](#supported-url-formats)
- [Pipeline Stages](#pipeline-stages)
- [Metadata Fetch](#metadata-fetch)
- [Audio Download](#audio-download)
- [Real-Time Progress](#real-time-progress)
- [Error Handling](#error-handling)
- [Storage Layout](#storage-layout)

---

## Overview

The import pipeline accepts a Spotify URL, fetches track metadata via the Spotify Web API, and downloads the audio using `spotdl`. The entire pipeline runs in the background via Oban workers, with real-time progress updates pushed to the LiveView dashboard via Phoenix PubSub.

```
User pastes URL
      |
 URL Parsing (SoundForge.Spotify.URLParser)
      |
 Metadata Fetch (Spotify Web API via OAuth2)
      |
 Track created in PostgreSQL
      |
 Download Job enqueued (Oban :download queue, concurrency: 3)
      |
 DownloadWorker → spotdl CLI → audio file
      |
 Track updated: output_path, file_size
      |
 PubSub broadcast → LiveView update
```

---

## Supported URL Formats

The URL parser (`SoundForge.Spotify.URLParser`) handles all standard Spotify URL forms:

| Format | Example |
|--------|---------|
| Track | `https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC` |
| Album | `https://open.spotify.com/album/6dVIqQ8qmQ5GBnJ9shOYGE` |
| Playlist | `https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M` |
| International locale | `https://open.spotify.com/intl-es/track/4uLU6hMCjMI75M1A2tKUQC` |
| Short Spotify URL | `https://spotify.com/track/4uLU6hMCjMI75M1A2tKUQC` |
| Spotify URI | `spotify:track:4uLU6hMCjMI75M1A2tKUQC` |

The parser returns `{:ok, %{type: "track" | "album" | "playlist", id: "..."}}` or `{:error, :invalid_url}`.

---

## Pipeline Stages

### Stage 1: URL Parsing

```elixir
SoundForge.Spotify.URLParser.parse(url)
# {:ok, %{type: "track", id: "4uLU6hMCjMI75M1A2tKUQC"}}
```

### Stage 2: Metadata Fetch

```elixir
SoundForge.Spotify.fetch_metadata(url)
# {:ok, %{
#   title: "Blinding Lights",
#   artist: "The Weeknd",
#   album: "After Hours",
#   album_art_url: "https://...",
#   duration: 200,
#   spotify_id: "0VjIjW4GlUZAMYd2vXMi3b",
#   spotify_url: "https://..."
# }}
```

For albums and playlists, the metadata fetch returns a list of tracks.

### Stage 3: Track Creation

A `Track` record is inserted into PostgreSQL. The `spotify_id` field has a unique constraint — importing the same track twice returns the existing record.

### Stage 4: Download Job

A `DownloadJob` is created and enqueued to Oban's `:download` queue (concurrency: 3):

```elixir
Jobs.Download.create_job(spotify_url)
# Creates DownloadJob record + inserts Oban job
```

### Stage 5: DownloadWorker Execution

The worker:
1. Updates status to `:downloading` and broadcasts `0%` progress
2. Runs `spotdl` CLI with the Spotify URL
3. Updates status to `:completed` with `output_path` and `file_size`
4. Broadcasts `100%` completion

On failure, sets status to `:failed` with an error message. Oban retries up to 3 times with exponential backoff.

---

## Metadata Fetch

**Module:** `SoundForge.Spotify.HTTPClient`

Uses OAuth2 client credentials flow (no user account needed for metadata):

1. Requests access token from `https://accounts.spotify.com/api/token`
2. Token cached in ETS for 3500s (Spotify tokens expire at 3600s)
3. Track metadata fetched from `https://api.spotify.com/v1/tracks/{id}`
4. Album tracks from `https://api.spotify.com/v1/albums/{id}/tracks`
5. Playlist tracks from `https://api.spotify.com/v1/playlists/{id}/tracks`

The client uses a **behaviour-based architecture** for testability:

```elixir
# Production
config :sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient

# Tests
config :sound_forge, :spotify_client, SoundForge.Spotify.MockClient
```

### Spotify OAuth (User Account)

For playback via Spotify (not just metadata), users can connect their Spotify account via the Settings page. The OAuth flow:

1. `GET /auth/spotify` — redirects to Spotify authorization
2. Spotify redirects to `GET /auth/spotify/callback` with authorization code
3. Code exchanged for access + refresh tokens (stored encrypted)
4. Tokens refreshed automatically before expiry

---

## Audio Download

**Tool:** `spotdl` (Python CLI)

`spotdl` downloads audio from YouTube (using Spotify metadata for matching), then applies Spotify metadata (title, artist, album art) to the file.

Supported audio quality (configurable per user):

| Quality | Format | Bitrate |
|---------|--------|---------|
| `lossless` | FLAC | Lossless |
| `high` (default) | MP3/AAC | 320kbps |
| `medium` | MP3 | 192kbps |
| `low` | MP3 | 128kbps |

### Download Worker Configuration

```elixir
# lib/sound_forge/jobs/download_worker.ex
use Oban.Worker,
  queue: :download,
  max_attempts: 3,
  priority: 1
```

---

## Real-Time Progress

Progress updates are broadcast via `Phoenix.PubSub` to the `"jobs:{job_id}"` topic:

```elixir
PubSub.broadcast(SoundForge.PubSub, "jobs:#{job_id}", {:job_progress, %{
  status: :downloading,
  progress: 45,
  message: "Downloading audio..."
}})
```

DashboardLive subscribes and updates the `JobProgress` component in real time.

---

## Error Handling

| Error | Behavior |
|-------|---------|
| Invalid URL | Immediate error — no job created |
| Spotify API auth failure | Error returned to UI — check credentials |
| Track not available | `spotdl` error captured, job marked `:failed` |
| Network timeout | Oban retries up to 3 times (exponential backoff) |
| spotdl not found | Job marked `:failed` with "spotdl not found" message |
| Disk full | Job marked `:failed`, error logged |

---

## Storage Layout

Downloaded files are stored under `priv/uploads/`:

```
priv/uploads/
  downloads/
    {track_id}/
      {artist} - {title}.mp3
```

The `output_path` column on `DownloadJob` stores the absolute path. The `FileController` serves files from this directory via `GET /files/*path`.

---

## See Also

- [Stem Separation](stem-separation.md)
- [Audio Analysis](analysis.md)
- [API: Download Endpoints](../api/rest.md#download)
- [Configuration: Spotify credentials](../guides/configuration.md)

---

[← Features Index](index.md) | [Next: Stem Separation →](stem-separation.md)
