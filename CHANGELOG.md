# Changelog

All notable changes to Sound Forge Alchemy are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [4.4.0] - 2026-02-25

### Added
- `/prototype` route: dev-only sandbox with four tabs (Components, DevTools, UAT, LLM Sandbox), gated to admin/super_admin/platform_admin role in dev environment
- **Components tab**: full daisyUI v5 component reference — buttons, badges, alerts, cards, stats, tables, form elements, modals, loading states
- **DevTools tab**: live Oban queue monitor (pending/executing/failed/scheduled counts), LLM provider health status, recent jobs table with retry button, log entry display
- **UAT tab**: scenario runner with 5 named scenarios (Import Spotify Track, Run Stem Separation, Call AI Agent, Admin Role Change, Platform Library View), fixture loader (5 test tracks), clear test data action
- **LLM Sandbox tab**: direct `Orchestrator.run/2` textarea with raw result display, provider badge, and token usage
- `SoundForge.UAT` module: `seed_test_track/1`, `seed_test_user/1`, `clear_test_data/0`, `list_scenarios/0`, `run_scenario/2` — runtime env guard (raises in prod)
- `platform_admin` role: 6th tier in role hierarchy, access to `/platform/library` combined library
- `CombinedLibraryLive` at `/platform/library`: paginated table of all tracks across all users with search (title/artist/email), read-only track detail modal
- `DevToolsPanelComponent`: floating bottom-right overlay injected into app layout in dev environment, shows current path, assigns count, quick links to /prototype, /admin, /platform/library, Phoenix LiveDashboard
- `SoundForge.Accounts` context: `list_users/0`, `get_user!/1`, `update_user_role/2`, session management
- `SoundForge.Tracks` context: `list_all_tracks/0`, `list_all_tracks_paginated/1` with search and pagination
- Router: `/platform` scope with `:require_platform_admin` pipeline, `/prototype` scope, `require_platform_admin_role/2` plug
- Migration `20260225000001_add_platform_admin_role` (audit trail)
- `docs/` folder: Jekyll just-the-docs site with architecture, guides, features, decisions, API reference, deployment docs (32 .md files)
- `docs/_config.yml`: dark theme, just-the-docs, GitHub aux link

### Changed
- Dev server now binds to `0.0.0.0:4000` (was `127.0.0.1`) for LAN/Docker access
- `AdminLive @valid_roles` now includes `:platform_admin`
- `layouts.ex` `role_badge/1` clause for `platform_admin` → `badge-secondary`
- README.md: complete rewrite with HTML collapsible `<details>/<summary>` sections, badge shields, v4.4.0

---

## [4.3.0] - 2026-02-25

### Added
- Multi-LLM provider routing system with intelligent task-to-model dispatch (`SoundForge.LLM.Router`)
- 9 LLM provider adapters: Anthropic, OpenAI, Azure OpenAI, Google Gemini, Ollama, LM Studio, LiteLLM, custom OpenAI-compatible, and system providers
- Fallback chain logic — up to 4 automatic provider retries with configurable preference (`:speed | :quality | :cost`)
- Per-user LLM provider configuration with at-rest encryption via Cloak/AES-GCM vault
- `ModelRegistry` for provider health tracking and capability discovery
- 6 specialist AI agents with capability routing:
  - `TrackAnalysisAgent` — key, BPM, energy, harmonic analysis
  - `MixPlanningAgent` — set sequencing, transition advice, key compatibility
  - `StemIntelligenceAgent` — stem analysis, loop extraction recommendations
  - `CuePointAgent` — drop detection, loop region, cue point analysis
  - `MasteringAgent` — loudness analysis, mastering advice
  - `LibraryAgent` — library search, track recommendations, playlist curation
- `Orchestrator` — single entry point with auto-routing by instruction keyword patterns and explicit `:task` hint dispatch
- Pipeline execution mode: `Orchestrator.pipeline/2` runs agents sequentially with merged results
- 16 user stories implemented; test suite expanded to 707 tests (0 failures)

### Changed
- LLM provider settings UI added to user settings LiveView
- Admin panel gains LLM provider health dashboard

---

## [4.2.12] - 2026-02-25

### Added
- Azure Container Apps production deployment configuration
- `Dockerfile` hardened for multi-stage amd64 builds via `az acr build`
- SSL termination and HTTPS-only configuration for Azure hosting
- `rel/overlays/bin/server` and `rel/overlays/bin/migrate` release scripts
- Live deployment at `sfa-app.jollyplant-d0a9771d.eastus.azurecontainerapps.io`

### Changed
- `config/runtime.exs` updated with `DATABASE_SSL`, `ECTO_IPV6`, `POOL_SIZE`, `PHX_HOST` env support
- DAW tab component bug fixes for production rendering

---

## [4.2.11] - 2026-02-24

### Added
- Analysis expansion: `AnalysisEnergyCurve` and `AnalysisStructure` D3.js hooks
- `SoundForge.DJ.Presets` — DJ preset management with persistence
- DAW editor extended with clip editing and arrangement features (`daw_editor.js` +186 lines)
- `SoundForge.Audio.AnalysisHelpers` — shared audio analysis utility functions
- Analysis API controller hardened with validation

### Changed
- `analysis_beats.js` hook refactored with improved waveform rendering
- lalal.ai integration finalized with full stem type coverage

---

## [4.2.10] - 2026-02-24

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

## [4.2.9] - 2026-02-20

### Fixed
- Restored `current_scope` on LiveSocket WebSocket reconnect — WebSocket upgrades bypass Plug pipeline; scope now loaded from session token on mount when socket assigns are absent, preventing user email from disappearing from header after reconnect

---

## [4.2.8] - 2026-02-19

### Added
- SFA Admin Dashboard v2 with expanded SaaS role hierarchy (PR #6)
- 5-tier role system: `user`, `moderator`, `admin`, `super_admin`, `system`
- Audit log context (`SoundForge.Admin.AuditLog`) with structured event recording
- Role promotion/demotion UI in admin users tab
- `require_admin_user/2` plug updated for role hierarchy enforcement
- Database migrations: `expand_roles_add_status`, `create_audit_logs`

---

## [4.2.7] - 2026-02-19

### Added
- Melodics integration (`SoundForge.Integrations.Melodics`) — practice session tracking and adapter
- MPC App profile (`SoundForge.MIDI.Profiles.MpcApp`) for Akai MPC software MIDI mapping
- TouchOSC layout generator (`SoundForge.OSC.TouchoscLayout`) and Mix task `sfa.touchosc.generate`
- OSC pipeline: server, parser, client, action executor, and MIDI-OSC bridge (`SoundForge.Bridge.MidiOsc`)
- Responsive layout system: `mobile_drawer.ex`, `mobile_nav.ex`, stem mixer component
- `StemMixer` LiveComponent with JS hook (`stem_mixer_hook.js`) for per-stem volume/pan
- `PadAssignment` LiveComponent with `pad_assign_hook.js`
- `PracticeLive` LiveView for Melodics session display
- PWA manifest (`priv/static/manifest.json`) and service worker (`priv/static/sw.js`)
- `resize_observer_hook.js` and `swipe_hook.js` for mobile interaction
- Database migration: `create_melodics_sessions`

---

## [4.2.6] - 2026-02-19

### Added
- Track images support in dashboard — album art display from Spotify metadata
- Smart folders foundation (`playlist.source` field) for source-based playlist grouping
- `Music.playlist` schema extended with `source` column (migration: `add_source_to_playlists`)

### Fixed
- `spotify_dl.py` image URL handling and metadata extraction

---

## [4.2.5] - 2026-02-19

### Added
- USB and network MIDI integration (PR #1) — full MIDI subsystem
- `SoundForge.MIDI` namespace: `DeviceManager`, `Dispatcher`, `Parser`, `Mapping`, `Mappings`, `Message`, `Clock`, `Output`, `ActionExecutor`, `NetworkDiscovery`
- MPC controller profile (`SoundForge.MIDI.MpcController`) with 320-line mapping implementation
- `MidiLive` LiveView for MIDI device configuration and live mapping
- `app_header.ex` updated with MIDI status indicator
- Database migration: `create_midi_mappings`

---

## [4.2.4] - 2026-02-19

### Added
- Admin dashboard with role-based access control (initial implementation)
- `SoundForge.Admin` context: `list_users/0`, `update_user_role/2`, `system_stats/0`, `all_jobs/0`
- `AdminLive` with 4 tabs: overview, users, jobs, system (daisyUI components)
- `Accounts.Scope` extended with `admin?` boolean field derived from user role
- `require_admin_user/2` plug added to `user_auth.ex`
- `/admin` route under admin pipeline in router
- `mix promote_admin <email>` Mix task for first admin setup
- `role` enum field on `users` table (migration: `add_role_to_users`)

---

## [4.2.3] - 2026-02-19

### Added
- lalal.ai cloud stem separation integration (US-022 through US-027)
- `SoundForge.Audio.Lalalai` — lalal.ai API v1.1.0 client with polling/backoff
- `SoundForge.Jobs.LalalaiWorker` — Oban worker with exponential backoff and status polling
- `ProcessingWorker` delegate routing: dispatches to `LalalaiWorker` when `engine=:lalalai`
- Engine selection UI in dashboard: "Local Demucs" vs "Cloud lalal.ai" toggle
- 60-second preview mode for lalal.ai (no full download cost)
- Source badges on stems indicating separation engine used
- `SoundForge.Audio.AudioUtils` — shared audio utility helpers
- Database migrations: `add_lalalai_stem_types`, `add_engine_and_preview_to_processing_jobs`
- `LALALAI_API_KEY` environment variable support in `runtime.exs`

---

## [4.2.2] - 2026-02-18

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

## [4.2.1] - 2026-02-17

### Added
- yt-dlp direct fallback in `DownloadWorker` when SpotDL/Spotify API is unavailable
- Fallback uses stored track title/artist/duration from database to search YouTube directly, bypassing Spotify API entirely
- Verbose SpotDL output capture and parse-failure diagnostics (US-002)
- Structured Oban telemetry logging with namespace scoping (US-001)
- `debug_mode` user setting and database migration (US-004)
- Debug inspector slide-in panel shell with tab navigation (US-005)
- Real-time log streaming tab with color coding and filtering (US-006)
- Error and event tracing tab with dependency graph visualization (US-007)
- Worker status collapsible with async PubSub updates (US-008)
- Queue panel with active/history tabs and log anchoring (US-009)
- Debug mode toggle in settings UI (US-010)
- `LogBroadcaster` module with unit test coverage
- Req.Test plug support added to Spotify HTTPClient for testability
- HTTPClient tests rewritten with `Req.Test` stubs

### Fixed
- Port conflict handling: server starts without crashing on busy ports
- Well-known probe errors (robots.txt, favicon) silenced in logs

---

## [4.2.0] - 2026-02-14

### Fixed
- Download path deduplication: absolute paths used for download output to prevent double-nesting
- Stem deduplication guards with unique database indexes
- Analysis deduplication guards to prevent duplicate analysis records
- Auto-formatting pass across all Elixir and HEEx templates

---

## [4.1.0] - 2026-02-14

### Added
- Playwright E2E test infrastructure with `playwright.config.ts`
- SPOTIPY_CLIENT_ID / SPOTIPY_CLIENT_SECRET aliases documented in `.env.example`

### Fixed
- Python runtime pinned to 3.11.7 for SpotDL/Demucs compatibility
- `.gitignore` updated to exclude E2E artifacts and build noise

---

## [4.0.1] - 2026-02-14

### Fixed
- File path bugs in `DownloadWorker` and `ProcessingWorker` causing stem file resolution failures
- E2E stem playback path resolution corrected

---

## [4.0.0] - 2026-02-14

### Added
- Spotify OAuth 2.0 integration with PKCE flow
- Playlist import: browse and import Spotify playlists to library
- User settings LiveView with per-user preferences
- In-app notification system with PubSub broadcast
- Dashboard overhaul: redesigned track grid, status badges, pipeline progress indicators

### Fixed
- `DemucsPort` Python stdout buffering — empty results no longer returned
- Demucs stderr captured and surfaced for error diagnosis
- `sys.executable` used in `demucs_runner.py` for reliable Python invocation
- 6-stem model (`htdemucs_6s`) support confirmed in runner
- Parsed DemucsPort result now stored in state to prevent data loss

---

## [3.5.0] - 2026-02-13

### Added
- SpotDL timeout detection with configurable threshold
- SpotDL rate-limit detection with automatic backoff
- Phase 40 comprehensive test suite completion
- `AudioPlayerLive` component tests
- Export controller hardening: empty zip file prevention (Phase 37)
- Async SpotDL metadata fetch to prevent LiveView timeout (Phase 38)

### Changed
- Worker hardening: stale struct fixes, improved error handling (Phase 36)
- `DemucsPort` dead code branch removed (Dialyzer compliance)
- Dashboard LiveView nesting depth reduced (Credo compliance)

### Fixed
- Duplicate `AudioPlayerLive` test removed
- File validation uses positive conditions (Credo compliance)

---

## [3.0.0] - 2026-02-13

### Added
- Comprehensive input validation across all Phoenix controllers and LiveViews
- Rate limiting middleware for API and download endpoints
- IDOR ownership checks on all track, stem, and analysis resources (Phase 35)
- File existence validation on processing and analysis API endpoints (Phase 34)
- Dialyzer type annotations across LLM and HTTP client modules (Phase 33)
- ARIA accessibility attributes across dashboard and settings views (Phase 28)
- Schema `@moduledoc` coverage and `AnalysisResult` changeset tests (Phase 29)
- Credo static analysis configuration and full compliance pass (Phase 32)
- Port module unit tests for `AnalyzerPort` and `DemucsPort` (Phase 31)
- Dashboard event handler and export edge case tests (Phase 30)
- `HTTPClient` tests with `Req.Test` stub infrastructure (Phase 33)

### Changed
- Security model hardened: all resource mutations verify ownership
- `user_auth.ex` updated with `require_authenticated_user` enforcement across routes

---

## [2.0.0] - 2026-02-13

### Added
- SpotDL integration for track download and Spotify metadata resolution
- `SoundForge.Audio.SpotDL` module wrapping `spotdl` CLI
- `priv/python/spotify_dl.py` Python bridge for SpotDL invocation
- Download pipeline uses SpotDL to fetch track metadata before enqueuing Oban job

### Removed
- Direct Spotify Web API download calls replaced by SpotDL

---

## [1.0.0] - 2026-02-13

### Added
- Feature-complete MVP: all Phase 10–16 stories delivered
- Safe input parsing for all user-supplied data (Phase 16)
- Configuration extraction to `config/` namespace (no more hardcoded values)
- Structured logging with `Logger.metadata/1` across all workers and contexts
- Security hardening: CSRF protection, secure cookies, Content-Security-Policy headers
- Accessibility: keyboard navigation, ARIA labels, focus management
- File management: upload size limits, MIME type validation, virus scan hooks
- Full test suite with 653 tests, 0 failures

---

## [0.9.0] - 2026-02-12

### Added
- Health check endpoint at `/health` returning system status JSON
- Security headers middleware: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`
- Custom error pages: 404, 500, 422 with consistent daisyUI styling
- Pagination for track library and admin job list
- `robots.txt` and `sitemap.xml` statics

---

## [0.8.0] - 2026-02-12

### Added
- Stem export: download individual or bundled stem files as `.zip`
- Track library sorting: by title, artist, BPM, key, date added
- Playlist processing: enqueue all tracks in a playlist for download + analysis
- Owner access control: users can only view/modify their own tracks

---

## [0.7.0] - 2026-02-12

### Added
- Supervisor tree hardened with `DemucsPort` and `AnalyzerPort` restart strategies
- Retry UI: failed jobs display retry button with exponential backoff display
- Telemetry integration: `Telemetry.Metrics` and `TelemetryPoller` configured
- Structured error handling across all Oban workers

### Changed
- `Application` supervisor spec updated for fault-tolerant port supervision

---

## [0.6.0] - 2026-02-12

### Added
- `SoundForge.Music` context fully wired to database (Ecto/PostgreSQL)
- `SoundForge.Jobs.DownloadWorker` — real SpotDL invocation via `AnalyzerPort`
- `SoundForge.Jobs.ProcessingWorker` — real Demucs invocation via `DemucsPort`
- `SoundForge.Jobs.AnalysisWorker` — real Python analyzer invocation
- Oban job queue replacing in-memory stub job system

### Removed
- All API stub implementations replaced by real backend workers

---

## [0.5.0] - 2026-02-12

### Added
- Real-time pipeline progress UI driven by Phoenix PubSub
- `JobProgress` LiveComponent with per-stage status indicators
- PubSub topic broadcasting from all Oban workers on stage transitions
- Dashboard subscribes to per-user pipeline topic for live updates

---

## [0.4.0] - 2026-02-12

### Added
- User authentication system via `mix phx.gen.auth`
- Waveform visualization using Web Audio API and Canvas
- Audio analysis dashboard tab with tempo, key, energy, and spectral data display
- REST API authentication with `Authorization: Bearer` token validation
- API rate limiting per authenticated user

---

## [0.3.0] - 2026-02-12

### Added
- Job pipeline chaining: download → process → analyze executed sequentially via Oban dependencies
- Multi-stem audio player: play vocals, drums, bass, other independently
- `AudioPlayerLive` LiveComponent with stem track switching

---

## [0.2.0] - 2026-02-12

### Added
- Full Phoenix backend with domain contexts: `Music`, `Accounts`, `Audio`
- Ecto schemas: `Track`, `Stem`, `AnalysisResult`, `ProcessingJob`, `Playlist`
- API controllers: tracks, stems, analysis, playlists
- `DashboardLive` LiveView with track library and pipeline trigger UI
- Oban configured for background job processing
- PostgreSQL database with initial migrations

---

## [0.1.0] - 2026-02-12

### Added
- Initial Phoenix LiveView scaffold via `mix phx.new sound_forge --live`
- Project dependencies: Phoenix 1.8, Ecto, Oban, Bandit, Tailwind CSS, daisyUI
- Base router, endpoint, and application supervisor
- Development configuration with live reload

---

[Unreleased]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.3.0...HEAD
[4.3.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.12...v4.3.0
[4.2.12]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.11...v4.2.12
[4.2.11]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.10...v4.2.11
[4.2.10]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.9...v4.2.10
[4.2.9]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.8...v4.2.9
[4.2.8]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.7...v4.2.8
[4.2.7]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.6...v4.2.7
[4.2.6]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.5...v4.2.6
[4.2.5]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.4...v4.2.5
[4.2.4]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.3...v4.2.4
[4.2.3]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.2...v4.2.3
[4.2.2]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.1...v4.2.2
[4.2.1]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.2.0...v4.2.1
[4.2.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.0.1...v4.1.0
[4.0.1]: https://github.com/peguesj/sound-forge-alchemy/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v3.5.0...v4.0.0
[3.5.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v3.0.0...v3.5.0
[3.0.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/peguesj/sound-forge-alchemy/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/peguesj/sound-forge-alchemy/releases/tag/v0.1.0
