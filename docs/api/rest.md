---
title: REST Endpoints
parent: API Reference
nav_order: 1
---

[Home](../index.md) > [API Reference](index.md) > REST Endpoints

# REST Endpoint Reference

## Table of Contents

- [Health](#health)
- [Spotify](#spotify)
- [Download](#download)
- [Processing](#processing)
- [Analysis](#analysis)
- [DAW](#daw)
- [lalal.ai Management](#lalalai-management)
- [Export](#export)
- [File Serving](#file-serving)
- [Auth Routes](#auth-routes)

---

## Health

### `GET /health`

Public endpoint. No authentication required.

**Response:**
```json
{"status": "ok"}
```

---

## Spotify

### `POST /api/spotify/fetch`

Fetch track metadata from Spotify. Accepts track, album, or playlist URLs.

**Auth:** Bearer token required
**Rate limit:** 60/min

**Request:**
```json
{
  "url": "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
}
```

**Response:**
```json
{
  "data": {
    "type": "track",
    "track": {
      "id": "uuid",
      "spotify_id": "4uLU6hMCjMI75M1A2tKUQC",
      "title": "Blinding Lights",
      "artist": "The Weeknd",
      "album": "After Hours",
      "album_art_url": "https://...",
      "duration": 200,
      "spotify_url": "https://..."
    }
  }
}
```

For albums/playlists, `data.type` is `"album"` or `"playlist"` and `data.tracks` is an array.

**Errors:**

| Code | Description |
|------|-------------|
| `invalid_url` | URL could not be parsed as a Spotify URL |
| `spotify_error` | Spotify API returned an error |
| `unauthorized` | Spotify credentials not configured |

---

## Download

### `POST /api/download/track`

Enqueue an audio download job.

**Auth:** Bearer token required
**Rate limit:** 10/min (heavy)

**Request:**
```json
{
  "url": "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
  "quality": "high"
}
```

`quality` options: `"lossless"`, `"high"` (default), `"medium"`, `"low"`

**Response:**
```json
{
  "data": {
    "job_id": "uuid",
    "track_id": "uuid",
    "status": "queued"
  }
}
```

### `GET /api/download/job/:id`

Get download job status.

**Auth:** Bearer token required

**Response:**
```json
{
  "data": {
    "id": "uuid",
    "status": "downloading",
    "progress": 45,
    "output_path": null,
    "file_size": null,
    "error": null
  }
}
```

`status` values: `"queued"`, `"downloading"`, `"processing"`, `"completed"`, `"failed"`

---

## Processing

### `POST /api/processing/separate`

Enqueue a stem separation job.

**Auth:** Bearer token required
**Rate limit:** 10/min (heavy)

**Request:**
```json
{
  "track_id": "uuid",
  "model": "htdemucs",
  "engine": "local"
}
```

`model` options: `"htdemucs"` (default), `"htdemucs_ft"`, `"htdemucs_6s"`, `"mdx_extra"`
`engine` options: `"local"` (Demucs), `"lalalai"`

**Response:**
```json
{
  "data": {
    "job_id": "uuid",
    "track_id": "uuid",
    "model": "htdemucs",
    "status": "queued"
  }
}
```

### `GET /api/processing/job/:id`

Get processing job status.

**Response:**
```json
{
  "data": {
    "id": "uuid",
    "status": "processing",
    "progress": 60,
    "model": "htdemucs",
    "stems": [],
    "error": null
  }
}
```

When `status` is `"completed"`, `stems` contains the list of stem records.

### `GET /api/processing/models`

List available Demucs models.

**Response:**
```json
{
  "data": {
    "models": [
      {
        "name": "htdemucs",
        "description": "Hybrid Transformer Demucs - default 4-stem model",
        "stems": 4
      },
      {
        "name": "htdemucs_ft",
        "description": "Fine-tuned Hybrid Transformer Demucs - higher quality, slower",
        "stems": 4
      },
      {
        "name": "htdemucs_6s",
        "description": "6-stem model (vocals, drums, bass, guitar, piano, other)",
        "stems": 6
      },
      {
        "name": "mdx_extra",
        "description": "MDX-Net Extra - alternative architecture, good for vocals",
        "stems": 4
      }
    ]
  }
}
```

---

## Analysis

### `POST /api/analysis/analyze`

Enqueue an audio analysis job.

**Auth:** Bearer token required
**Rate limit:** 10/min (heavy)

**Request:**
```json
{
  "track_id": "uuid",
  "features": ["tempo", "key", "energy", "spectral", "mfcc", "chroma"]
}
```

`features` options: `"tempo"`, `"key"`, `"energy"`, `"spectral"`, `"mfcc"`, `"chroma"`, `"all"`

**Response:**
```json
{
  "data": {
    "job_id": "uuid",
    "track_id": "uuid",
    "status": "queued"
  }
}
```

### `GET /api/analysis/job/:id`

Get analysis job status.

**Response:**
```json
{
  "data": {
    "id": "uuid",
    "status": "completed",
    "progress": 100,
    "result": {
      "tempo": 128.0,
      "key": "A minor",
      "energy": 0.74,
      "spectral_centroid": 1823.4,
      "spectral_rolloff": 4200.1,
      "zero_crossing_rate": 0.12,
      "features": {
        "mfcc": [[...]],
        "chroma": [[...]]
      }
    }
  }
}
```

---

## DAW

### `POST /api/daw/export`

Export processed DAW audio. Uses session cookie auth (browser-only).

**Auth:** Session cookie + CSRF token
**Content-Type:** `multipart/form-data`

**Request form fields:**
- `track_id` — UUID of the track
- `stems[]` — Stem audio files to mix
- `manifest` — JSON edit manifest (volumes, pans, edits)

**Response:** Binary audio file (WAV)

---

## lalal.ai Management

### `GET /api/lalalai/quota`

Get lalal.ai quota for the current user.

**Auth:** Session cookie

**Response:**
```json
{
  "data": {
    "quota_minutes": 120,
    "used_minutes": 45,
    "remaining_minutes": 75
  }
}
```

### `POST /api/lalalai/cancel`

Cancel an active lalal.ai task.

**Request:**
```json
{"task_id": "lalalai-task-id"}
```

### `POST /api/lalalai/cancel-all`

Cancel all pending lalal.ai tasks for the current user.

---

## Export

### `GET /export/stem/:id`

Download a single stem audio file.

**Auth:** Session cookie (browser) or Bearer token
**Response:** Audio file stream

### `GET /export/stems/:track_id`

Download all stems for a track as a ZIP archive.

**Auth:** Session cookie or Bearer token
**Response:** ZIP file stream

### `GET /export/analysis/:track_id`

Export analysis result as JSON.

**Auth:** Session cookie or Bearer token

**Response:**
```json
{
  "track_id": "uuid",
  "title": "Blinding Lights",
  "artist": "The Weeknd",
  "analysis": {
    "tempo": 128.0,
    "key": "A minor",
    "energy": 0.74,
    "spectral_centroid": 1823.4,
    "features": {...}
  }
}
```

---

## File Serving

### `GET /files/*path`

Serve audio files from the uploads directory.

**Auth:** Session cookie required

Path examples:
- `/files/downloads/track-uuid/artist-title.mp3`
- `/files/stems/job-uuid/vocals.wav`

---

## Auth Routes

| Route | Method | Description |
|-------|--------|-------------|
| `/users/register` | GET | Registration form |
| `/users/register` | POST | Submit registration |
| `/users/log-in` | GET | Login form |
| `/users/log-in` | POST | Submit credentials |
| `/users/log-out` | DELETE | Log out |
| `/users/settings` | GET | User settings form |
| `/users/settings` | PUT | Update settings |
| `/auth/spotify` | GET | Initiate Spotify OAuth |
| `/auth/spotify/callback` | GET | Spotify OAuth callback |

---

## See Also

- [WebSocket Channels](websocket.md)
- [Rate Limiting](index.md#rate-limits)
- [Architecture: Router](../architecture/index.md)

---

[← API Overview](index.md) | [Next: WebSocket →](websocket.md)
