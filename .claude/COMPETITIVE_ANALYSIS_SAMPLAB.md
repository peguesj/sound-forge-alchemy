# SFA vs Samplab -- Competitive Gap Analysis
**Date**: 2026-03-05
**Samplab Version**: 2.4.6 (Electron, macOS 12+, Xcode 15.4)
**SFA Version**: v4.4.0 (Phoenix/Elixir, deployed Azure)

---

## Executive Summary

Samplab is a **focused, polished audio-to-MIDI and note-editing tool** targeting producers who need to repitch/retune samples, with an expanding product ecosystem (Resynthesizer, TextToSample). SFA is a **broader music production platform** (stems, analysis, DJ, DAW, MIDI, multi-LLM agents, 707 tests). Samplab wins on **single-task UX polish, DAW integration, and product ecosystem breadth**; SFA wins on **feature depth, local processing, and server-side intelligence**. The critical gap is that Samplab ships as a **native VST3/AU plugin** that lives inside the DAW, while SFA is a web app that lives outside it.

**Samplab Product Ecosystem** (3 products):
1. **Samplab Editor** -- polyphonic note editing, stem separation, audio-to-MIDI, chord detection (cloud AI)
2. **Resynthesizer** -- AI-powered sample-to-synth instrument (on-device AI, EUR 9.99/mo or EUR 77.99 perpetual)
3. **TextToSample** -- text-to-audio generation via Meta's MusicGen (free, runs locally)

---

## Architecture Comparison

| Dimension | Samplab | SFA |
|---|---|---|
| **Platform** | Electron desktop + VST3/AU plugin | Phoenix LiveView web app |
| **Frontend** | React (minified), single-page | HEEx templates, LiveView, JS hooks |
| **Backend** | Cloud API (samplab.com) | Elixir/OTP + PostgreSQL + Oban |
| **Audio Engine** | Cloud-only (no local ML models) | Local Demucs + cloud lalal.ai |
| **Native Binary** | ffmpeg only (458MB total) | Demucs + librosa + spotdl (4.8GB Docker) |
| **Distribution** | Direct + MuseHub marketplace | Azure Container Apps (web) |
| **Auth** | Device fingerprinting + store tokens | Phoenix auth + Spotify OAuth |
| **Plugin Format** | VST3 + AU (inside DAW) | None (browser only) |
| **Localization** | 57 languages | English only |

---

## Feature-by-Feature Gap Analysis

### SAMPLAB HAS, SFA LACKS (Critical Gaps)

| Feature | Samplab | SFA Status | Priority |
|---|---|---|---|
| **VST3/AU Plugin** | Ships plugin, in-DAW workflow | No plugin | P0 -- existential |
| **Note-level editing** | Edit individual notes in polyphonic audio (pitch, timing, duration, volume, pan per note) | Not implemented | P0 |
| **Audio-to-MIDI** | Polyphonic, multi-track MIDI output per instrument | Not implemented | P1 |
| **Chord detection** | Automatic detection + editing + MIDI export of progressions | Not implemented | P1 |
| **Piano roll editor** | Visual note editing UI | Not implemented | P1 |
| **Audio warping** | Tempo/key matching, auto-sync to DAW project | Not implemented | P1 |
| **Resynthesizer** | AI sample-to-synth: one-shots become playable instruments across octaves, dual-layer morphing, on-device AI | Not implemented | P1 |
| **TextToSample** | Text-to-audio generation (Meta MusicGen, runs locally, free) | LLM agents exist but no audio generation | P2 |
| **MuseHub distribution** | Listed on MuseHub marketplace (Steinberg ecosystem) | No marketplace presence | P2 |
| **Drag & drop export** | Drag stems/MIDI into DAW | Web download only | P2 |
| **Plugin auto-update** | Squirrel auto-updater + `updatePlugin()` with sudo escalation | Manual redeploy | P3 |
| **57-language i18n** | Full localization | English only | P3 |
| **SQLite local DB** | Local persistence via SQLite + electron-store | Server-side PostgreSQL only | P3 |

### SFA HAS, SAMPLAB LACKS (SFA Advantages)

| Feature | SFA | Samplab Status |
|---|---|---|
| **Local stem separation** | Demucs (htdemucs, htdemucs_ft, htdemucs_6s, mdx_extra) -- works offline | Cloud-only, no model choice, requires internet |
| **Multiple separation engines** | Demucs + lalal.ai (11 stem types: vocals, drums, bass, piano, electric/acoustic guitar, synth, strings, winds, noise, midside) | Single cloud engine, 4 stems only |
| **Spotify integration** | OAuth, metadata fetch, SpotDL download, Spotify SDK playback | No Spotify integration |
| **Audio analysis** | 5 D3.js visualizations (radar, chroma, beats, MFCC, spectral) + Python librosa pipeline | Basic BPM/key/chord only |
| **DJ mode** | Dual decks, crossfader, BPM sync, hot cue points (1-8), auto-cue detection, per-stem loops, stem mixer (volume/pan/solo/mute) | No DJ features |
| **DAW tab** | Timeline preview, 10 non-destructive edit operations (crop, gain, fade in/out, pitch shift, time stretch, reverse, EQ, compress, distortion), WAV/MP3/FLAC export | No DAW-like features (IS a plugin) |
| **MIDI hardware** | DeviceManager (USB + network), Dispatcher (GenServer), Learn flow, MPC preset profiles, MIDI monitor heatmap | No MIDI hardware support |
| **OSC integration** | UDP server/client, MIDI-OSC bridge, TouchOSC layout (iPad/iPhone control surface) | No OSC |
| **Multi-LLM agents** | 9 providers (Anthropic, OpenAI, Azure, Gemini, Ollama, LM Studio, LiteLLM, Custom, System), 6 specialist agents (track analysis, mix planning, stem intelligence, cue points, mastering, library), intelligent router with fallback | No AI assistants |
| **Role-based access** | 6-tier hierarchy (user -> platform_admin), audit logging | Simple free/premium |
| **Admin dashboard** | Users, jobs, system, analytics, audit, LLM health tabs | No admin |
| **Practice integration** | Melodics import, practice stats, AI recommendations | No practice features |
| **Background jobs** | 14 Oban workers with monitoring, retry, reconciliation | Polling-based (sleep 1s, 500 retries) |
| **Real-time updates** | Phoenix PubSub, LiveView (server push) | HTTP polling (Axios) |
| **Self-hostable** | Docker/Azure Container Apps | SaaS only (Electron app + cloud API) |
| **Audio file management** | Full library with search, sort, pagination, playlists, albums, batch operations | Session-based (no persistent library) |
| **Voice effects** | Voice change, voice clean, demuser (via lalal.ai workers) | No voice effects |
| **Test coverage** | 707 tests, 0 failures | Unknown (closed source) |
| **Documentation** | 41-page docs site (architecture, guides, API, changelog) | Minimal (website FAQs) |
| **Sampler** | Chromatic pad banks (4x4), per-pad stem assignment, MIDI mapping | No sampler |
| **API encryption** | Cloak/AES-GCM vault for API keys | Device fingerprinting |
| **Rate limiting** | Browser (120/min), API (60/min), Heavy (10/min) | Unknown |

### BOTH HAVE (Parity)

| Feature | Samplab | SFA |
|---|---|---|
| Stem separation | Cloud API | Local Demucs + cloud lalal.ai |
| File format support | WAV import/export, ffmpeg conversion | WAV, MP3, FLAC via ffmpeg/spotdl |
| Dark theme | Default | daisyUI dark theme |
| macOS + cross-platform | Electron (Mac/Win) | Web (any browser) |

---

## Pricing Comparison

| Tier | Samplab | SFA |
|---|---|---|
| **Free** | 10s mono audio, basic editing, TextToSample (full, free) | Full features, local Demucs |
| **Premium** | $7.99/mo ($95.88/yr) -- unlimited length, stereo, premium note controls | No paid tier yet |
| **Complete** | EUR 9.99/mo -- Premium + Resynthesizer | N/A |
| **Resynthesizer Perpetual** | EUR 77.99 intro / EUR 129.99 regular (one-time, 3 devices) | N/A |

**Analysis**: Samplab's free tier is deliberately crippled (10 seconds, mono only) but TextToSample is genuinely free. No one-time purchase for core editor (subscription-only, user friction). SFA gives away the farm with no monetization. SFA needs a pricing tier to be sustainable.

**Endorsements**: KSHMR, ill.Gates (EDM producer community). Market positioning as "free Melodyne alternative" -- undercuts Melodyne ($99-$699) and RipX ($99).

---

## Technical Architecture Deep Dive (from binary analysis)

### Samplab Internals (from ASAR extraction + binary analysis)
- **Electron 28+** (Chromium-based, Squirrel.Windows auto-updater)
- **React production** build, single renderer.js (1.4MB minified)
- **Axios** HTTP client for cloud API
- **SQLite** local database + **electron-store** key-value persistence (`getFromStore`/`setOnStore`)
- **Device fingerprinting** (`getUniqueDeviceId`) for license enforcement
- **MuseHub integration** (`isMuseHubBuild`, `getMuseHubUuid`) for Steinberg marketplace distribution
- **Plugin lifecycle**: `downloadPlugin()`, `updatePlugin({sudoIfNecessary})`, `installPluginWindows()`
- **Update feed**: `https://release.samplab.com/update/${platform}/${version}`
- **Download server**: `https://download.samplab.com/bin/${platform}/` (includes Windows `sndfile.dll`)
- **Cloud processing** with polling (sleep 1s, up to 500 attempts = ~8 min timeout)
- **No local ML inference** for core editor -- 100% cloud-dependent (Resynthesizer is on-device, TextToSample uses local MusicGen)
- **ffmpeg** bundled (universal binary, arm64 + x86_64) for audio format conversion
- **IPC channels** (22 total): `convertAudio`, `warpAudio`, `downloadPlugin`, `updatePlugin`, `installPluginWindows`, `getPaths`, `getFromStore`, `setOnStore`, `openDialog`, `saveDialog`, `showMessage`, `close`, `minimizeWindow`, `setOrToggleMaximizeWindow`, `isWindowMaximized`, `isWindowFullScreen`, `setExitMessage`, `quit`, `reload`, `restart`, `restartAndInstallUpdate`, `isDev`, `isMuseHubBuild`, `getMuseHubUuid`, `getUniqueDeviceId`, `onDragStart`
- **Dev server**: `localhost:1212` (default), `localhost:3000` (alternative)
- **Entitlements**: JIT, unsigned executable memory, debugger -- typical for Electron + native code
- **Cross-platform**: macOS (darwin) + Windows (win32) + Linux (limited)

### SFA Internals
- **Phoenix/OTP** with supervision trees, fault tolerance
- **Oban** job queues (download:3, processing:2, analysis:2 concurrency)
- **Erlang Ports** for Python (Demucs, librosa) -- true local processing
- **PubSub** for real-time UI updates (no polling)
- **PostgreSQL** as source of truth (survives crashes)
- **707 tests**, 0 failures

---

## User Sentiment (from reviews, Reddit, forums)

**Positive:**
- "Pure magic -- no other program lets you tweak the notes of polyphonic audio while actually sounding good" (KSHMR)
- UI praised as "friendly to the point of sparseness" -- zero confusion
- Audio-to-MIDI widely called "absolute game changer"
- Good results on vocals, mono-synth samples, and lead sounds

**Negative:**
- Severe formant-like artifacts on densely-textured instruments (acoustic guitar, complex timbres) -- "almost unusable"
- Internet requirement for initial analysis is a pain point (cloud dependency)
- Subscription-only model (no perpetual license for core editor) frustrates users
- At least one report of difficulty unsubscribing (Dec 2025)
- Polyphonic accuracy trails Melodyne for professional precision work
- "Far from a magic bullet" -- technology has real limits on complex material

**Overall**: Positive but realistic. Best for beat makers and sample flippers, not mastering engineers. The cloud dependency and subscription-only model are exploitable weaknesses.

---

## Strategic Gaps (Ranked by Impact)

### P0 -- Existential Threats
1. **No DAW plugin**: Samplab lives INSIDE the DAW. SFA lives in a browser tab. For producers, context-switching to a browser is a deal-breaker. SFA needs at minimum a **CLAP/VST3/AU bridge** or **Ableton Link** integration.
2. **No note-level editing**: Samplab's core value prop is editing individual notes in polyphonic audio. SFA has stem separation but not note manipulation. This is the key differentiator that makes Samplab "magical" to producers.

### P1 -- Competitive Parity
3. **Audio-to-MIDI conversion**: Standard feature in the space. SFA has MIDI hardware support but no audio-to-MIDI pipeline.
4. **Chord detection**: Complementary to audio analysis. SFA has spectral/chroma analysis (the data is there) but no chord extraction UI.
5. **Piano roll / note editor**: Visual editing paradigm that producers expect.
6. **Audio warping / time-stretching**: Essential for sample manipulation.

### P2 -- Market Positioning
7. **Marketplace presence**: Samplab is on MuseHub. SFA has no distribution channel for producers.
8. **Drag-and-drop to DAW**: Standard workflow. SFA requires download + manual import.
9. **Freemium monetization**: SFA needs a pricing tier to be sustainable.

### P3 -- Nice to Have
10. **i18n**: 57 languages gives Samplab global reach.
11. **Auto-update**: Plugin self-updates without user intervention.
12. **Desktop app**: Electron wrapper for offline use.

---

## Recommended Action Plan

### Phase 1: Bridge the DAW Gap (P0)
- Investigate **CLAP plugin SDK** (open source, modern) for an SFA bridge plugin
- Alternatively: **Ableton Link** integration via `abletonlink` Elixir NIF
- MVP: Plugin that sends audio to SFA web app and receives stems back

### Phase 2: Note-Level Features (P0-P1)
- **Audio-to-MIDI**: Leverage existing librosa analysis + add `basic-pitch` (Spotify's open-source audio-to-MIDI)
- **Chord detection**: Add `madmom` or `librosa.feature.chroma` -> chord mapping
- **Piano roll UI**: LiveView + Canvas/WebGL hook for note visualization

### Phase 3: Monetization (P2)
- Define free tier limits (e.g., 3 tracks/day, 2-stem separation)
- Premium: unlimited tracks, all Demucs models, lalal.ai access, priority processing
- Enterprise: self-hosted, API access, bulk processing

### Phase 4: Distribution (P2-P3)
- **Electron wrapper**: Package SFA web app in Electron for offline use
- **MuseHub listing**: Apply for marketplace inclusion
- **i18n**: Start with top 5 languages (Spanish, Portuguese, Japanese, German, French)

---

## Key Insight

Samplab is a **scalpel** -- one thing done extremely well (note editing in polyphonic audio). SFA is a **Swiss Army knife** -- many tools, broader capability. The market wants both. The winning strategy is NOT to out-Samplab Samplab on note editing, but to:

1. **Close the DAW integration gap** (plugin bridge)
2. **Add audio-to-MIDI** (leverage existing analysis pipeline)
3. **Position SFA as the all-in-one production companion** that Samplab isn't
4. **Keep the multi-engine advantage** (local Demucs + cloud lalal.ai vs Samplab's cloud-only)

Samplab's cloud-only dependency is a vulnerability. When their API is down, users can't work. SFA's local processing is a moat.

---

## Sources

- [Samplab Homepage](https://samplab.com/)
- [Samplab Features](https://samplab.com/features)
- [Samplab Resynthesizer](https://samplab.com/resynthesizer)
- [Samplab on MuseHub](https://www.musehub.com/partner/samplab)
- [Samplab Audio-to-MIDI Guide (Afroplug)](https://afroplug.com/samplab/)
- [Samplab Review (AI Chief)](https://aichief.com/ai-audio-tools/samplab/)
- [Samplab Review (Magnetic Magazine)](https://magneticmag.com/2023/01/samplab-2-review/)
- [Samplab Resynthesizer (Bedroom Producers Blog)](https://bedroomproducersblog.com/2025/06/18/samplab-resynthesizer/)
- [Best Stem Separation Tools 2026 (MusicRadar)](https://www.musicradar.com/music-tech/i-tested-11-of-the-best-stem-separation-tools-and-you-might-already-have-the-winner-in-your-daw)
- [Best AI Stem Splitter Tools 2026 (AI Music Preneur)](https://www.aimusicpreneur.com/ai-tools-news/the-best-ai-stem-separation-tools-ai-stem-splitter/)
- [TextToSample (MusicRadar)](https://www.musicradar.com/news/text-to-sample-samplab-meta-ai)
- [KVR Audio Product Page](https://www.kvraudio.com/product/samplab-by-samplab)
- Binary analysis: `/Applications/Samplab.app` ASAR extracted to `/tmp/samplab-extracted/`
- SFA codebase analysis: `/Users/jeremiah/Developer/sfa` (707 tests, v4.4.0)
