---
title: Features
nav_order: 4
has_children: true
---

[Home](../index.md) > Features

# Features

Sound Forge Alchemy is a full-stack audio processing platform built on Phoenix LiveView. This section catalogs every user-facing feature, from Spotify import through AI-powered music intelligence.

---

## Feature Catalog

### [Spotify Import Pipeline](import-pipeline.md)

The import pipeline accepts any Spotify track or playlist URL and drives the entire download workflow. SpotDL fetches metadata (title, artist, album, ISRC, BPM, key) from the Spotify API, then locates and downloads the highest-quality audio source. Each import becomes an Oban background job with live progress updates streamed to the browser via Phoenix PubSub, so users can monitor queued, running, and completed downloads in real time.

---

### [Stem Separation](stem-separation.md)

Stem separation isolates individual instrument layers from a mixed audio file. Sound Forge Alchemy supports two engines: local Demucs (running on CPU or GPU) and cloud-based lalal.ai. The local engine ships four model variants — `htdemucs`, `htdemucs_ft`, `htdemucs_6s`, and `mdx_extra` — each with different tradeoffs between speed and quality. The lalal.ai integration unlocks up to nine discrete stem types (vocals, drums, bass, electric guitar, acoustic guitar, piano, synthesizer, strings, wind instruments) and offers a 60-second preview without consuming a full processing credit.

---

### [Audio Analysis](analysis.md)

The analysis module runs a Python/librosa pipeline over downloaded tracks and stores quantitative audio features in PostgreSQL. Extracted features include BPM, key, energy, valence, spectral centroid, zero-crossing rate, MFCCs, chroma vectors, and beat frames. Five D3.js visualization hooks render the data directly in the browser: `AnalysisRadar`, `AnalysisChroma`, `AnalysisBeats`, `AnalysisMFCC`, and `AnalysisSpectral`. Analysis runs automatically after download completes or can be triggered manually per track.

---

### [DJ Deck](dj-daw.md)

The DJ Deck is a browser-native two-deck mixer implemented as a Phoenix LiveComponent. Each deck loads a downloaded track through the Web Audio API and exposes individual-stem channel controls. Users can crossfade between decks, adjust tempo independently per deck, cue tracks, and apply low/mid/high EQ. The deck is accessible from the main dashboard via the `?tab=dj` query parameter. A Spotify SDK toggle lets users audition tracks that have not yet been downloaded.

---

### [DAW Preview](dj-daw.md#daw-preview)

The DAW Preview component provides a lightweight multi-track editor view for tracks that have completed stem separation. Each stem appears as its own horizontal lane with per-lane gain control, mute, and solo. Stems are aligned on a shared timeline and play back in sync via the Web Audio API. The DAW is accessible from the dashboard via `?tab=daw` and receives the active track context through LiveView assigns. This is a preview/editing surface, not a full offline DAW — it is designed for rapid stem review and rough arrangement.

---

### [AI Agents](ai-agents.md)

The AI agent system provides music-intelligence capabilities powered by a multi-LLM routing layer. An Orchestrator agent dispatches tasks to six specialist agents: Track Analyst, Mix Engineer, Music Theory, Genre Classifier, Production Assistant, and Lyrics Analyzer. The routing layer supports multiple LLM providers (configurable in admin) with automatic fallback. Agents are invoked from a chat panel in the dashboard and respond with structured analysis, suggested stems, mix recommendations, and music theory observations about the loaded track.

---

### [Admin Portal](admin.md)

The Admin Portal is accessible to users with `admin`, `super_admin`, or `platform_admin` roles. It provides user management (list, search, role assignment), a six-tier role hierarchy (`user → pro → enterprise → admin → super_admin → platform_admin`), audit log review, LLM provider health monitoring, and system-level configuration. The admin panel uses Phoenix LiveView with server-side filtering and pagination. Role changes take effect on the target user's next page load via session revalidation.

---

### [Platform Admin](platform-admin.md)

Platform Admin is a restricted cross-tenant view available exclusively to users with the `platform_admin` role. It renders at `/platform/library` via `CombinedLibraryLive` and displays every track across all user accounts in a unified searchable table. This is intended for infrastructure-level oversight — debugging download failures, reviewing separation queue depth, and auditing storage usage — rather than day-to-day user activity.

---

## Feature Matrix

| Feature | Status | Requires |
|---------|--------|----------|
| [Spotify Import Pipeline](import-pipeline.md) | Production | `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, SpotDL |
| [Stem Separation — Local](stem-separation.md) | Production | Python 3.10+, Demucs, sufficient disk space |
| [Stem Separation — Cloud (lalal.ai)](stem-separation.md#lalalai) | Production | `LALALAI_API_KEY` |
| [Audio Analysis](analysis.md) | Production | Python 3.10+, librosa |
| [DJ Deck](dj-daw.md) | Production | Downloaded track or Spotify SDK |
| [DAW Preview](dj-daw.md#daw-preview) | Production | Completed stem separation |
| [AI Agents](ai-agents.md) | Production | LLM API key configured in admin |
| [Admin Portal](admin.md) | Production | `admin` role or higher |
| [Platform Admin](platform-admin.md) | Production | `platform_admin` role |

---

## See Also

- [Architecture Overview](../architecture/index.md)
- [API Reference](../api/index.md)
- [Guides: Quickstart](../guides/quickstart.md)

---

[Next: Import Pipeline →](import-pipeline.md)
