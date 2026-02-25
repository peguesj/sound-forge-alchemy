---
title: Changelog
nav_order: 6
---

[Home](../index.md) > Changelog

# Changelog

Release history for Sound Forge Alchemy.

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
