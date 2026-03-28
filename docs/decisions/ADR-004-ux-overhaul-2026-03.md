---
title: "ADR-004: UX Overhaul — Industry-Aligned Module Design"
nav_order: 4
parent: Design Decisions
---

[Home](../index.md) > [Design Decisions](index.md) > ADR-004: UX Overhaul

# ADR-004: UX Overhaul — Industry-Aligned Module Design

**Status**: Accepted
**Date**: 2026-03-18
**Author**: Jeremiah Pegues
**Scope**: All SFA modules (Dashboard, DJ, DAW, MIDI, CrateDigger, SampleLibrary, Settings)

---

## Context

Sound Forge Alchemy v4.6.0 has grown to encompass DJ mixing, DAW editing, MIDI mapping, stem separation, AI agents, and crate management. As features accumulated across multiple sprints, the UX drifted from established industry patterns. Users familiar with Traktor Pro, Serato DJ Pro, Rekordbox, and Logic Pro experience a learning curve that is not inherent to the task complexity — it is a consequence of inconsistent layout conventions.

This ADR documents the design decisions driving the v4.7+ UX overhaul, drawn from competitive analysis of the four reference applications and translated into SFA's Phoenix LiveView constraints.

### Reference Applications Analyzed

| Application | Paradigm | Primary Strength |
|-------------|----------|-----------------|
| **Traktor Pro 4** | Modular deck architecture, hardware-first | Best-in-class deck layout, FX routing |
| **Serato DJ Pro** | Performer-centric, waveform-dominant | Waveform zoom, cue workflow |
| **Rekordbox 6** | Library-first, CDJ parity | Preparation workflow, key locking |
| **Logic Pro X** | DAW/production, non-linear | Arranger, smart tempo, region-based |
| **VirtualDJ 2023** | Accessibility, feature breadth | Skin customization, AI stems |

---

## Decision 1: Deck Labeling — Letters over Numbers

### Context
SFA DJ module previously used numbers (Deck 1, Deck 2) matching Rekordbox's convention. Traktor and Serato both use letters (Deck A, Deck B, Deck C, Deck D).

### Decision
**Use letters (A, B) for 2-deck layout; (A, B, C, D) for 4-deck.** Add optional numeric alias toggle in settings for users migrating from Rekordbox/Pioneer CDJ workflow.

### Rationale
- Traktor Pro is the most common software-only DJ platform; Serato is second. Both use letters.
- Letters unambiguously map to left/right spatial position (A=left, B=right is convention across both).
- Numbers create ambiguity in 4-deck layouts (is "1" on the left or right of the 4-deck view?).
- Pioneer hardware uses numbers — the numeric alias toggle serves CDJ migration users without breaking the default.

### Implementation
```heex
<!-- deck_label/1 function component -->
<span class="deck-label deck-label-<%= @letter %>">
  Deck <%= @letter %><%= if @show_number, do: " (#{@number})", else: "" %>
</span>
```

---

## Decision 2: Volume Controls — Vertical Channel Faders with Knob Trim

### Context
SFA DJ used CSS-only horizontal sliders for channel volume. Industry standard is vertical faders with a separate trim/gain knob above.

### Decision
**Channel faders are vertical sliders (CSS transform + range input)**. A trim knob (rotary, ±6dB) sits above each fader. Master volume is also a vertical fader on the right. The crossfader remains horizontal at the bottom center.

### Rationale from Industry Analysis
| Control | Traktor | Serato | Rekordbox | SFA Target |
|---------|---------|--------|-----------|------------|
| Channel fader | Vertical | Vertical | Vertical | **Vertical** |
| Trim/gain | Rotary knob | Rotary knob | Rotary knob | **Rotary knob** |
| Master | Vertical | Vertical | Vertical | **Vertical** |
| Crossfader | Horizontal | Horizontal | Horizontal | **Horizontal** |

- Horizontal faders on channel strips are only found on budget/starter apps. Professional muscle memory is exclusively vertical for channel strips.
- The trim knob at the top of the channel strip is the gain-staging touch point — it must be visually distinct from the volume fader.

### Phoenix LiveView Constraint
Range inputs with CSS `transform: rotate(-90deg)` create layout reflow issues. Use the `phx-hook="VerticalFader"` JS hook that renders an SVG fader track and maps pointer events to a hidden `<input type="range">`.

---

## Decision 3: Crossfader Positioning and Curve Selection

### Decision
- Crossfader: **horizontally centered, full width of the mixer strip**, at the bottom of the mixer section (between the two decks, above transport controls).
- Curve modes: **linear** (default), **constant power** (+3dB at center), **sharp cut** (switch-style, used for scratching), **slow fade** (extended center region).
- Curve selector: **4-button toggle group** adjacent to the crossfader, not hidden in settings.

### Rationale
All four reference applications expose crossfader curve selection on the main mixer interface, not buried in preferences:
- Traktor: Crossfader curve selector in mixer strip header
- Serato: Crossfader contour knob physically next to the crossfader
- Rekordbox: 3-mode toggle (Linear/Cut/Through)
- VirtualDJ: 5-curve selector in the crossfader section

Hiding curve selection in a settings modal was a v4.x regression. DJs switch curves mid-set (scratching vs. smooth mixing requires different curves).

---

## Decision 4: EQ Knob Placement — 3-Band Per Channel Strip

### Decision
Each channel strip carries **three EQ knobs in vertical order: HI → MID → LO**, positioned between the trim knob and the channel fader. Kill buttons (one per band) sit to the right of each knob.

### Rationale
```
Channel Strip Layout (top to bottom):
┌─────────────────┐
│  [GAIN/TRIM]    │  rotary, ±6dB
│  [HI]  [hi▼]   │  knob + kill
│  [MID] [md▼]   │  knob + kill
│  [LO]  [lo▼]   │  knob + kill
│  ┃ FADER ┃      │  vertical slider
│  [CUE]          │  headphone cue toggle
└─────────────────┘
```

This arrangement matches Traktor, Serato, and Pioneer DJM hardware — the three dominant professional mixer form factors. Rekordbox uses identical placement for CDJ parity.

### Kill Button Behavior
- Single click: **isolate kill** (cut that band, latch off until re-clicked)
- Double-click: **temporary kill** (hold to cut, release to restore) — matches Traktor's `momentary` mode
- Visual state: band kill buttons use `accent-error` color when active, `accent-neutral` when inactive

---

## Decision 5: Stem/Channel Controls — Individual Stem Faders per Track

### Decision
When a track has been stem-separated, the channel strip expands to show **4 mini faders (Vocals, Drums, Bass, Other)** below the main channel fader. These are controlled independently via separate WebAudio GainNodes.

### Rationale
VirtualDJ 2023 was first to market with stem faders in the main channel strip (their "VideoStem" concept). Traktor followed in Stem Tracks. SFA's local Demucs separation is a core differentiator — the stem controls must be first-class in the mixer, not hidden in a side panel.

### Layout
```
[ CHANNEL FADER ]
──── stems (if loaded) ────
[V] [D] [B] [O]  mini faders
 V   D   B   O   mini labels
```

Mini faders use proportional height (40% of main fader height). They collapse to mute buttons when the user presses a stem icon twice (Traktor-style stem isolate).

---

## Decision 6: Hot Cue Pad Layout — 8 Pads in 2×4 Grid, Numbered

### Decision
**8 hot cue pads arranged in a 2-row × 4-column grid**, numbered 1–8 left-to-right, top-to-bottom (Serato convention). Pads are color-coded by cue type:

| Color | Type |
|-------|------|
| Emerald | Standard hot cue (point) |
| Blue | Loop cue (saved loop) |
| Amber | Roll cue (auto-loop while held) |
| Red | Splice/slice marker |
| Purple | AI-detected structural marker |

### Rationale
- Serato DJ: 8 pads, 2×4, numbered 1–8. Market-leading pad layout convention.
- Traktor: 8 pads, 2×4, color-coded by mode (but mode is selected globally)
- Pioneer Nexus 2 hardware: 8 pads, 2×4

SFA v4.x used 4 pads per row in a 1×4 horizontal strip — this does not match any hardware or software reference and wastes vertical space.

---

## Decision 7: Loop Deck Features

### Decision
Loop deck controls are placed **inside each deck**, not in a separate panel. Controls:

```
[ ◄ LOOP IN ] [ LOOP OUT ► ]
[ ½x ] [  loop size  ] [ 2x ]
[ AUTO LOOP ] [ LOOP ACTIVE ]
[ LOOP ROLL ] [     BPM     ]
```

Loop size selection uses a **beatgrid selector** (1/4, 1/2, 1, 2, 4, 8, 16, 32 beats) shown as a horizontal button group, not a numeric input.

### Rationale
Rekordbox and Traktor both embed loop controls directly in the deck section — they are never separate panels. Loop size as a beatgrid button group (not a text input) matches all hardware controllers and both reference apps.

---

## Decision 8: AI-Assisted Cue Detection UI

### Decision
After `AutoCueWorker` processes a track, the waveform displays cue markers with **type-coded colors and icon overlays**:

| Cue Type | Icon | Color |
|----------|------|-------|
| Drop (energy increase ≥35%) | ▼ | Red |
| Breakdown (energy decrease ≥30%) | ▲ | Blue |
| Build-up (rising energy, 8+ bars) | ↑ | Amber |
| Intro (first 16 bars) | I | Green |
| Outro (last 16 bars) | O | Purple |

The AI cue overlay has a **toggle button** in the waveform toolbar (eye icon). When visible, a **cue density badge** shows "26 AI cues" in the deck header. Clicking a cue marker zooms the waveform to that position and shows a tooltip with confidence score.

### Rationale
No current reference application exposes ML-generated structural cues with confidence scores. This is a SFA-exclusive feature and should be visually prominent as a differentiator — not hidden behind multiple settings menus.

---

## Decision 9: Grid Overlay Modes

### Decision
The waveform toolbar provides a **3-mode grid overlay toggle**:

| Mode | Display | Use Case |
|------|---------|----------|
| Bar | Bold line every 4 beats | Structural editing, mix planning |
| Beat | Line every beat | Standard DJ beat matching |
| Sub | Lines at 1/4 beat | Scratch, micro-timing, pitch correction |

Active mode is highlighted in the toolbar. Grid color and opacity are theme-controlled (defaults: `hsl(270, 60%, 60%)` at 40% opacity).

### Rationale
Traktor Pro 4: bar/beat/sub modes in waveform toolbar.
Rekordbox 6: beat/bar toggle.
Logic Pro: bar/beat/division/ticks in the ruler.

All three applications provide at minimum a bar/beat toggle. Sub-beat (1/4 note) grid is unique to production-level tools and is needed for SFA's audio warping and MIDI extraction workflows.

---

## Decision 10: MIDI Learn Workflow

### Decision
MIDI learn follows a **3-step inline pattern**:

```
Step 1: Click [LEARN] button adjacent to any mapped control
        → Button pulses amber, control enters learn mode
        → Status bar shows "Waiting for MIDI input..."

Step 2: Move/press any control on connected hardware
        → CC/Note/channel captured in real-time
        → Status updates: "CC 118, Ch 0 detected — MPC Live II"

Step 3: [SAVE] or [CANCEL] confirmation inline
        → Saved: button turns emerald, mapping persists to DB
        → Cancel: button returns to default state
```

### Rationale
- Current SFA v4.x requires navigating to `/midi` page to set up mappings — this breaks DJs' mental model (hardware control should be learnable from wherever the control appears)
- Traktor: click label → MIDI learn → move knob → auto-save (2-step, no confirmation)
- Serato: right-click any control → "MIDI Map" → move hardware

SFA uses a 3-step pattern (with confirmation step) because Elixir PubSub transport introduces ~20ms latency on detection — the confirmation step prevents false captures from nearby controllers.

---

## Module-Specific Guidelines

### Dashboard (Track Library)
- Sticky header: always visible with nav tabs (Library, DJ, DAW, MIDI, Pads, CrateDigger)
- Track rows: album art (32×32), title, artist, BPM, key, duration, pipeline status dot
- Bulk select: single "All" checkbox, immediate cross-page selection (no two-step)
- Overflow: single scrollable container, no nested `overflow-y-auto`

### DJ Module
- Fixed 2-deck layout at top, mixer strip center
- Waveforms below decks (full width, 80px height per deck)
- Cue pads below waveforms
- Loop controls embedded in each deck
- Transport controls at absolute bottom

### DAW Module
- Piano roll primary view (horizontal time axis, vertical pitch axis)
- Arrangement mode toggle (vertical track stack, horizontal time)
- MIDI/Audio lane parity (same track height, same transport controls)

### MIDI Module
- Single-page overview: connected devices, current mappings, learn controls per mapping
- Device selector at top (physical device → virtual port → software surface)
- Mapping table: action, device, CC/Note, channel, [LEARN] [DELETE]

### CrateDigger
- Full-width layout (no sidebar when active)
- Spotify import panel: search + playlist URL
- Track list: album art, title, artist, stems config badge, WhoSampled indicator
- Slide panel: WhoSampled history, sample chain, stem config override

---

## Implementation Priority

| Priority | Component | Wave |
|----------|-----------|------|
| P0 | Sticky header always visible (missing on CrateDigger) | Wave 1 |
| P0 | Remove nested `overflow-y-auto` from track library | Wave 1 (done) |
| P1 | Vertical channel faders (CSS rotation + `VerticalFader` hook) | Wave 2 |
| P1 | Crossfader curve selector inline | Wave 2 |
| P1 | Hot cue 2×4 grid, color-coded | Wave 2 |
| P2 | EQ kill buttons per band | Wave 2 |
| P2 | Stem mini-faders in channel strip | Wave 3 |
| P2 | Beatgrid loop size selector | Wave 3 |
| P3 | Inline MIDI learn on control surfaces | Wave 3 |
| P3 | AI cue overlay toggle in waveform toolbar | Wave 3 |

---

## Rejected Alternatives

### Rejected: Numbered Decks
Rejected because Traktor (dominant software DJ) and Serato (second most used) both use letters. Numbers-only creates confusion in 4-deck layouts.

### Rejected: Horizontal Channel Faders
Rejected because no professional mixer uses horizontal channel faders. This was a stop-gap from early web UI constraints (CSS `input[type="range"]` defaults horizontal). The `VerticalFader` hook resolves the constraint.

### Rejected: Modal Crossfader Curve Settings
Rejected because all four reference applications expose curve selection on the main interface. Mid-set mode changes are a normal DJ operation.

### Rejected: Separate Loop Panel
Rejected because loop controls are deck-specific — separating them into a panel breaks the spatial model where left deck controls are left, right deck controls are right.

---

## References

- Traktor Pro 4 Manual §4.2 (Mixer Section), §5.1 (Deck Controls)
- Serato DJ Pro 3.0 Manual §3 (Main View), §5 (Hot Cues)
- Rekordbox 6 Software Manual §4 (Performance View)
- VirtualDJ 2023 Reference Manual §2.1 (Main Screen)
- Logic Pro 10.8 User Guide §7 (Smart Tempo), §24 (Piano Roll)
- SFA CHANGELOG.md v4.6.0 (MIDI/DJ architecture)
- SFA ADR-001 (Framework Choice — Phoenix LiveView)

---

[← ADR-003](ADR-003-job-architecture.md) | [Back to Design Decisions →](index.md)
