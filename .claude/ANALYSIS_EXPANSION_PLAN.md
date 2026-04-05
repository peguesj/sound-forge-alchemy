# Audio Analysis Expansion Plan: Structural Segmentation, Loop Detection, and Arrangement Markers

**Date**: 2026-02-24
**Status**: Research & Planning (PRD)
**Scope**: Expand the librosa-based audio analysis pipeline to identify song structure, optimal loop points, and arrangement markers for DJ/DAW integration.

---

## 1. Current State Assessment

### 1.1 Python Analyzer (`priv/python/analyzer.py`)

The analyzer extracts six feature categories via librosa:

| Feature | Function | Output |
|---------|----------|--------|
| **tempo** | `librosa.beat.beat_track` | BPM (float), beat frame times (list), beat count |
| **key** | Chroma correlation with major/minor profiles | Key name (e.g., "C# minor"), confidence, pitch class, mode |
| **energy** | `librosa.feature.rms`, `zero_crossing_rate` | Mean/variance/min/max RMS, ZCR |
| **spectral** | Centroid, rolloff, bandwidth, contrast, flatness | Mean values for each spectral feature |
| **mfcc** | `librosa.feature.mfcc` (13 coefficients) | Mean and variance per coefficient |
| **chroma** | `chroma_stft`, `chroma_cqt`, `chroma_cens` | Mean values per pitch class (12 values each) |

Key observations:
- All features are **globally averaged** across the entire track. There is no time-series segmentation.
- Beat tracking returns individual beat frame times but they are stored flat in the features JSON.
- The chroma features are averaged over time -- no temporal chroma change detection.
- No onset detection, no segment boundaries, no structural analysis.
- The `features` CLI argument accepts: `tempo`, `key`, `energy`, `spectral`, `mfcc`, `chroma`, `all`.

### 1.2 Schema (`analysis_results` table)

```
analysis_results
  id:                 binary_id (PK)
  track_id:           binary_id (FK -> tracks)
  analysis_job_id:    binary_id (FK -> analysis_jobs)
  tempo:              float
  key:                string
  energy:             float
  spectral_centroid:  float
  spectral_rolloff:   float
  zero_crossing_rate: float
  features:           map (JSONB) -- all extracted features as flat/nested JSON
  inserted_at, updated_at
```

The `features` map currently contains whatever the Python analyzer returns. It is a catch-all JSON column. The DJ tab component reads `features["beat_times"]` (which does not appear to exist -- the Python analyzer stores beats under the key `"beats"`). The dashboard reads `features["beats"]`, `features["chroma"]`, `features["mfcc"]`, `features["spectral_contrast"]`.

### 1.3 Data Flow: Analyzer to Frontend

1. **AnalysisController** or pipeline creates an `AnalysisJob` record (status: :queued).
2. **AnalysisWorker** (Oban, queue: :analysis) picks up the job, starts `AnalyzerPort`.
3. **AnalyzerPort** (GenServer) spawns a Python process via Erlang Port, passes audio path + features list.
4. Python `analyzer.py` runs, outputs JSON to stdout. Port collects buffer, parses on exit.
5. Worker creates `AnalysisResult` record with top-level fields (tempo, key, energy, spectral_centroid, spectral_rolloff, zero_crossing_rate) and the full results map in `features`.
6. **Dashboard LiveView** loads `analysis_results` on track selection, passes data to D3 hooks via `data-*` attributes with `Jason.encode!`.
7. **DJ Tab Component** extracts `tempo` and `beat_times` from analysis results when loading a track to a deck, passes to the DjDeck JS hook for beat grid rendering and loop quantization.

### 1.4 DJ Loop Controls (Current)

The DJ deck hook (`assets/js/hooks/dj_deck.js`) supports:
- **Manual loop in/out**: User sets loop start/end at current playback position, quantized to beats using `quantize_to_beat()` (simple BPM-based calculation, not beat-grid-aligned).
- **Beat-sized loops**: 1/4, 1/2, 1, 2, 4, 8 beat buttons that calculate loop length from BPM.
- **Loop region visualization**: WaveSurfer RegionsPlugin renders colored loop overlay on waveform.
- **Beat grid rendering**: Beat times from analysis rendered as vertical markers on waveform.
- **Cue points**: User-created hot cues stored in `cue_points` table with position_ms, label, color, cue_type.

Limitations:
- No awareness of song structure (cannot snap to chorus, drop, etc.).
- Loop quantization uses simple BPM math, not actual beat positions from analysis.
- No auto-suggested loop points based on musical coherence.
- No visual indication of song sections on the waveform.

### 1.5 DAW Editor (Current)

The DAW tab (`daw_tab_component.ex`, `daw_editor.js`) provides:
- Per-stem WaveSurfer waveforms with region-based operations (crop, trim, fade in/out, split, gain).
- Operations stored in `edit_operations` table.
- No structural awareness -- operations are positioned manually by the user.
- No beat-grid or bar-grid snapping for operations.

### 1.6 D3 Visualization Hooks (Current)

| Hook | Visualization | Data Source |
|------|--------------|-------------|
| **AnalysisRadar** | Spider chart: 6 axes (tempo, energy, brightness, richness, ZCR, flatness) | `features` top-level fields |
| **AnalysisChroma** | Circular pitch class wheel (12 segments) | `features["chroma"]` |
| **AnalysisBeats** | Horizontal SVG with vertical beat markers, color-coded by regularity | `features["beats"]` |
| **AnalysisMFCC** | 13 horizontal bars with variance error bars | `features["mfcc"]` |
| **AnalysisSpectral** | 7-band spectral contrast heatmap | `features["spectral_contrast"]` |

---

## 2. Proposed New Analysis Features

### 2.1 Structural Segmentation

**Goal**: Identify the high-level song structure -- intro, verse, pre-chorus, chorus, bridge, drop, breakdown, outro, and any repeated sections.

**librosa capabilities**:
- `librosa.segment.agglomerative()` -- Performs bottom-up agglomerative clustering on feature matrices to identify segment boundaries.
- `librosa.segment.recurrence_matrix()` -- Computes a self-similarity matrix showing which parts of a song sound similar to each other.
- `librosa.feature.tempogram()` -- Time-varying tempo analysis that can detect tempo changes marking structural boundaries.
- `librosa.onset.onset_detect()` / `onset_strength()` -- Onset detection for transient boundaries.
- Novelty-based segmentation: Compute a feature matrix (chroma, MFCC, spectral) over time, then detect novelty peaks (checkerboard kernel on self-similarity matrix) to find section boundaries.

**Proposed algorithm pipeline**:

```
1. Compute features over time (windowed, not globally averaged):
   - Chroma (CQT) at hop_length=512
   - MFCC (13 coefficients) at hop_length=512
   - Spectral contrast at hop_length=512
   - RMS energy over time

2. Build self-similarity matrix using chroma features
   (librosa.segment.recurrence_matrix with cosine affinity)

3. Detect segment boundaries via novelty curve:
   - Apply checkerboard kernel convolution to self-similarity matrix
   - Peak-pick the novelty curve to find boundary frames
   - Convert frames to timestamps

4. Cluster segments by similarity:
   - Extract mean feature vector per segment
   - Agglomerative clustering to group similar segments
   - Label clusters as structural types using heuristics:
     a. First segment = "intro"
     b. Last segment = "outro"
     c. Recurring high-energy segments = "chorus" / "drop"
     d. Recurring lower-energy segments = "verse"
     e. Transitional segments = "bridge" / "pre-chorus" / "breakdown"
     f. Energy build-up preceding chorus/drop = "build-up"

5. Output segment list with:
   - section_type: string (intro, verse, pre_chorus, chorus, bridge, drop, breakdown, build_up, outro, other)
   - start_time: float (seconds)
   - end_time: float (seconds)
   - confidence: float (0.0-1.0)
   - label: string (e.g., "Chorus A", "Verse 1")
   - energy_profile: float (mean energy for this section)
   - repetition_group: int (which cluster this segment belongs to, for identifying repeated sections)
```

### 2.2 Optimal Loop Point Detection

**Goal**: Identify musically coherent loop boundaries that sound natural when looped, aligned to bars/beats.

**Algorithm**:

```
1. Use beat tracking to establish bar grid:
   - Beat times from librosa.beat.beat_track
   - Estimate time signature (4/4 assumed default, detect via beat strength pattern)
   - Compute bar boundaries (every 4 beats for 4/4)

2. For each bar boundary pair (1 bar, 2 bars, 4 bars, 8 bars, 16 bars):
   - Extract chroma feature at loop start and loop end
   - Compute similarity score (cosine similarity of chroma vectors)
   - Compute RMS energy match (difference in energy levels at boundaries)
   - Compute spectral similarity at boundaries
   - Weight: chroma_similarity * 0.5 + energy_match * 0.3 + spectral_match * 0.2

3. Rank all candidate loop points by composite score.

4. For each structural segment, identify the best loop point within it:
   - "Best 4-bar loop in Chorus 1"
   - "Best 8-bar loop spanning Verse 2"

5. Output loop point list with:
   - loop_start_ms: integer
   - loop_end_ms: integer
   - loop_beats: integer (length in beats)
   - loop_bars: integer (length in bars)
   - quality_score: float (0.0-1.0, how smooth the loop sounds)
   - section_label: string (which structural section this loop is in)
   - recommended: boolean (top 3-5 loops flagged as recommended)
   - bar_aligned: boolean (whether start/end are on bar boundaries)
```

### 2.3 Arrangement Markers

**Goal**: Identify key musical moments -- key changes, energy transitions, build-ups, drops, and dynamic shifts.

**Algorithm**:

```
1. Key change detection:
   - Compute windowed chroma (e.g., 4-second windows with 50% overlap)
   - For each window, determine local key using the same major/minor correlation method
   - Mark positions where detected key changes (with hysteresis to avoid flicker)

2. Energy transition detection:
   - Compute windowed RMS energy curve
   - Detect significant energy ramps (gradient > threshold over N seconds)
   - Classify: "energy_rise" (build-up), "energy_drop" (breakdown/drop), "energy_plateau"

3. Drop detection:
   - Look for pattern: sustained energy rise followed by brief silence/dip followed by energy spike
   - Mark the energy spike as "drop"

4. Build-up detection:
   - Rising energy + increasing spectral bandwidth + potentially rising tempo/onset density
   - Mark the start of the ramp as "build_up_start" and peak as "build_up_end"

5. Onset density analysis:
   - Compute onset strength envelope
   - Detect regions of high onset density (busy sections) vs low (sparse sections)

6. Output marker list with:
   - marker_type: string (key_change, energy_rise, energy_drop, drop, build_up, onset_density_shift)
   - position_ms: integer (timestamp)
   - position_end_ms: integer (optional, for ranged markers)
   - description: string (e.g., "Key change: C major -> A minor")
   - intensity: float (0.0-1.0, strength of the transition)
   - metadata: map (key-specific data, e.g., {from_key: "C major", to_key: "A minor"})
```

---

## 3. Schema Changes

### 3.1 Approach: Extend the `features` JSON Map

Rather than creating new database tables, the structural analysis data will be stored within the existing `features` JSONB column on `analysis_results`. This preserves backward compatibility and avoids migration complexity. The JSON structure will be extended with new top-level keys.

**Updated `features` map structure**:

```json
{
  "tempo": 128.0,
  "beats": { "times": [...], "count": 256 },
  "key": { "key": "C# minor", "confidence": 0.82, ... },
  "energy": { "energy": 0.45, "energy_variance": 0.02, ... },
  "spectral": { ... },
  "mfcc": { "means": [...], "variances": [...] },
  "chroma": { "stft": [...], "cqt": [...], "cens": [...] },

  "structure": {
    "segments": [
      {
        "section_type": "intro",
        "start_time": 0.0,
        "end_time": 15.2,
        "confidence": 0.91,
        "label": "Intro",
        "energy_profile": 0.22,
        "repetition_group": 0
      },
      {
        "section_type": "verse",
        "start_time": 15.2,
        "end_time": 45.6,
        "confidence": 0.85,
        "label": "Verse 1",
        "energy_profile": 0.38,
        "repetition_group": 1
      },
      ...
    ],
    "time_signature": { "beats_per_bar": 4, "confidence": 0.95 },
    "bar_times": [0.0, 1.875, 3.75, ...],
    "segment_count": 8,
    "analysis_version": "2.0.0"
  },

  "loop_points": {
    "recommended": [
      {
        "loop_start_ms": 30468,
        "loop_end_ms": 45703,
        "loop_beats": 32,
        "loop_bars": 8,
        "quality_score": 0.94,
        "section_label": "Chorus 1",
        "bar_aligned": true
      },
      ...
    ],
    "all": [
      ... (all evaluated candidates above quality_score 0.6)
    ]
  },

  "arrangement_markers": [
    {
      "marker_type": "build_up",
      "position_ms": 42000,
      "position_end_ms": 48000,
      "description": "Energy build-up into Chorus 1",
      "intensity": 0.87,
      "metadata": {}
    },
    {
      "marker_type": "drop",
      "position_ms": 48000,
      "description": "Drop at Chorus 1",
      "intensity": 0.95,
      "metadata": { "energy_spike": 0.92 }
    },
    {
      "marker_type": "key_change",
      "position_ms": 120000,
      "description": "Key change: C# minor -> E major",
      "intensity": 0.78,
      "metadata": { "from_key": "C# minor", "to_key": "E major" }
    },
    ...
  ],

  "energy_curve": {
    "times": [0.0, 0.5, 1.0, ...],
    "values": [0.12, 0.15, 0.18, ...]
  }
}
```

### 3.2 Optional Future Migration: Dedicated Tables

If query performance on the JSONB column becomes a bottleneck (e.g., searching for all tracks with a "drop" marker, or filtering by structural similarity), consider adding dedicated tables:

```sql
-- Future: Only if needed for query performance
CREATE TABLE track_segments (
  id         UUID PRIMARY KEY,
  track_id   UUID REFERENCES tracks(id) ON DELETE CASCADE,
  section_type VARCHAR NOT NULL,
  start_ms   INTEGER NOT NULL,
  end_ms     INTEGER NOT NULL,
  confidence FLOAT,
  label      VARCHAR,
  energy_profile FLOAT,
  repetition_group INTEGER,
  metadata   JSONB,
  inserted_at TIMESTAMP
);

CREATE TABLE track_loop_points (
  id             UUID PRIMARY KEY,
  track_id       UUID REFERENCES tracks(id) ON DELETE CASCADE,
  loop_start_ms  INTEGER NOT NULL,
  loop_end_ms    INTEGER NOT NULL,
  loop_beats     INTEGER,
  loop_bars      INTEGER,
  quality_score  FLOAT,
  section_label  VARCHAR,
  recommended    BOOLEAN DEFAULT FALSE,
  bar_aligned    BOOLEAN DEFAULT TRUE,
  inserted_at    TIMESTAMP
);

CREATE TABLE track_arrangement_markers (
  id              UUID PRIMARY KEY,
  track_id        UUID REFERENCES tracks(id) ON DELETE CASCADE,
  marker_type     VARCHAR NOT NULL,
  position_ms     INTEGER NOT NULL,
  position_end_ms INTEGER,
  description     VARCHAR,
  intensity       FLOAT,
  metadata        JSONB,
  inserted_at     TIMESTAMP
);
```

For Phase 1, JSONB in `features` is sufficient and avoids schema migration.

---

## 4. Python Analyzer Changes

### 4.1 New Feature Module: `extract_structure`

```python
def extract_structure(y: np.ndarray, sr: int, beat_times: np.ndarray) -> Dict[str, Any]:
    """
    Structural segmentation via novelty-based boundary detection
    and agglomerative clustering.
    """
    # 1. Compute time-series features
    hop_length = 512
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop_length)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=hop_length)

    # 2. Build recurrence/self-similarity matrix
    R = librosa.segment.recurrence_matrix(chroma, mode='affinity', metric='cosine')

    # 3. Compute novelty curve (checkerboard kernel)
    novelty = librosa.segment.novelty(R, kernel_size=64)

    # 4. Peak-pick boundary frames
    boundaries = librosa.segment.agglomerative(chroma, k=None)
    # ... or use novelty peak picking

    # 5. Convert to timestamps
    boundary_times = librosa.frames_to_time(boundaries, sr=sr, hop_length=hop_length)

    # 6. Classify segments (heuristic labeling)
    segments = classify_segments(y, sr, boundary_times, chroma, hop_length)

    # 7. Compute bar grid
    bar_times = compute_bar_grid(beat_times)

    return {
        "segments": segments,
        "bar_times": bar_times.tolist(),
        "segment_count": len(segments),
        "time_signature": detect_time_signature(beat_times),
        "analysis_version": "2.0.0"
    }
```

### 4.2 New Feature Module: `extract_loop_points`

```python
def extract_loop_points(y: np.ndarray, sr: int, beat_times: np.ndarray,
                         segments: List[Dict]) -> Dict[str, Any]:
    """
    Identify optimal loop points aligned to beats/bars.
    """
    hop_length = 512
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop_length)
    rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]

    bar_times = compute_bar_grid(beat_times)
    candidates = []

    for loop_bars in [1, 2, 4, 8, 16]:
        for i in range(len(bar_times) - loop_bars):
            start = bar_times[i]
            end = bar_times[i + loop_bars]
            score = compute_loop_quality(chroma, rms, start, end, sr, hop_length)
            candidates.append({
                "loop_start_ms": int(start * 1000),
                "loop_end_ms": int(end * 1000),
                "loop_beats": loop_bars * 4,
                "loop_bars": loop_bars,
                "quality_score": float(score),
                "section_label": find_section_for_time(segments, start),
                "bar_aligned": True
            })

    # Sort by quality, take top N as recommended
    candidates.sort(key=lambda x: x["quality_score"], reverse=True)
    recommended = candidates[:5]
    for lp in recommended:
        lp["recommended"] = True

    all_good = [c for c in candidates if c["quality_score"] >= 0.6]

    return {
        "recommended": recommended,
        "all": all_good
    }
```

### 4.3 New Feature Module: `extract_arrangement_markers`

```python
def extract_arrangement_markers(y: np.ndarray, sr: int, beat_times: np.ndarray,
                                 segments: List[Dict]) -> List[Dict]:
    """
    Detect key changes, energy transitions, build-ups, and drops.
    """
    hop_length = 512
    markers = []

    # Key change detection
    markers.extend(detect_key_changes(y, sr, hop_length))

    # Energy transition detection
    markers.extend(detect_energy_transitions(y, sr, hop_length))

    # Drop detection
    markers.extend(detect_drops(y, sr, hop_length, segments))

    # Build-up detection
    markers.extend(detect_buildups(y, sr, hop_length, segments))

    # Sort by position
    markers.sort(key=lambda m: m["position_ms"])
    return markers
```

### 4.4 Energy Curve (Time-Series)

```python
def extract_energy_curve(y: np.ndarray, sr: int, resolution: float = 0.5) -> Dict[str, Any]:
    """
    Compute a downsampled energy curve for visualization.
    Resolution controls the time step in seconds.
    """
    hop_length = int(sr * resolution)
    rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]
    times = librosa.frames_to_time(range(len(rms)), sr=sr, hop_length=hop_length)

    return {
        "times": times.tolist(),
        "values": rms.tolist()
    }
```

### 4.5 Updated CLI Interface

Add new feature names to the valid set:

```python
valid_features = {
    'tempo', 'key', 'energy', 'spectral', 'mfcc', 'chroma',
    'structure', 'loop_points', 'arrangement', 'energy_curve',
    'all'
}
```

Dependency chain within `analyze_audio`:
- `structure` requires `tempo` (for beat_times) and `chroma` (for segmentation)
- `loop_points` requires `tempo` (for beat_times) and `structure` (for segment context)
- `arrangement` requires `tempo`, `energy`, `chroma` (for key change detection)
- `energy_curve` is independent

When `all` is requested, compute in dependency order: tempo -> key -> energy -> spectral -> mfcc -> chroma -> structure -> loop_points -> arrangement -> energy_curve.

### 4.6 Performance Considerations

Structural analysis is significantly more expensive than basic feature extraction:
- Recurrence matrix: O(n^2) where n = number of frames. For a 5-minute song at hop_length=512 and sr=22050: ~12,900 frames -> ~167M element matrix.
- Mitigation: Downsample before computing recurrence (use larger hop_length for structure, e.g., 4096). At hop=4096: ~1,600 frames -> ~2.5M elements. Acceptable.
- Loop point evaluation: O(bars * loop_sizes) candidates. For 100 bars and 5 sizes: 500 candidates. Fast.
- Energy curve: Trivial computation.

Estimated additional processing time per track:
- Structure: 5-15 seconds (depending on track length)
- Loop points: 1-3 seconds
- Arrangement markers: 2-5 seconds
- Energy curve: < 1 second
- **Total additional**: 8-24 seconds on top of existing analysis (~10-20 seconds)

### 4.7 Dependencies

No new Python package dependencies needed. All algorithms use existing librosa functions:
- `librosa.segment.recurrence_matrix`
- `librosa.segment.agglomerative`
- `librosa.onset.onset_strength`
- `librosa.onset.onset_detect`
- `librosa.feature.tempogram`
- `numpy` for matrix operations and peak picking

---

## 5. Elixir Backend Changes

### 5.1 AnalyzerPort Updates

Update `@valid_features` in `lib/sound_forge/audio/analyzer_port.ex`:

```elixir
@valid_features ~w(tempo key energy spectral mfcc chroma structure loop_points arrangement energy_curve all)
```

### 5.2 AnalysisWorker Updates

The worker already stores the full results map in `features`. No changes needed to the worker itself -- the new data flows through automatically. However, we may want to:

1. Add a progress broadcast at 50% when basic features are done and structural analysis begins.
2. Handle the larger features map gracefully (the JSON could be 50-100KB for complex tracks with many loop candidates).

### 5.3 AnalysisController Updates

Add `structure`, `loop_points`, `arrangement`, `energy_curve` to `@valid_analysis_types` and update `type_to_features/1`:

```elixir
defp type_to_features("full"), do: ["all"]
defp type_to_features("structure"), do: ["tempo", "chroma", "structure"]
defp type_to_features("loops"), do: ["tempo", "chroma", "structure", "loop_points"]
defp type_to_features("arrangement"), do: ["tempo", "energy", "chroma", "arrangement"]
```

### 5.4 Settings Integration

Add new settings for structural analysis in `UserSettings`:
- `structural_analysis_enabled`: boolean (default true) -- whether to run structural analysis on new tracks
- `loop_detection_enabled`: boolean (default true)
- `arrangement_markers_enabled`: boolean (default true)
- `structural_analysis_sensitivity`: float (0.5-1.5, default 1.0) -- controls novelty detection threshold

These settings feed into the `features` list passed to the analyzer.

### 5.5 Helper Functions for Frontend Data Extraction

Add to `DashboardLive` or a dedicated helper module:

```elixir
def structure_segments(analysis) do
  get_in(analysis.features || %{}, ["structure", "segments"]) || []
end

def recommended_loop_points(analysis) do
  get_in(analysis.features || %{}, ["loop_points", "recommended"]) || []
end

def arrangement_markers(analysis) do
  (analysis.features || %{})["arrangement_markers"] || []
end

def energy_curve(analysis) do
  (analysis.features || %{})["energy_curve"] || %{}
end

def bar_times(analysis) do
  get_in(analysis.features || %{}, ["structure", "bar_times"]) || []
end
```

---

## 6. Frontend Visualization Additions

### 6.1 New Hook: `AnalysisStructure` (Song Structure Timeline)

**Description**: A horizontal timeline showing the song structure with color-coded sections, rendered as a stacked bar chart.

**Data**: `features["structure"]["segments"]`

**Design**:
```
[Intro   ][  Verse 1  ][ Pre  ][  Chorus 1  ][ Verse 2 ][ Pre ][  Chorus 2  ][Bridge][ Chorus 3 ][Outro]
 gray      blue          yellow  purple         blue       yellow  purple         green   purple     gray
 0:00     0:15          0:45    0:53           1:23       1:53    2:01           2:31    2:46       3:16
```

- Each section rendered as a colored rectangle proportional to its duration.
- Section type determines color (consistent color palette).
- Hover shows section details (type, start, end, energy, confidence).
- Click on section to seek playback to that position.
- Repeating sections (same repetition_group) share the same color saturation.

**Color palette**:
- Intro/Outro: gray-500
- Verse: blue-500
- Pre-Chorus: yellow-500
- Chorus: purple-500
- Bridge: green-500
- Drop: red-500
- Breakdown: cyan-500
- Build-up: orange-500 (gradient)

### 6.2 New Hook: `AnalysisLoopPoints` (Loop Point Visualization)

**Description**: Markers overlaid on the beat timeline or structure timeline showing recommended loop points.

**Data**: `features["loop_points"]["recommended"]`

**Design**:
- Rendered as bracketed regions on the AnalysisBeats timeline.
- Recommended loops shown with solid borders and quality score badge.
- Click on a loop point to set it as the active loop on the DJ deck.
- Hover shows: bars, beats, quality score, section label.

### 6.3 New Hook: `AnalysisEnergyCurve` (Energy Waveform)

**Description**: A continuous energy curve overlaid beneath or above the structure timeline, showing dynamic range over time.

**Data**: `features["energy_curve"]`

**Design**:
- Area chart with gradient fill (low energy = cool blue, high energy = hot red/purple).
- Arrangement markers rendered as vertical lines/icons at their positions.
- Key change markers shown as small key symbols.
- Build-up regions shown as gradient ramps.
- Drop markers shown as lightning bolt icons.

### 6.4 Updated Hook: `AnalysisBeats` Enhancement

Extend the existing beat timeline to overlay:
- Bar boundaries (thicker lines every 4 beats).
- Section boundaries (vertical dashed lines with section labels).
- Loop point brackets for recommended loops.

### 6.5 Registration in `app.js`

```javascript
import AnalysisStructure from "./hooks/analysis_structure"
import AnalysisLoopPoints from "./hooks/analysis_loop_points"
import AnalysisEnergyCurve from "./hooks/analysis_energy_curve"

const Hooks = {
  // ... existing hooks ...
  AnalysisStructure,
  AnalysisLoopPoints,
  AnalysisEnergyCurve,
}
```

---

## 7. Integration Points with DJ/DAW Components

### 7.1 DJ Deck Integration

#### 7.1.1 Structure-Aware Loop Controls

Extend the DJ tab component to:
- Display recommended loop points as quick-select buttons below the loop controls.
- Add a "Smart Loop" button that sets the loop to the best loop point for the current structural section.
- When a loop is set manually, snap to the nearest bar boundary from the `bar_times` array instead of simple BPM-based quantization.

**Server-side** (`dj_tab_component.ex`):
```elixir
defp extract_analysis_data(track) do
  track = Repo.preload(track, :analysis_results)
  case track.analysis_results do
    [result | _] ->
      beat_times = (result.features || %{}) |> Map.get("beats", %{}) |> Map.get("times", [])
      structure = get_in(result.features || %{}, ["structure"]) || %{}
      loop_points = get_in(result.features || %{}, ["loop_points", "recommended"]) || []
      bar_times = get_in(result.features || %{}, ["structure", "bar_times"]) || []
      arrangement_markers = (result.features || %{})["arrangement_markers"] || []

      {result.tempo, beat_times, structure, loop_points, bar_times, arrangement_markers}
    _ ->
      {nil, [], %{}, [], [], []}
  end
end
```

**Client-side** (`dj_deck.js`):
- Receive `structure`, `loop_points`, `bar_times`, `arrangement_markers` in `load_deck_audio`.
- Render structure sections as colored bands on the minimap.
- Render loop point markers on the waveform (distinguishable from beat markers).
- Use `bar_times` for quantization instead of BPM math.
- Add `set_smart_loop` event handler: given current position, find the best loop point in the current section.

#### 7.1.2 Section Navigation

- Add section skip buttons (forward/back) that jump between structural sections.
- Display current section name in the deck UI (e.g., "Chorus 2" next to BPM).
- Cue point auto-suggestion: when analysis completes, auto-create cue points at section boundaries (user-configurable).

#### 7.1.3 Auto-Cue on Section Boundaries

When a track is loaded and analysis data is available:
- Auto-set a cue point at the first beat of each section boundary.
- Label each cue with the section name.
- Color based on section type (using the same palette as the structure visualization).
- These auto-cues are distinguishable from user-created hot cues (cue_type: :section vs :hot).

### 7.2 DAW Editor Integration

#### 7.2.1 Structure-Aware Operation Placement

- Display structure sections as a colored track header above the stem waveforms.
- When applying operations (crop, trim, fade), offer snap-to-section-boundary mode.
- "Select Section" tool: click a section in the header to auto-select that time range for operations.

#### 7.2.2 Bar Grid Snapping

- Use `bar_times` from analysis to render a bar grid on DAW waveforms.
- Operations snap to bar boundaries when dragged/resized (with modifier key to override).

#### 7.2.3 Section-Based Stem Processing

**Key integration**: Allow users to select specific sections for stem separation rather than processing the entire track.

- UI: "Process Section" button on each section in the structure visualization.
- Backend: Extract audio for that time range, submit to Demucs/lalal.ai for separation.
- This saves processing time and resources when users only need stems for a specific chorus or drop.

**Implementation path**:
1. Add `start_ms` and `end_ms` optional parameters to the processing pipeline.
2. Before calling Demucs/lalal.ai, trim the audio to the specified range using `ffmpeg`.
3. Store resulting stems with section metadata (which section they came from).
4. In the DAW, render section-specific stems alongside or in place of full-track stems.

### 7.3 Stem Separation Section Selection UI

In the track detail view (Analysis tab), each structural section will have a "Separate Stems" button:

```
[Chorus 1: 0:53 - 1:23]  Energy: 0.82  [ Separate Stems ]  [ Set as Loop ]
```

Clicking "Separate Stems" for a section will:
1. Extract that audio range using ffmpeg.
2. Submit the extracted range to the selected engine (Demucs or lalal.ai).
3. Store resulting stems with metadata: `{section: "Chorus 1", start_ms: 53000, end_ms: 83000}`.
4. Display in DAW as section-scoped stems.

---

## 8. Implementation Phases

### Phase 1: Core Structural Analysis (Week 1-2)

**Goal**: Get structural segmentation working end-to-end from Python -> database -> frontend visualization.

**Tasks**:
1. Implement `extract_structure()` in `priv/python/analyzer.py`
   - Self-similarity matrix computation
   - Novelty-based boundary detection
   - Segment classification heuristics
   - Bar grid computation
   - Time signature detection
2. Add `structure` to valid features in Python CLI and AnalyzerPort
3. Implement `AnalysisStructure` D3 hook (colored section timeline)
4. Add structure timeline to dashboard analysis section in `dashboard_live.html.heex`
5. Implement `extract_energy_curve()` in Python
6. Implement `AnalysisEnergyCurve` D3 hook
7. Add helper functions to DashboardLive for extracting structure data
8. Test with 5-10 diverse tracks (electronic, pop, rock, hip-hop, classical)

**Deliverables**:
- Working structural segmentation with visual timeline
- Energy curve visualization with gradient
- All data stored in existing `features` JSONB column

### Phase 2: Loop Point Detection (Week 3)

**Goal**: Detect optimal loop points and surface them in the UI.

**Tasks**:
1. Implement `extract_loop_points()` in Python
   - Bar-aligned candidate generation
   - Quality scoring (chroma + energy + spectral boundary matching)
   - Ranking and recommendation
2. Implement `AnalysisLoopPoints` D3 hook or integrate into AnalysisBeats
3. Display recommended loops in track detail analysis view
4. Add "quick loop" buttons to DJ deck controls showing top recommended loops
5. Test loop quality: verify recommended loops actually sound good when looped

**Deliverables**:
- Loop point detection with quality scores
- Loop recommendations visible in analysis view
- Quick-loop buttons in DJ tab

### Phase 3: Arrangement Markers (Week 4)

**Goal**: Detect key changes, energy transitions, build-ups, and drops.

**Tasks**:
1. Implement `extract_arrangement_markers()` in Python
   - Key change detection (windowed chroma analysis)
   - Energy transition detection (gradient analysis on RMS curve)
   - Drop detection (energy dip-spike pattern)
   - Build-up detection (energy ramp + spectral widening)
2. Overlay arrangement markers on energy curve visualization
3. Add marker icons on structure timeline (key change, drop, build-up icons)
4. Display marker list in analysis detail view

**Deliverables**:
- Arrangement markers with type classification
- Visual markers on energy curve and structure timeline
- Marker list with descriptions

### Phase 4: DJ Integration (Week 5-6)

**Goal**: Integrate structural analysis into DJ workflow.

**Tasks**:
1. Pass structure, loop_points, bar_times, arrangement_markers to DJ deck hook
2. Render structure sections as colored bands on DJ waveform minimap
3. Implement bar-grid quantization for loop in/out (replace BPM-based math)
4. Add recommended loop quick-select buttons
5. Add section skip (forward/back) buttons
6. Show current section label in deck UI
7. Implement "Smart Loop" button (auto-set best loop for current section)
8. Add auto-cue suggestion at section boundaries (opt-in setting)

**Deliverables**:
- Structure-aware DJ deck with visual section indicators
- Bar-grid quantized loop controls
- Section navigation and smart loop

### Phase 5: DAW Integration (Week 7)

**Goal**: Integrate structural analysis into DAW editor workflow.

**Tasks**:
1. Add structure header track above stem waveforms in DAW editor
2. Implement bar grid rendering on DAW waveforms
3. Add snap-to-bar and snap-to-section for operation drag/resize
4. Add "Select Section" tool for quick region selection
5. Implement section-based stem processing UI ("Separate Stems" per section)

**Deliverables**:
- Structure-aware DAW editor
- Bar grid snapping
- Section-based stem separation

### Phase 6: Polish, Settings, and Section Separation (Week 8)

**Goal**: Settings integration, performance optimization, edge case handling.

**Tasks**:
1. Add structural analysis settings to Settings LiveView
2. Handle edge cases: very short tracks, tracks with no clear structure, spoken word, ambient music
3. Performance optimization: cache expensive computations, lazy-load loop candidates
4. Add `--structure-sensitivity` CLI parameter for tuning novelty detection threshold
5. Implement section-specific stem separation backend (ffmpeg pre-trim + Demucs/lalal.ai)
6. Add keyboard shortcuts for section navigation in DJ mode
7. Write tests for structural analysis worker, loop detection, arrangement markers
8. Update analysis export JSON to include new data

**Deliverables**:
- Complete settings integration
- Robust error handling for edge cases
- Section-based stem separation pipeline
- Test coverage

---

## 9. Risk Assessment and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Structural labeling is inaccurate for non-EDM genres | Medium | High | Use confidence scores, allow manual override, train heuristics on diverse genres |
| Self-similarity matrix too large for long tracks (>10 min) | High | Medium | Use larger hop_length (4096+), subsample, or compute in chunks |
| Loop quality scoring does not match perceptual quality | Medium | Medium | Iterative tuning with real listening tests, user feedback loop |
| JSONB column grows too large with all new features | Low | Low | Cap loop candidates (top 50), downsample energy curve, compress |
| Analysis time exceeds Oban timeout (120s) | Medium | Medium | Increase timeout, run structural analysis as separate Oban job with lower priority |
| librosa segment functions produce too few/many boundaries | Medium | High | Tune parameters (kernel_size, k clusters), add min/max segment constraints |

---

## 10. Success Metrics

1. **Structural accuracy**: >= 75% of segments correctly labeled (evaluated on 50 test tracks across genres)
2. **Loop quality**: Top 3 recommended loops sound musically coherent when looped (subjective evaluation)
3. **Processing time**: Structural analysis adds < 30 seconds per track on average
4. **DJ workflow improvement**: Section navigation reduces time to find loop points by 50%+ (compared to manual scrubbing)
5. **User engagement**: Section-based stem separation reduces unnecessary full-track processing by 30%+

---

## 11. Technical Notes

### librosa API Reference for Key Functions

```python
# Self-similarity / recurrence
librosa.segment.recurrence_matrix(data, mode='affinity', metric='cosine', bandwidth=None)
librosa.segment.agglomerative(data, k=None)

# Novelty detection (not a direct librosa function -- implement manually)
# Use checkerboard kernel convolution on self-similarity matrix:
#   kernel = np.outer([-1, 1], [-1, 1])
#   novelty = scipy.signal.convolve2d(R, kernel, mode='same').diagonal()

# Alternative: librosa.segment.subsegment() for refining boundaries

# Onset detection (useful for drop/build-up detection)
librosa.onset.onset_strength(y=y, sr=sr)
librosa.onset.onset_detect(y=y, sr=sr, units='time')

# Tempogram (for time-varying tempo)
librosa.feature.tempogram(y=y, sr=sr)
```

### Existing Beat Grid Issue

The DJ tab component calls `Map.get("beat_times", [])` on `result.features`, but the Python analyzer stores beats under the key `"beats"` as a flat list (line 50 of analyzer.py). The dashboard correctly reads `features["beats"]`. This inconsistency should be fixed as part of Phase 4 (DJ integration) to standardize on `features["beats"]["times"]` or add a `"beat_times"` alias.

### JSON Size Estimation

For a typical 4-minute track:
- Current features JSON: ~5-10 KB
- Structure segments (8-12 segments): +1 KB
- Loop points (50 candidates): +5 KB
- Arrangement markers (10-20 markers): +2 KB
- Energy curve (480 samples at 0.5s resolution): +4 KB
- Bar grid (200 bars): +2 KB
- **Total estimated**: 20-25 KB per track (manageable for JSONB)
