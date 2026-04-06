---
title: Changelog
nav_order: 6
---

[Home](../index.md) > Changelog

# Changelog

Release history for Sound Forge Alchemy.

Jump to version:
<select id="version-jump" onchange="document.getElementById(this.value).scrollIntoView({behavior:'smooth'})" style="background:#1e293b;color:#e2e8f0;border:1px solid #334155;padding:4px 8px;border-radius:4px;margin-bottom:1rem">
  <option value="">— select version —</option>
  <option value="v470">v4.7.0 (Unreleased) — CrateDigger + MIDI Redesign</option>
  <option value="v460">v4.6.0 — DJ Playback + MIDI Fixes</option>
  <option value="v450">v4.5.0 — Audio-to-MIDI + Chord Detection</option>
  <option value="v440">v4.4.0 — Prototype Sandbox + Docs</option>
  <option value="v430">v4.3.0 — Multi-LLM Agents</option>
  <option value="v4212">v4.2.12 — Azure Container Apps</option>
  <option value="v4211">v4.2.11 — Analysis Expansion</option>
  <option value="v4210">v4.2.10 — lalal.ai + DAW + DJ Decks</option>
  <option value="v429">v4.2.9 — WebSocket Reconnect Fix</option>
  <option value="v428">v4.2.8 — Admin Dashboard v2</option>
  <option value="v427">v4.2.7 — Melodics + OSC + Mobile</option>
  <option value="v426">v4.2.6 — Album Art + Smart Folders</option>
  <option value="v425">v4.2.5 — MIDI Subsystem</option>
  <option value="v424">v4.2.4 — Admin RBAC</option>
  <option value="v423">v4.2.3 — lalal.ai Integration</option>
  <option value="v422">v4.2.2 — D3 Visualizations</option>
  <option value="v421">v4.2.1 — Debug Panel + yt-dlp Fallback</option>
  <option value="v420">v4.2.0 — Deduplication + Formatting</option>
  <option value="v410">v4.1.0 — E2E Infrastructure</option>
  <option value="v400">v4.0.0 — lalal.ai Full Integration</option>
  <option value="v300">v3.0.0 — Analysis Expansion</option>
  <option value="v200">v2.0.0 — Multi-LLM Agents</option>
  <option value="v100">v1.0.0 — Initial Phoenix Port</option>
</select>

---

<h2 id="v470">v4.7.0 — Unreleased</h2>

**CrateDigger + MIDI Redesign**

*In development on `feature/crate-digger`.*

### CrateDigger Module
- New `/crate` route — Spotify playlist import with per-track stem configuration
- `Crate` and `CrateTrackConfig` schemas with JSONB stem config overrides
- `WhoSampledScraper` — async sample history fetcher with 7-day TTL cache
- Slide panel: WhoSampled sample chain with origin tracks and year display
- Effective stem config resolution: track override → crate default → global default
- Full-width layout (no sidebar when CrateDigger active)
- PubSub stem broadcast for cross-module stem config sync

### MIDI Redesign (M-VAVE Profile)
- M-VAVE Chocolate 16-button MIDI controller profile with 3-column SVG layout
- `ControllerRegistry` GenServer for hardware device management
- OSC route `/osc` for Open Sound Control configuration
- SVG pad grid with live status indication
- Universal MIDI action executor across all modules (Dashboard, DJ, DAW, Pads, CrateDigger)

### Bug Fixes
- PWA manifest icon paths fixed (`/icon-192.png` not `/images/icon-192.png`) — resolves SW cache failure
- Deprecated `apple-mobile-web-app-capable` meta tag removed
- Track library overflow above sticky filter bar fixed (nested `overflow-y-auto` removed)
- Select All defaults to all pages in one click (no two-step)

---

<h2 id="v460">v4.6.0 — 2026-03-11</h2>

**DJ Dual-Deck Instantaneous Playback and MIDI Fixes**

### Added
- `JS.dispatch` + `JS.push` dual-path architecture for sub-frame DJ playback response
- AI cue detection engine (`AutoCueWorker`) — 26+ ML-identified cues per track (drops, breakdowns, build-ups)
- Stem loop decks — per-stem independent loop points in DJ tab
- Crossfader curve modes: linear, constant power, sharp cut, slow fade
- SMPTE/bar-beat transport display at 60fps
- Master sync with phase-aligned pitch-lock between decks
- Built-in metronome with headphone cue routing
- Chef AI set builder for harmonic/energy-optimized track sequencing
- Virtual controller — software MIDI surface in-browser
- Chromatic pad surface with auto-cue integration and velocity sensitivity
- Controller preset import/export as JSON
- `midi_results` and `chord_results` database tables
- `auto_midi_chord` user settings columns (auto-trigger after analysis)

### Fixed
- MIDI `DeviceManager` ETS key collision — composite `port_id` (`"input:N"` / `"output:N"`) prevents input/output overwrite
- MIDI `Dispatcher` added to OTP supervision tree (was never started — zero MIDI messages dispatched)
- `phx-change` on `<select>` elements outside `<form>` silently failed — all MIDI selects wrapped in `<form>` tags
- `resolve_user_id/1` guard changed from `is_binary` to `is_integer` (was returning raw UUID bytes to integer column)
- `Mapping` schema removed incorrect UUID `@primary_key` override — uses integer serial PK from migration
- `debug_log` WebSocket flood at 30Hz — guarded on `debug_panel_open` with rate limiting
- BPM display throttled to 5-second server-sync intervals to prevent excessive DOM updates
- `ArgumentError` in `toggle_play` / `set_hot_cue` / `trigger_cue` — `to_string` type normalization at handler boundary

---

<h2 id="v450">v4.5.0 — 2026-02-26</h2>

**Audio-to-MIDI, Chord Detection, Piano Roll, Audio Warping**

### Added
- Polyphonic audio-to-MIDI conversion via Spotify's basic-pitch (`AudioToMidiPort`, `AudioToMidiWorker`)
- Chord detection via librosa chroma_cqt with Krumhansl key profiles (`ChordDetectorPort`, `ChordDetectionWorker`)
- Pure Elixir MIDI file writer with variable-length quantity encoding (`MidiFileWriter`)
- Canvas-based piano roll visualization JS hook (`piano_roll.js`)
- D3-based chord progression timeline JS hook (`chord_progression.js`)
- Audio warping (time-stretch / pitch-shift) via pyrubberband (`AudioWarpPort`, `AudioWarpWorker`)
- `MidiResult` and `ChordResult` Ecto schemas with upsert pattern (one result per track)
- Auto-pipeline extensions — user settings for auto MIDI conversion and chord detection after analysis
- Chord boundary cue points in `AutoCueWorker` — major chord changes as structural markers
- Harmonic complexity axis in analysis radar chart (7th axis when chord data available)
- MIDI file export endpoint (`GET /export/midi/:track_id`)
- 38 new tests covering all new workers, ports, and schemas
- 772 total tests, 0 failures

### Changed
- `AnalysisWorker` chains MIDI/chord workers when user auto-pipeline settings are enabled
- `AutoCueWorker` merges chord boundary cues with structure-based cues (500ms dedup window)
- `PortSupervisor` extended with `start_audio_to_midi/0`, `start_chord_detector/0`, `start_audio_warp/0`
- Dockerfile runtime image includes `rubberband-cli` and `libsndfile1` for pyrubberband

---

<h2 id="v440">v4.4.0 — 2026-02-25</h2>

**Prototype Sandbox, DevTools Panel, Platform Admin**

### Added
- `/prototype` route — dev-only sandbox (admin role + Mix.env() == :dev) with four tabs:
  - **Components**: full daisyUI v5 reference — buttons, badges, alerts, cards, stats, tables, forms, modals
  - **DevTools**: live Oban queue monitor, LLM provider health, recent jobs table with retry button
  - **UAT**: 5 scenario runner, fixture loader, clear test data action
  - **LLM Sandbox**: direct `Orchestrator.run/2` textarea with raw result + token usage
- `SoundForge.UAT` module — `seed_test_track/1`, `seed_test_user/1`, `clear_test_data/0`, runtime env guard
- `platform_admin` role — 6th tier in role hierarchy (user → pro → enterprise → admin → super_admin → platform_admin)
- `CombinedLibraryLive` at `/platform/library` — paginated all-users track table with search
- `DevToolsPanelComponent` — floating dev overlay injected in layout (dev only)
- `SoundForge.Accounts` context — `list_users/0`, `get_user!/1`, `update_user_role/2`
- `SoundForge.Tracks` context — `list_all_tracks/0`, `list_all_tracks_paginated/1` with search/pagination
- 41-page GitHub Pages documentation site (Jekyll, just-the-docs dark theme, 191 internal links)
- Migration `20260225000001_add_platform_admin_role`

### Changed
- Dev server now binds to `0.0.0.0:4000` (was `127.0.0.1`) for LAN/Docker access
- `AdminLive @valid_roles` includes `:platform_admin`
- `layouts.ex` `role_badge/1` adds `platform_admin` → `badge-secondary` clause
- README.md complete rewrite with collapsible `<details>` sections, badge shields

---

<h2 id="v430">v4.3.0 — 2026-02-25</h2>

**Multi-LLM Agentic System**

### Added
- Multi-LLM provider routing with intelligent task-to-model dispatch (`SoundForge.LLM.Router`)
- 9 LLM provider adapters: Anthropic, OpenAI, Azure OpenAI, Google Gemini, Ollama, LM Studio, LiteLLM, custom OpenAI-compatible, system providers
- Fallback chain logic — up to 4 automatic provider retries (`:speed | :quality | :cost` preference)
- Per-user LLM provider configuration with at-rest encryption (Cloak/AES-GCM vault)
- `ModelRegistry` GenServer for provider health tracking and capability discovery
- 6 specialist AI agents with capability routing:
  - `TrackAnalysisAgent` — key, BPM, energy, harmonic analysis
  - `MixPlanningAgent` — set sequencing, transition advice, key compatibility
  - `StemIntelligenceAgent` — stem analysis, loop extraction recommendations
  - `CuePointAgent` — drop detection, loop region, cue point analysis
  - `MasteringAgent` — loudness analysis, mastering advice
  - `LibraryAgent` — library search, track recommendations, playlist curation
- `Orchestrator` — keyword-based auto-routing + explicit `:task` hint dispatch
- Pipeline mode: `Orchestrator.pipeline/2` for sequential agent chains with merged results
- 707 tests, 0 failures

### Changed
- LLM provider settings UI in user settings LiveView
- Admin panel gains LLM provider health dashboard

---

<h2 id="v4212">v4.2.12 — 2026-02-25</h2>

**Azure Container Apps Production Deployment**

### Added
- Azure Container Apps deployment configuration (`sfa-app` in `sfa-env`, eastus)
- `Dockerfile` hardened for multi-stage amd64 builds via `az acr build` (required for Apple Silicon)
- SSL termination and HTTPS-only configuration for Azure hosting
- `rel/overlays/bin/server` and `rel/overlays/bin/migrate` release scripts
- Live at: `sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io`

### Changed
- `config/runtime.exs` updated with `DATABASE_SSL`, `ECTO_IPV6`, `POOL_SIZE`, `PHX_HOST` env support
- DAW tab component bug fixes for production rendering

---

<h2 id="v4211">v4.2.11 — 2026-02-24</h2>

**Analysis Expansion + DJ Preset Management**

### Added
- Analysis expansion: `AnalysisEnergyCurve` and `AnalysisStructure` D3.js hooks
- `SoundForge.DJ.Presets` — DJ preset management with persistence
- DAW editor extended with clip editing and arrangement features (`daw_editor.js` +186 lines)
- `SoundForge.Audio.AnalysisHelpers` — shared audio analysis utility functions
- Analysis API controller with validation hardening

### Changed
- `analysis_beats.js` hook refactored with improved waveform rendering
- lalal.ai integration finalized with full stem type coverage

---

<h2 id="v4210">v4.2.10 — 2026-02-24</h2>

**Full lalal.ai Integration + DAW Editor + DJ Deck**

### Added
- Full lalal.ai API v1.1.0 integration (PR #7)
- DAW tab: `daw_editor.js` (700-line WebAudio arrangement editor) and `daw_preview.js`
- DJ deck: `dj_deck.js` (711-line virtual DJ deck with jog wheel)
- `jog_wheel.js` hook for hardware jog wheel emulation
- `Dockerfile` for containerized deployment
- `.env.example` with all required environment variables documented
- `.dockerignore` for optimized Docker build context

### Changed
- `audio_player.js` extended with stem switching and loop controls (+103 lines)
- `config/runtime.exs` receives lalal.ai API key configuration

---

<h2 id="v429">v4.2.9 — 2026-02-20</h2>

**WebSocket Reconnect Scope Fix**

### Fixed
- `current_scope` lost on LiveSocket WebSocket reconnect — WebSocket upgrades bypass Plug pipeline; scope now loaded from session token on mount when socket assigns are absent, preventing user email from disappearing from header after reconnect

---

<h2 id="v428">v4.2.8 — 2026-02-19</h2>

**Admin Dashboard v2 + Role Hierarchy**

### Added
- SFA Admin Dashboard v2 with expanded SaaS role hierarchy (PR #6)
- 5-tier role system: `user`, `moderator`, `admin`, `super_admin`, `system`
- Audit log context (`SoundForge.Admin.AuditLog`) with structured event recording
- Role promotion/demotion UI in admin users tab
- `require_admin_user/2` plug updated for role hierarchy enforcement
- Database migrations: `expand_roles_add_status`, `create_audit_logs`

---

<h2 id="v427">v4.2.7 — 2026-02-19</h2>

**Melodics + OSC + Mobile Layout**

### Added
- Melodics integration (`SoundForge.Integrations.Melodics`) — practice session tracking and adapter
- MPC App profile (`SoundForge.MIDI.Profiles.MpcApp`) for Akai MPC software MIDI mapping
- TouchOSC layout generator (`SoundForge.OSC.TouchoscLayout`) and Mix task `sfa.touchosc.generate`
- OSC pipeline: server, parser, client, action executor, MIDI-OSC bridge (`SoundForge.Bridge.MidiOsc`)
- Responsive layout: `mobile_drawer.ex`, `mobile_nav.ex`, stem mixer component
- `StemMixer` LiveComponent with `stem_mixer_hook.js` for per-stem volume/pan
- `PadAssignment` LiveComponent with `pad_assign_hook.js`
- `PracticeLive` LiveView for Melodics session display
- PWA manifest (`priv/static/manifest.json`) and service worker (`priv/static/sw.js`)
- `resize_observer_hook.js` and `swipe_hook.js` for mobile interaction
- Database migration: `create_melodics_sessions`

---

<h2 id="v426">v4.2.6 — 2026-02-19</h2>

**Album Art + Smart Folders**

### Added
- Track images in dashboard — album art display from Spotify metadata
- Smart folders foundation (`playlist.source` field) for source-based playlist grouping
- `Music.playlist` schema extended with `source` column

### Fixed
- `spotify_dl.py` image URL handling and metadata extraction

---

<h2 id="v425">v4.2.5 — 2026-02-19</h2>

**USB and Network MIDI Subsystem**

### Added
- Full MIDI subsystem via Midiex (PR #1)
- `SoundForge.MIDI` namespace: `DeviceManager`, `Dispatcher`, `Parser`, `Mapping`, `Mappings`, `Message`, `Clock`, `Output`, `ActionExecutor`, `NetworkDiscovery`
- MPC controller profile (`SoundForge.MIDI.MpcController`) with 320-line mapping implementation
- `MidiLive` LiveView for MIDI device configuration and live mapping
- `app_header.ex` updated with MIDI status indicator
- Database migration: `create_midi_mappings`

---

<h2 id="v424">v4.2.4 — 2026-02-19</h2>

**Admin Dashboard + RBAC**

### Added
- Admin dashboard with role-based access control (initial implementation)
- `SoundForge.Admin` context: `list_users/0`, `update_user_role/2`, `system_stats/0`, `all_jobs/0`
- `AdminLive` with 4 tabs: overview, users, jobs, system (daisyUI components)
- `Accounts.Scope` extended with `admin?` boolean field
- `require_admin_user/2` plug in `user_auth.ex`
- `/admin` route under admin pipeline
- `mix promote_admin <email>` Mix task for first admin setup
- `role` enum field on `users` table (migration: `add_role_to_users`)

---

<h2 id="v423">v4.2.3 — 2026-02-19</h2>

**lalal.ai Cloud Stem Separation**

### Added
- lalal.ai API v1.1.0 client (`SoundForge.Audio.Lalalai`) with polling/backoff
- `SoundForge.Jobs.LalalaiWorker` — Oban worker with exponential backoff and status polling
- `ProcessingWorker` delegate routing to `LalalaiWorker` when `engine=:lalalai`
- Engine selection UI: "Local Demucs" vs "Cloud lalal.ai" toggle
- 60-second preview mode for lalal.ai (preview without full download cost)
- Source badges on stems indicating separation engine used
- `SoundForge.Audio.AudioUtils` — shared utility helpers
- Database migrations: `add_lalalai_stem_types`, `add_engine_and_preview_to_processing_jobs`
- `LALALAI_API_KEY` environment variable support in `runtime.exs`

---

<h2 id="v422">v4.2.2 — 2026-02-18</h2>

**D3.js Analysis Visualizations**

### Added
- 5 D3.js analysis visualization hooks: `AnalysisRadar`, `AnalysisChroma`, `AnalysisBeats`, `AnalysisMFCC`, `AnalysisSpectral`
- All hooks registered in `assets/js/app.js`
- Track detail view renders analysis visualizations in dedicated tab
- `AudioPlayerLive` extended with stem switching controls
- `JobProgress` component enhanced with async PubSub update support
- `Music` context extended with analysis query helpers

### Changed
- Dashboard UI refined: pipeline UX improvements, dismiss button visibility logic
- `pipeline_complete?/1` checks only triggered pipeline stages

---

<h2 id="v421">v4.2.1 — 2026-02-17</h2>

**Debug Panel + yt-dlp Fallback**

### Added
- yt-dlp direct fallback in `DownloadWorker` when SpotDL/Spotify API is unavailable
- Verbose SpotDL output capture and parse-failure diagnostics
- Structured Oban telemetry logging with namespace scoping
- `debug_mode` user setting and database migration
- Debug inspector slide-in panel with tabs: real-time logs, error/event trace, worker status, queue panel
- `LogBroadcaster` module with unit test coverage
- `Req.Test` plug support for Spotify HTTPClient testability

### Fixed
- Port conflict handling — server starts without crashing on busy ports
- Well-known probe errors (robots.txt, favicon) silenced in logs

---

<h2 id="v420">v4.2.0 — 2026-02-14</h2>

**Deduplication + Auto-formatting**

### Fixed
- Download path deduplication — absolute paths used for download output to prevent double-nesting
- Stem deduplication guards with unique database indexes
- Analysis deduplication guards to prevent duplicate analysis records
- Auto-formatting pass across all Elixir and HEEx templates

---

<h2 id="v410">v4.1.0 — 2026-02-14</h2>

**E2E Test Infrastructure**

### Added
- Playwright E2E test infrastructure with `playwright.config.ts`
- `SPOTIPY_CLIENT_ID` / `SPOTIPY_CLIENT_SECRET` aliases documented in `.env.example`

### Fixed
- Python runtime pinned to 3.11.7 for SpotDL/Demucs compatibility
- `.gitignore` updated to exclude E2E artifacts and build noise

---

<h2 id="v400">v4.0.0 — 2026-02</h2>

**lalal.ai Full Cloud Stem Separation** (82 files, +12,398 lines)

### Added
- Cloud stem separation via lalal.ai API (9+ stem types including electric guitar, piano, synth)
- 60-second preview before full processing
- lalal.ai quota management dashboard
- `GET /api/lalalai/quota`, `POST /api/lalalai/cancel`, `POST /api/lalalai/cancel-all` endpoints
- Per-user lalal.ai API key storage (encrypted)
- Engine toggle: local Demucs vs. cloud lalal.ai
- `LalalaiWorker` Oban background worker
- Voice pack service for voice transformation
- Admin dashboard with SaaS role hierarchy (`user`, `admin`, `platform_admin`)
- Audit logging for role changes, deactivations, config changes
- User management UI

---

<h2 id="v300">v3.0.0 — 2026-01</h2>

**Analysis Expansion** (24 files, +4,712 lines)

### Added
- 5 D3.js visualization hooks: `AnalysisRadar`, `AnalysisChroma`, `AnalysisBeats`, `AnalysisMFCC`, `AnalysisSpectral`
- MFCC (13 coefficients) and chroma (12 pitch classes) feature extraction
- Spectral centroid, rolloff, bandwidth, contrast features
- Extended `AnalysisResult.features` JSONB column for high-dimensional data
- Beat frame detection and beat grid timeline visualization
- Key detection confidence score
- Analysis export as JSON (`GET /export/analysis/:track_id`)

---

<h2 id="v200">v2.0.0 — 2025-12</h2>

**Multi-LLM Agent System**

### Added
- Six specialist agents: TrackAnalysis, MixPlanning, StemIntelligence, CuePoint, Mastering, Library
- `SoundForge.Agents.Orchestrator` with keyword-based auto-routing
- `SoundForge.LLM.ModelRegistry` GenServer with ETS storage and 5-minute health checks
- Per-user LLM provider config with encrypted API keys (Cloak.Ecto AES-256-GCM)
- Anthropic, OpenAI, Google Gemini, Ollama, Azure OpenAI providers
- DAW LiveComponent with multi-track editor and MIDI export
- DJ LiveComponent with two-deck mixer, BPM sync, and loop controls
- MIDI hardware mapping (Pioneer DDJ-200, Traktor Kontrol S2 presets)
- OSC server for DAW integration

---

<h2 id="v100">v1.0.0 — 2025-11</h2>

**Initial Phoenix/Elixir Port**

### Added
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
- [ADR-004: UX Overhaul](../decisions/ADR-004-ux-overhaul-2026-03.md)

---

[← WebSocket API](../api/websocket.md) | [Next: Contributing →](../contributing/index.md)
