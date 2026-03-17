---
title: Changelog
nav_order: 6
---

[Home](../index.md) > Changelog

# Changelog

Release history for Sound Forge Alchemy.

---

## v4.6.0 — 2026-03-11

**DJ Dual-Deck Instantaneous Playback and MIDI Fixes**

- JS.dispatch + JS.push dual-path architecture for sub-frame DJ playback response
- AI cue detection engine (26+ cues per track) with AutoCueWorker Oban job
- Stem loop decks for per-stem loop control during live mixing
- Crossfader curve modes: linear, constant power, sharp cut, slow fade
- SMPTE/bar-beat transport display at 60fps
- Master sync with phase-aligned pitch-lock between decks
- Built-in metronome with headphone cue routing
- Chef AI set builder for harmonic/energy-optimized track sequencing
- Virtual controller (software MIDI surface in-browser)
- Chromatic pads with auto-cue integration and velocity sensitivity
- Controller preset import/export as JSON

**MIDI Fixes:**
- Fixed ETS key collision in DeviceManager -- composite `port_id` (`"input:N"` / `"output:N"`) replaces raw `num`
- Added Dispatcher to supervision tree (was missing from `application.ex`)
- Wrapped `phx-change` select elements in `<form>` tags (LiveView requirement)
- Fixed `resolve_user_id` guard (changed from `is_binary` to `is_integer`)
- Fixed Mapping schema PK mismatch (removed UUID override, uses integer serial)

**WebSocket Optimization:**
- Fixed 30Hz WebSocket flood -- `debug_log` handler guarded on `debug_panel_open`
- BPM throttle handler with 5-second interval (local JS.dispatch + throttled server sync)

**Bug Fixes:**
- Fixed ArgumentError in `toggle_play` / `set_hot_cue` / `trigger_cue` -- `to_string` type normalization at handler boundary

**Database:**
- New `midi_results` table
- New `chord_results` table
- New `auto_midi_chord` user settings columns

---

## v4.5.0 — 2026-02-26

**Audio-to-MIDI, Chord Detection, Piano Roll, Audio Warping**

- Audio-to-MIDI conversion via basic-pitch
- Chord detection via librosa chroma analysis
- Piano roll visualization component
- Audio warping via pyrubberband
- Auto-pipeline extensions for MIDI and chord stages
- 16 competitive response stories
- 45 files changed, +4,731 lines

---

## v4.4.0 — 2026-02-25

**Prototype Sandbox, DevTools Panel, Platform Admin Library**

- /prototype sandbox (Components, DevTools, UAT, LLM tabs)
- DevTools floating panel component
- UAT fixture/scenario helpers (runtime env guard)
- CombinedLibraryLive at /platform/library (platform_admin)
- Accounts context (list_users, update_user_role)
- Tracks context (list_all_tracks, paginated search)
- 41-page GitHub Pages documentation site (Jekyll, just-the-docs dark theme)

---

## v4.3.0 — 2026-02-25

**Multi-LLM Agentic System**

- LLM adapter/routing layer with 6 specialist agents
- Agent framework with Orchestrator dispatch
- Chat UI for agent interaction
- Health worker for provider monitoring
- 707 tests passing

---

## v4.1.0 — 2026-02-25

**Azure Container Apps Production Deployment**

- Azure Container Apps deployment with SSL termination
- Azure Container Registry image build pipeline
- DAW editor fixes and stability improvements
- Comprehensive GitHub Pages documentation
- `SoundForge.Release.migrate/0` for production migration runner
- Docker multi-stage build optimization

**Bug Fixes:**
- Fixed DAW component routing (LiveComponent instead of standalone LiveView)
- Fixed stem file_path stored as relative (not absolute) for clean `/files/stems/...` URLs
- Fixed `pipeline_complete?/1` to check only triggered stages

---

## v4.0.0 — 2026-02

**lalal.ai Full Cloud Stem Separation Integration** (82 files, +12,398 lines)

- Cloud stem separation via lalal.ai API (9+ stem types)
- 60-second preview before full processing
- lalal.ai quota management dashboard
- `GET /api/lalalai/quota` endpoint
- `POST /api/lalalai/cancel` and `cancel-all` endpoints
- Per-user lalal.ai API key storage (encrypted)
- Engine toggle: local Demucs vs. cloud lalal.ai
- `LalalaiWorker` Oban background worker
- Voice pack service for voice transformation
- Voice change and voice clean workers

**Admin:**
- Admin dashboard with SaaS role hierarchy (`user`, `admin`, `platform_admin`)
- Audit logging for role changes, deactivations, config changes
- User management UI

---

## v3.0.0 — 2026-01

**Analysis Expansion** (24 files, +4,712 lines)

- 5 D3.js visualization hooks: AnalysisRadar, AnalysisChroma, AnalysisBeats, AnalysisMFCC, AnalysisSpectral
- MFCC (13 coefficients) and chroma (12 pitch classes) feature extraction
- Spectral centroid, rolloff, bandwidth, contrast features
- Extended `AnalysisResult.features` JSONB column for high-dimensional data
- Beat frame detection and beat grid timeline visualization
- Key detection confidence score
- Analysis export as JSON (`GET /export/analysis/:track_id`)

---

## v2.0.0 — 2025-12

**Multi-LLM Agent System**

- Six specialist agents: TrackAnalysis, MixPlanning, StemIntelligence, CuePoint, Mastering, Library
- `SoundForge.Agents.Orchestrator` with keyword-based auto-routing and capability-based dispatch
- `SoundForge.LLM.ModelRegistry` GenServer with ETS storage and 5-minute health checks
- Per-user LLM provider configuration with encrypted API keys (Cloak.Ecto AES-256-GCM)
- Support for: Anthropic, OpenAI, Google Gemini, Ollama, Azure OpenAI
- System-level LLM provider fallbacks from environment variables
- DAW LiveComponent with multi-track editor and MIDI export
- DJ LiveComponent with two-deck mixer, BPM sync, and loop controls
- MIDI hardware mapping (Pioneer DDJ-200, Traktor Kontrol S2 presets)
- OSC server for DAW integration

---

## v1.0.0 — 2025-11

**Initial Phoenix/Elixir Port**

- Full port from Node.js/TypeScript to Elixir/Phoenix 1.8
- Phoenix LiveView dashboard replacing React + Socket.IO
- Oban background jobs replacing Redis + BullMQ
- Erlang Port architecture for Demucs and librosa (replacing Node child_process)
- 4-stem Demucs separation (htdemucs, htdemucs_ft, mdx_extra)
- Basic audio analysis: tempo, key, energy, spectral centroid
- Spotify metadata fetch + spotdl audio download
- Phoenix scope-based authentication (phx.gen.auth)
- PostgreSQL schema: tracks, download_jobs, processing_jobs, analysis_jobs, stems, analysis_results
- 653 ExUnit tests, 0 failures

---

## See Also

- [Contributing Guide](../contributing/index.md)
- [Architecture Overview](../architecture/index.md)

---

[← WebSocket API](../api/websocket.md) | [Next: Contributing →](../contributing/index.md)
