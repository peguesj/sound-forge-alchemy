---
title: WebSocket Channels
parent: API Reference
nav_order: 2
---

[Home](../index.md) > [API Reference](index.md) > WebSocket Channels

# WebSocket Channels

Phoenix Channel and LiveView WebSocket documentation.

## Table of Contents

- [Overview](#overview)
- [Connection Setup](#connection-setup)
- [JobChannel](#jobchannel)
- [LiveSocket](#livesocket)
- [PubSub Topics](#pubsub-topics)
- [Event Reference](#event-reference)

---

## Overview

SFA provides two WebSocket surfaces:

1. **Phoenix Channels** (`/socket`) — For external clients (mobile apps, CLI tools) that need real-time job progress without a full browser/LiveView session.
2. **LiveSocket** (`/live`) — The Phoenix LiveView WebSocket. All browser UI updates go through this connection.

---

## Connection Setup

### Phoenix Channel Client

```javascript
import {Socket} from "phoenix"

const socket = new Socket("/socket", {
  params: {token: userToken}
})
socket.connect()

// Join the job channel
const channel = socket.channel("jobs:JOB_UUID_HERE", {})
channel.join()
  .receive("ok", resp => console.log("Joined channel", resp))
  .receive("error", resp => console.log("Unable to join", resp))
```

### Authentication

Pass a `token` in the socket params. Tokens are generated at `/users/settings` → API Keys.

```javascript
const socket = new Socket("/socket", {
  params: {token: "your-api-token"}
})
```

---

## JobChannel

**Module:** `SoundForgeWeb.JobChannel`
**Topic pattern:** `"jobs:{job_id}"`

Subscribe to real-time progress events for a specific job (download, processing, or analysis).

### Joining

```javascript
const channel = socket.channel("jobs:a1b2c3d4-e5f6-...", {})
channel.join()
```

### Events Received from Server

#### `job:progress`

Sent periodically during job execution.

```json
{
  "topic": "jobs:uuid",
  "event": "job:progress",
  "payload": {
    "job_id": "uuid",
    "status": "downloading",
    "progress": 45,
    "message": "Downloading audio..."
  }
}
```

`status` values: `"queued"`, `"downloading"`, `"processing"`, `"completed"`, `"failed"`
`progress`: Integer 0–100

#### `job:completed`

Sent when a job finishes successfully.

```json
{
  "event": "job:completed",
  "payload": {
    "job_id": "uuid",
    "job_type": "download",
    "track_id": "uuid",
    "result": {
      "output_path": "/files/downloads/...",
      "file_size": 8394752
    }
  }
}
```

`job_type` values: `"download"`, `"processing"`, `"analysis"`

#### `job:failed`

Sent when a job fails (after all retries exhausted).

```json
{
  "event": "job:failed",
  "payload": {
    "job_id": "uuid",
    "job_type": "download",
    "error": "spotdl: track not available in your region"
  }
}
```

### Client → Server Messages

#### `ping`

```javascript
channel.push("ping", {})
  .receive("ok", resp => console.log("pong", resp))
```

---

## LiveSocket

**URL:** `/live`
**Module:** `SoundForgeWeb.Endpoint` (LiveView WebSocket)

The LiveSocket is used by the browser for all Phoenix LiveView interactions. It is initialized in `assets/js/app.js`:

```javascript
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {
    AnalysisRadar,
    AnalysisChroma,
    AnalysisBeats,
    AnalysisMFCC,
    AnalysisSpectral,
    DjDeck,
    DawEditor,
    DawPreview
  }
})
liveSocket.connect()
```

### LiveView Events

LiveView events are sent between the browser and the server automatically as part of the LiveView protocol. Key user-initiated events:

| Event | Trigger | Handler |
|-------|---------|---------|
| `fetch_spotify` | Spotify URL form submit | `DashboardLive.handle_event/3` |
| `start_download` | Download button | `DashboardLive.handle_event/3` |
| `start_separation` | Separate stems button | `DashboardLive.handle_event/3` |
| `start_analysis` | Analyze button | `DashboardLive.handle_event/3` |
| `play_track` | Play button | Routes to AudioPlayerLive or Spotify SDK |
| `dismiss_pipeline` | Dismiss button | `DashboardLive.handle_event/3` |

### Server Push to Hooks

The server can push events to JS hooks via `push_event/3`:

```elixir
# In LiveView
socket = push_event(socket, "analysis_data", %{
  track_id: track.id,
  tempo: result.tempo,
  key: result.key,
  chroma: result.features["chroma"]
})
```

The hook receives it:

```javascript
// In AnalysisChroma hook
mounted() {
  this.handleEvent("analysis_data", data => {
    this.renderChromaChart(data.chroma)
  })
}
```

---

## PubSub Topics

Internal PubSub topics (BEAM process-level, not exposed to external WebSocket clients):

| Topic | Publisher | Subscriber |
|-------|-----------|-----------|
| `"tracks"` | `Music` context | `DashboardLive` |
| `"jobs:{job_id}"` | Oban workers | `JobChannel`, `DashboardLive` |
| `"midi:events"` | `MIDI.DeviceManager` | `MidiLive`, `DjLive` |
| `"osc:events"` | `OSC.Server` | `DawLive` |

---

## Event Reference

### Complete Job Progress Event

```elixir
# Broadcast from Oban worker
Phoenix.PubSub.broadcast(SoundForge.PubSub, "jobs:#{job_id}", {
  :job_progress,
  %{
    job_id: job_id,
    track_id: track_id,
    status: :processing,
    progress: 60,
    message: "Separating stems..."
  }
})
```

### Track Created Event

```elixir
# Broadcast from Music context
Phoenix.PubSub.broadcast(SoundForge.PubSub, "tracks", {
  :track_created,
  %Track{id: ..., title: ..., artist: ...}
})
```

DashboardLive handles this and calls `stream_insert/3` to add the track to the library list.

---

## See Also

- [REST Endpoints](rest.md)
- [Architecture: PubSub](../architecture/index.md)
- [Features: Import Pipeline](../features/import-pipeline.md)

---

[← REST Endpoints](rest.md) | [Next: Changelog →](../changelog/index.md)
