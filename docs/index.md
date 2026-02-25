---
title: Sound Forge Alchemy
nav_order: 1
---

# Sound Forge Alchemy

**v4.1.0** — AI-powered audio pipeline with multi-LLM agents, stem separation, and DJ/DAW tools

[![Phoenix](https://img.shields.io/badge/Phoenix-1.8.3-orange)](https://phoenixframework.org)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple)](https://elixir-lang.org)
[![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/peguesj/sound-forge-alchemy/blob/main/LICENSE)

---

Sound Forge Alchemy (SFA) is a production-grade audio toolkit built on Elixir/OTP and Phoenix LiveView. Import tracks from Spotify, separate stems locally via Demucs or in the cloud via lalal.ai, analyze audio features with librosa, query a multi-LLM agent system for music intelligence, and control it all in real time through MIDI/OSC hardware.

![Sound Forge Alchemy - Main Dashboard](assets/screenshots/dashboard-authenticated.png)
*Main library view: 67-track collection with album art, sidebar navigation (Library, Playlists, Browse, Studio), and Spotify player integration.*

---

## Quick Navigation

| Section | Description |
|---------|-------------|
| [Architecture](architecture/index.md) | System design, OTP tree, data model |
| [Guides](guides/index.md) | Quickstart, installation, configuration, deployment |
| [Features](features/index.md) | Import pipeline, stem separation, analysis, DJ/DAW, AI agents, admin |
| [API Reference](api/index.md) | REST endpoints and WebSocket channels |
| [Changelog](changelog/index.md) | Release history |
| [Contributing](contributing/index.md) | Development guidelines |

---

## Feature Highlights

![Login page with magic link and password authentication](assets/screenshots/login.png)
*Authentication page supporting both magic link (email-only) and traditional password login flows.*

- **Spotify Import** — Paste any Spotify URL (track, album, playlist). Metadata fetched via OAuth2 client credentials; audio downloaded by `spotdl`.
- **Dual Stem Engine** — Local Demucs (htdemucs, htdemucs_ft, htdemucs_6s, mdx_extra) or cloud lalal.ai with 9+ stem types and 60-second preview.
- **Audio Analysis** — librosa-powered feature extraction: tempo, key, energy, MFCC, chroma, spectral centroid. Rendered as D3.js visualizations.
- **AI Agent System** — Six specialist agents (TrackAnalysis, MixPlanning, StemIntelligence, CuePoint, Mastering, Library) orchestrated by a routing Orchestrator. Pluggable LLM backends: Anthropic, OpenAI, Google Gemini, Ollama, Azure OpenAI.
- **DJ / DAW Tools** — Two-deck DJ mixer with BPM sync, loop controls, and EQ; multi-track DAW editor with MIDI export and per-stem mute/solo.
- **MIDI/OSC Control** — Hardware controller mapping via `midiex`; Open Sound Control server for DAW integration.
- **Admin Dashboard** — Role-based access (`user`, `admin`, `platform_admin`) with audit logs, user management, and analytics.
- **Real-Time Pipeline** — Oban background jobs, Phoenix PubSub, LiveView streams — no page refresh required.

---

## Recent Changelog

### v4.1.0 (2026-02-25)
- Azure Container Apps production deployment
- SSL termination, DAW fixes, comprehensive documentation

### v4.0.0 (2026-02)
- lalal.ai full cloud stem separation integration (82 files, +12,398 lines)
- 9+ lalal.ai stem types, 60-second preview, quota management

### v3.0.0 (2026-01)
- Audio analysis expansion: MFCC, chroma, spectral, 5 D3.js visualizations
- 24 files, +4,712 lines

---

## Getting Started

![Registration page](assets/screenshots/register.png)
*Registration page: create an account to begin importing tracks and building your library.*

For setup instructions see the [Quickstart Guide](guides/quickstart.md).

---

## Repository Links

- [GitHub Repository](https://github.com/peguesj/sound-forge-alchemy)
- [Open Issues](https://github.com/peguesj/sound-forge-alchemy/issues)
- [Pull Requests](https://github.com/peguesj/sound-forge-alchemy/pulls)
- [Live Demo](https://sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io)

---

## See Also

- [Quickstart Guide](guides/quickstart.md)
- [Architecture Overview](architecture/index.md)
- [API Reference](api/index.md)
