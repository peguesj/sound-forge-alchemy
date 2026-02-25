---
title: DJ / DAW Tools
parent: Features
nav_order: 4
---

[Home](../index.md) > [Features](index.md) > DJ / DAW Tools

# DJ / DAW Tools

Two-deck DJ mixer and multi-track DAW editor.

## Table of Contents

- [Overview](#overview)
- [DJ Deck](#dj-deck)
- [DAW Editor](#daw-editor)
- [LiveComponent Architecture](#livecomponent-architecture)
- [JS Hooks](#js-hooks)
- [MIDI/OSC Control](#midiosc-control)
- [Export](#export)

---

## Overview

SFA includes two professional audio tools built into the dashboard:

- **DJ Deck** — A two-deck mixer for live mixing with BPM sync, loop controls, EQ, and cue points.
- **DAW Editor** — A multi-track editor for per-stem mute/solo, volume control, and MIDI export.

Both are accessed via tabs on the main dashboard at `/` (using `?tab=dj` and `?tab=daw`). Legacy routes `/dj` and `/daw/:track_id` redirect to the appropriate dashboard tabs.

![Main dashboard with Library, Browse, DAW, DJ, and Pads tabs in the top navigation](../assets/screenshots/dashboard-authenticated.png)
*The main dashboard at `/`. The **DAW**, **DJ**, and **Pads** tabs in the top navigation open the respective tools. The left sidebar's **Studio** section (DAW, DJ, Pads) provides the same navigation. Both tools are LiveComponents embedded in `DashboardLive` and share its track library without a separate data fetch.*

---

## DJ Deck

**LiveComponent:** `SoundForgeWeb.DjLive`
**JS Hook:** `DjDeck`

### Features

- **Two decks (A and B)** — Each loads a downloaded track with full playback controls
- **BPM sync** — Pitch-shift one deck to match the other's tempo
- **Loop controls** — Set loop start/end points; toggle active loop
- **EQ (3-band)** — High, mid, low frequency adjusters per deck
- **Crossfader** — Blend between decks
- **Cue points** — Set and jump to named cue markers
- **Waveform display** — Scrolling waveform with playhead and beat grid

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Play/pause active deck |
| `1` / `2` | Switch active deck |
| `Q` | Set cue on active deck |
| `W` | Jump to cue on active deck |
| `A` / `S` | Adjust crossfader left/right |

### Deck Session Persistence

Active deck sessions are stored in `SoundForge.DJ.DeckSession` (ETS-backed). Sessions persist for the browser session duration.

---

## DAW Editor

**LiveComponent:** `SoundForgeWeb.DawLive`
**JS Hook:** `DawEditor`, `DawPreview`

### Features

- **Multi-track view** — One lane per stem (vocals, drums, bass, other/guitar/piano)
- **Per-stem controls:**
  - Mute toggle
  - Solo mode
  - Volume fader (0–200%)
  - Pan knob (-100 to +100)
- **Timeline** — Zoom in/out, scrub position
- **Edit operations** — Cut, copy, trim, fade in/out (stored as `SoundForge.DAW.EditOperation` records)
- **Preview** — Real-time stem mixing in the browser via Web Audio API
- **MIDI export** — Export beat grid and cue points as MIDI file

### Edit Operations

Edit operations are stored as a log in PostgreSQL, enabling undo/redo:

```elixir
# EditOperation schema
%EditOperation{
  track_id: uuid,
  operation: "cut" | "fade_in" | "fade_out" | "trim" | "volume",
  params: %{start_ms: 1000, end_ms: 5000, value: 0.8},
  applied_at: datetime
}
```

### DAW Export API

```
POST /api/daw/export
Content-Type: multipart/form-data
Authorization: session cookie

{stem files + edit manifest}
-> Returns processed audio file
```

---

## LiveComponent Architecture

Both DJ and DAW are `Phoenix.LiveComponent` embedded in `DashboardLive`. They are **not** standalone LiveViews.

```
DashboardLive (LiveView)
  |
  +-- DjLive (LiveComponent) [?tab=dj]
  |     |-- DjDeck JS Hook
  |
  +-- DawLive (LiveComponent) [?tab=daw]
        |-- DawEditor JS Hook
        |-- DawPreview JS Hook
```

PubSub messages from the server are forwarded from `DashboardLive` to the appropriate component via `send_update/3`.

### Why LiveComponents (not LiveViews)

- DashboardLive holds the track stream (the source of truth for the library)
- DJ and DAW need read access to that library without a separate data fetch
- LiveComponents can call `send_update` to receive targeted updates from the parent

---

## JS Hooks

### DjDeck Hook

```javascript
// assets/js/hooks/dj_deck.js
const DjDeck = {
  mounted() {
    // Initialize Web Audio API nodes (deck A and B)
    // Handle phx events: load_track, play, pause, set_bpm, set_loop
    this.handleEvent("deck_update", ({deck, state}) => {
      // Update waveform display, playhead, cue markers
    })
  }
}
```

### DawEditor Hook

```javascript
// assets/js/hooks/daw_editor.js
const DawEditor = {
  mounted() {
    // Initialize timeline canvas
    // Handle stem mute/solo/volume events
    this.handleEvent("stem_update", ({stems}) => {
      // Re-render track lanes
    })
  }
}
```

### DawPreview Hook

Handles real-time stem mixing using Web Audio API `GainNode` and `ChannelMergerNode`:

```javascript
const DawPreview = {
  mounted() {
    this.ctx = new AudioContext()
    this.stemNodes = {}  // One AudioBufferSourceNode per stem

    this.handleEvent("load_stems", ({stems}) => {
      // Fetch + decode each stem file
      // Route through individual GainNodes
    })

    this.handleEvent("update_volume", ({stem_type, volume}) => {
      this.stemNodes[stem_type].gainNode.gain.value = volume
    })
  }
}
```

---

## MIDI/OSC Control

**Module:** `SoundForge.MIDI` (midiex)
**Module:** `SoundForge.OSC`

Both DJ decks and DAW controls can be mapped to MIDI hardware controllers:

- **MIDI Learn** — Click a control and press a MIDI button/knob to assign
- **Preset mappings** — Built-in mappings for popular controllers (Pioneer DDJ-200, Traktor Kontrol S2)
- **OSC** — Open Sound Control server for DAW integration (Ableton Link, TouchOSC)

MIDI mappings are stored in `SoundForge.DJ.Presets` and persisted per user in the database.

---

## Export

| Export | Route | Format |
|--------|-------|--------|
| Single stem | `GET /export/stem/{id}` | WAV/MP3 |
| All stems (ZIP) | `GET /export/stems/{track_id}` | ZIP |
| Analysis JSON | `GET /export/analysis/{track_id}` | JSON |
| DAW export | `POST /api/daw/export` | Processed WAV |

---

## See Also

- [Stem Separation](stem-separation.md)
- [Audio Analysis](analysis.md)
- [API: DAW Export](../api/rest.md#daw)
- [WebSocket: Events](../api/websocket.md)

---

[← Audio Analysis](analysis.md) | [Next: AI Agents →](ai-agents.md)
