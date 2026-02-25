#!/usr/bin/env python3
"""
Audio Analyzer - Librosa-based Feature Extraction

@description Extracts audio features using librosa for Sound Forge Alchemy
@features tempo, key, energy, spectral, mfcc, chroma, structure, loop_points, arrangement, energy_curve
@author Sound Forge Alchemy Team
@version 2.0.0
@license MIT
"""

import sys
import json
import argparse
import os
import warnings
from typing import Dict, List, Any, Optional, Tuple

# Suppress librosa warnings
warnings.filterwarnings('ignore')

try:
    import librosa
    import numpy as np
except ImportError as e:
    print(json.dumps({
        "error": "Missing dependencies",
        "message": str(e),
        "details": "Please install: pip install librosa numpy"
    }), file=sys.stderr)
    sys.exit(1)

# Optional scipy for checkerboard kernel novelty
try:
    from scipy.signal import convolve2d
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False


# ---------------------------------------------------------------------------
# Existing feature extractors
# ---------------------------------------------------------------------------

def extract_tempo(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """
    Extract tempo (BPM) from audio

    Args:
        y: Audio time series
        sr: Sample rate

    Returns:
        Dictionary containing tempo information
    """
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
    beat_times = librosa.frames_to_time(beats, sr=sr)

    return {
        "tempo": float(tempo),
        "beats": beat_times.tolist(),
        "beat_count": len(beats)
    }


def extract_key(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """
    Extract musical key from audio using chroma features

    Args:
        y: Audio time series
        sr: Sample rate

    Returns:
        Dictionary containing key information
    """
    # Compute chroma features
    chromagram = librosa.feature.chroma_stft(y=y, sr=sr)

    # Average chroma across time
    chroma_mean = np.mean(chromagram, axis=1)

    # Find dominant pitch class
    dominant_pitch_class = np.argmax(chroma_mean)

    # Map to key names
    pitch_classes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

    # Simple major/minor detection using chroma profile
    major_profile = np.array([1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1])
    minor_profile = np.array([1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0])

    # Rotate profiles to match dominant pitch class
    major_correlation = np.correlate(np.roll(major_profile, dominant_pitch_class), chroma_mean)[0]
    minor_correlation = np.correlate(np.roll(minor_profile, dominant_pitch_class), chroma_mean)[0]

    mode = "major" if major_correlation > minor_correlation else "minor"
    key = f"{pitch_classes[dominant_pitch_class]} {mode}"

    return {
        "key": key,
        "confidence": float(max(major_correlation, minor_correlation) / np.sum(chroma_mean)),
        "pitch_class": pitch_classes[dominant_pitch_class],
        "mode": mode
    }


def extract_energy(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """
    Extract energy features from audio

    Args:
        y: Audio time series
        sr: Sample rate

    Returns:
        Dictionary containing energy information
    """
    # RMS energy
    rms = librosa.feature.rms(y=y)[0]

    # Zero crossing rate (proxy for noisiness)
    zcr = librosa.feature.zero_crossing_rate(y)[0]

    return {
        "energy": float(np.mean(rms)),
        "energy_variance": float(np.var(rms)),
        "energy_max": float(np.max(rms)),
        "energy_min": float(np.min(rms)),
        "zero_crossing_rate": float(np.mean(zcr))
    }


def extract_spectral(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """
    Extract spectral features from audio

    Args:
        y: Audio time series
        sr: Sample rate

    Returns:
        Dictionary containing spectral information
    """
    # Spectral centroid
    spectral_centroids = librosa.feature.spectral_centroid(y=y, sr=sr)[0]

    # Spectral rolloff
    spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)[0]

    # Spectral bandwidth
    spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)[0]

    # Spectral contrast
    spectral_contrast = librosa.feature.spectral_contrast(y=y, sr=sr)

    return {
        "spectral_centroid": float(np.mean(spectral_centroids)),
        "spectral_centroid_variance": float(np.var(spectral_centroids)),
        "spectral_rolloff": float(np.mean(spectral_rolloff)),
        "spectral_bandwidth": float(np.mean(spectral_bandwidth)),
        "spectral_contrast": np.mean(spectral_contrast, axis=1).tolist(),
        "spectral_flatness": float(np.mean(librosa.feature.spectral_flatness(y=y)[0]))
    }


def extract_mfcc(y: np.ndarray, sr: int, n_mfcc: int = 13) -> Dict[str, Any]:
    """
    Extract MFCC (Mel-frequency cepstral coefficients) features

    Args:
        y: Audio time series
        sr: Sample rate
        n_mfcc: Number of MFCCs to extract

    Returns:
        Dictionary containing MFCC information
    """
    mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)

    return {
        "mfcc": np.mean(mfccs, axis=1).tolist(),
        "mfcc_variance": np.var(mfccs, axis=1).tolist(),
        "n_mfcc": n_mfcc
    }


def extract_chroma(y: np.ndarray, sr: int) -> Dict[str, Any]:
    """
    Extract chroma features from audio

    Args:
        y: Audio time series
        sr: Sample rate

    Returns:
        Dictionary containing chroma information
    """
    # Compute chroma features
    chroma_stft = librosa.feature.chroma_stft(y=y, sr=sr)
    chroma_cqt = librosa.feature.chroma_cqt(y=y, sr=sr)
    chroma_cens = librosa.feature.chroma_cens(y=y, sr=sr)

    return {
        "chroma_stft": np.mean(chroma_stft, axis=1).tolist(),
        "chroma_cqt": np.mean(chroma_cqt, axis=1).tolist(),
        "chroma_cens": np.mean(chroma_cens, axis=1).tolist()
    }


# ---------------------------------------------------------------------------
# US-001: Structural Segmentation
# ---------------------------------------------------------------------------

def compute_bar_grid(beat_times: np.ndarray, beats_per_bar: int = 4) -> np.ndarray:
    """Compute bar boundary times by grouping beats into bars.

    Args:
        beat_times: Array of beat onset times in seconds.
        beats_per_bar: Number of beats per bar (default 4).

    Returns:
        Array of bar boundary times (including track end extrapolation).
    """
    if len(beat_times) < 2:
        return beat_times.copy()
    bar_times = beat_times[::beats_per_bar].copy()
    # Extrapolate one bar past the last detected bar boundary
    if len(bar_times) >= 2:
        bar_dur = float(bar_times[-1] - bar_times[-2])
        bar_times = np.append(bar_times, bar_times[-1] + bar_dur)
    elif len(bar_times) == 1:
        # Estimate bar duration from average beat interval
        avg_beat = float(np.mean(np.diff(beat_times)))
        bar_times = np.append(bar_times, bar_times[0] + avg_beat * beats_per_bar)
    return bar_times


def _detect_time_signature(beat_times: np.ndarray) -> Dict[str, Any]:
    """Estimate time signature from beat intervals.

    Heuristic: if the beat intervals show a strong grouping-of-3 pattern
    (via autocorrelation at lag 3 > lag 4), report 3/4; otherwise 4/4.

    Returns:
        {"beats_per_bar": int, "confidence": float}
    """
    if len(beat_times) < 6:
        return {"beats_per_bar": 4, "confidence": 0.5}

    intervals = np.diff(beat_times)
    if len(intervals) < 6:
        return {"beats_per_bar": 4, "confidence": 0.5}

    # Normalised autocorrelation at lags 3 and 4
    norm = np.correlate(intervals, intervals, mode='full')
    mid = len(norm) // 2
    ac0 = norm[mid] if norm[mid] > 0 else 1.0

    ac3 = norm[mid + 3] / ac0 if mid + 3 < len(norm) else 0.0
    ac4 = norm[mid + 4] / ac0 if mid + 4 < len(norm) else 0.0

    if ac3 > ac4 * 1.15:
        return {"beats_per_bar": 3, "confidence": float(min(1.0, ac3))}
    else:
        return {"beats_per_bar": 4, "confidence": float(min(1.0, ac4))}


def _compute_segment_energy(y: np.ndarray, sr: int, start: float, end: float) -> float:
    """Compute mean RMS energy for a time range."""
    s_start = int(start * sr)
    s_end = min(int(end * sr), len(y))
    if s_end <= s_start:
        return 0.0
    seg = y[s_start:s_end]
    rms = librosa.feature.rms(y=seg)[0]
    return float(np.mean(rms)) if len(rms) > 0 else 0.0


def classify_segments(
    boundaries: np.ndarray,
    y: np.ndarray,
    sr: int,
    rec_matrix: Optional[np.ndarray] = None
) -> List[Dict[str, Any]]:
    """Classify segment boundaries into section types using energy heuristics.

    Args:
        boundaries: Array of segment boundary times in seconds (sorted).
        y: Audio time series.
        sr: Sample rate.
        rec_matrix: Optional recurrence/self-similarity matrix for repetition grouping.

    Returns:
        List of segment dictionaries.
    """
    n_seg = len(boundaries) - 1
    if n_seg <= 0:
        return []

    # Pre-compute per-segment energy
    energies = []
    for i in range(n_seg):
        energies.append(_compute_segment_energy(y, sr, boundaries[i], boundaries[i + 1]))
    energies = np.array(energies)

    mean_energy = float(np.mean(energies)) if len(energies) > 0 else 0.0
    max_energy = float(np.max(energies)) if len(energies) > 0 else 1.0
    if max_energy == 0:
        max_energy = 1.0

    # Repetition groups via simple chroma fingerprint similarity
    # Build a chroma centroid per segment and group by cosine similarity
    seg_chromas = []
    for i in range(n_seg):
        s_start = int(boundaries[i] * sr)
        s_end = min(int(boundaries[i + 1] * sr), len(y))
        if s_end - s_start < sr // 4:
            seg_chromas.append(np.zeros(12))
        else:
            c = librosa.feature.chroma_cqt(y=y[s_start:s_end], sr=sr, hop_length=4096)
            seg_chromas.append(np.mean(c, axis=1))
    seg_chromas = np.array(seg_chromas)

    # Assign repetition groups via greedy clustering (cosine > 0.85 threshold)
    groups: List[int] = [-1] * n_seg
    next_group = 0
    for i in range(n_seg):
        if groups[i] >= 0:
            continue
        groups[i] = next_group
        norm_i = np.linalg.norm(seg_chromas[i])
        if norm_i == 0:
            next_group += 1
            continue
        for j in range(i + 1, n_seg):
            if groups[j] >= 0:
                continue
            norm_j = np.linalg.norm(seg_chromas[j])
            if norm_j == 0:
                continue
            cos_sim = float(np.dot(seg_chromas[i], seg_chromas[j]) / (norm_i * norm_j))
            if cos_sim > 0.85:
                groups[j] = next_group
        next_group += 1

    # Count how often each group appears
    from collections import Counter
    group_counts = Counter(groups)

    segments: List[Dict[str, Any]] = []
    for i in range(n_seg):
        e_norm = energies[i] / max_energy

        # Determine section type
        if i == 0:
            section_type = "intro"
        elif i == n_seg - 1:
            section_type = "outro"
        elif group_counts[groups[i]] >= 2 and e_norm > 0.65:
            section_type = "chorus"
        elif group_counts[groups[i]] >= 2 and e_norm > 0.8:
            section_type = "drop"
        elif e_norm < 0.4:
            section_type = "verse"
        elif 0.4 <= e_norm <= 0.55:
            section_type = "bridge"
        elif 0.55 < e_norm <= 0.65:
            section_type = "pre_chorus"
        else:
            # Transitional heuristics
            if i > 0 and energies[i] > energies[i - 1] * 1.3:
                section_type = "build_up"
            elif i > 0 and energies[i] < energies[i - 1] * 0.7:
                section_type = "breakdown"
            else:
                section_type = "verse"

        label = f"{section_type}_{i + 1}"
        confidence = min(1.0, 0.5 + 0.3 * (group_counts[groups[i]] / max(group_counts.values())) + 0.2 * e_norm)

        segments.append({
            "section_type": section_type,
            "start_time": float(boundaries[i]),
            "end_time": float(boundaries[i + 1]),
            "confidence": round(float(confidence), 4),
            "label": label,
            "energy_profile": round(float(e_norm), 4),
            "repetition_group": int(groups[i])
        })

    return segments


def extract_structure(y: np.ndarray, sr: int, beat_times: np.ndarray) -> Dict[str, Any]:
    """US-001: Extract structural segmentation from audio.

    Uses chroma CQT self-similarity, checkerboard kernel novelty (scipy) or
    agglomerative clustering (fallback) to detect section boundaries, then
    classifies each segment via energy-based heuristics.

    Args:
        y: Audio time series.
        sr: Sample rate.
        beat_times: Array of beat onset times in seconds.

    Returns:
        Dictionary with segments, bar_times, time_signature, etc.
    """
    duration = librosa.get_duration(y=y, sr=sr)

    # Edge case: very short track (< 30s) or no beats
    if duration < 30.0 or len(beat_times) < 4:
        ts = _detect_time_signature(beat_times)
        bar_times = compute_bar_grid(beat_times, ts["beats_per_bar"])
        single_segment = {
            "section_type": "intro",
            "start_time": 0.0,
            "end_time": float(duration),
            "confidence": 0.5,
            "label": "intro_1",
            "energy_profile": 1.0,
            "repetition_group": 0
        }
        return {
            "segments": [single_segment],
            "bar_times": bar_times.tolist(),
            "segment_count": 1,
            "time_signature": ts,
            "analysis_version": "2.0.0"
        }

    # Compute chroma CQT (memory-efficient hop)
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=4096)

    # Build self-similarity / recurrence matrix
    rec = librosa.segment.recurrence_matrix(
        chroma, mode='affinity', metric='cosine', sparse=False
    )

    # Detect boundaries
    boundaries_frames = None

    if HAS_SCIPY:
        # Checkerboard kernel novelty on the diagonal of the recurrence matrix
        try:
            # Build a small checkerboard kernel
            kern_size = min(32, rec.shape[0] // 4)
            if kern_size < 4:
                kern_size = 4
            half = kern_size // 2
            kernel = np.ones((kern_size, kern_size))
            kernel[:half, half:] = -1
            kernel[half:, :half] = -1

            # Extract diagonal band and convolve
            diag = np.diag(rec)
            # Full 2D convolution on the recurrence matrix for novelty
            novelty_2d = convolve2d(rec, kernel, mode='same', boundary='fill', fillvalue=0)
            # Take the diagonal of the convolved matrix as novelty curve
            novelty = np.abs(np.diag(novelty_2d))

            # Smooth and peak-pick
            novelty = np.convolve(novelty, np.hanning(9) / np.sum(np.hanning(9)), mode='same')
            # Adaptive threshold: mean + 0.5*std
            threshold = np.mean(novelty) + 0.5 * np.std(novelty)
            peaks = []
            for idx in range(1, len(novelty) - 1):
                if novelty[idx] > novelty[idx - 1] and novelty[idx] > novelty[idx + 1] and novelty[idx] > threshold:
                    peaks.append(idx)
            if len(peaks) >= 2:
                boundaries_frames = np.array([0] + peaks + [chroma.shape[1] - 1])
        except Exception:
            boundaries_frames = None

    if boundaries_frames is None:
        # Fallback: agglomerative clustering
        try:
            n_clusters = max(3, min(10, int(duration / 30)))
            boundaries_frames = librosa.segment.agglomerative(chroma, k=n_clusters)
            # agglomerative returns cluster labels per frame; convert to boundary frames
            if boundaries_frames.ndim == 1 and len(boundaries_frames) == chroma.shape[1]:
                # These are cluster assignments; find change points
                change_points = [0]
                for idx in range(1, len(boundaries_frames)):
                    if boundaries_frames[idx] != boundaries_frames[idx - 1]:
                        change_points.append(idx)
                change_points.append(chroma.shape[1] - 1)
                boundaries_frames = np.array(change_points)
            else:
                # Already boundary indices
                boundaries_frames = np.concatenate([[0], boundaries_frames, [chroma.shape[1] - 1]])
        except Exception:
            # Ultimate fallback: evenly spaced boundaries
            n_segs = max(3, min(8, int(duration / 30)))
            boundaries_frames = np.linspace(0, chroma.shape[1] - 1, n_segs + 1, dtype=int)

    # Convert frames to times (hop_length=4096 was used for chroma)
    boundaries_times = librosa.frames_to_time(boundaries_frames, sr=sr, hop_length=4096)

    # Ensure boundaries start at 0 and end at duration
    if boundaries_times[0] > 0.5:
        boundaries_times = np.concatenate([[0.0], boundaries_times])
    else:
        boundaries_times[0] = 0.0
    if boundaries_times[-1] < duration - 0.5:
        boundaries_times = np.concatenate([boundaries_times, [duration]])
    else:
        boundaries_times[-1] = duration

    # Remove duplicates and sort
    boundaries_times = np.unique(boundaries_times)

    # Classify segments
    segments = classify_segments(boundaries_times, y, sr, rec)

    # Time signature and bar grid
    ts = _detect_time_signature(beat_times)
    bar_times = compute_bar_grid(beat_times, ts["beats_per_bar"])

    return {
        "segments": segments,
        "bar_times": bar_times.tolist(),
        "segment_count": len(segments),
        "time_signature": ts,
        "analysis_version": "2.0.0"
    }


# ---------------------------------------------------------------------------
# US-002: Loop Point Detection
# ---------------------------------------------------------------------------

def _chroma_similarity(y: np.ndarray, sr: int, t1: float, t2: float, window: float = 0.5) -> float:
    """Compute chroma cosine similarity between two time points."""
    hw = int(window * sr / 2)
    s1 = max(0, int(t1 * sr) - hw)
    e1 = min(len(y), int(t1 * sr) + hw)
    s2 = max(0, int(t2 * sr) - hw)
    e2 = min(len(y), int(t2 * sr) + hw)

    if e1 - s1 < sr // 8 or e2 - s2 < sr // 8:
        return 0.0

    c1 = np.mean(librosa.feature.chroma_cqt(y=y[s1:e1], sr=sr, hop_length=2048), axis=1)
    c2 = np.mean(librosa.feature.chroma_cqt(y=y[s2:e2], sr=sr, hop_length=2048), axis=1)
    n1, n2 = np.linalg.norm(c1), np.linalg.norm(c2)
    if n1 == 0 or n2 == 0:
        return 0.0
    return float(np.dot(c1, c2) / (n1 * n2))


def _energy_match(y: np.ndarray, sr: int, t1: float, t2: float, window: float = 0.5) -> float:
    """Compute energy similarity between two time points."""
    hw = int(window * sr / 2)
    s1 = max(0, int(t1 * sr) - hw)
    e1 = min(len(y), int(t1 * sr) + hw)
    s2 = max(0, int(t2 * sr) - hw)
    e2 = min(len(y), int(t2 * sr) + hw)

    if e1 - s1 < sr // 8 or e2 - s2 < sr // 8:
        return 0.0

    rms1 = float(np.mean(librosa.feature.rms(y=y[s1:e1])[0]))
    rms2 = float(np.mean(librosa.feature.rms(y=y[s2:e2])[0]))
    max_rms = max(rms1, rms2)
    if max_rms == 0:
        return 1.0
    return 1.0 - abs(rms1 - rms2) / max_rms


def _spectral_match(y: np.ndarray, sr: int, t1: float, t2: float, window: float = 0.5) -> float:
    """Compute spectral centroid similarity between two time points."""
    hw = int(window * sr / 2)
    s1 = max(0, int(t1 * sr) - hw)
    e1 = min(len(y), int(t1 * sr) + hw)
    s2 = max(0, int(t2 * sr) - hw)
    e2 = min(len(y), int(t2 * sr) + hw)

    if e1 - s1 < sr // 8 or e2 - s2 < sr // 8:
        return 0.0

    sc1 = float(np.mean(librosa.feature.spectral_centroid(y=y[s1:e1], sr=sr)[0]))
    sc2 = float(np.mean(librosa.feature.spectral_centroid(y=y[s2:e2], sr=sr)[0]))
    max_sc = max(sc1, sc2)
    if max_sc == 0:
        return 1.0
    return 1.0 - abs(sc1 - sc2) / max_sc


def compute_loop_quality(y: np.ndarray, sr: int, start: float, end: float) -> float:
    """Score a loop candidate: chroma*0.5 + energy*0.3 + spectral*0.2."""
    cs = _chroma_similarity(y, sr, start, end)
    em = _energy_match(y, sr, start, end)
    sm = _spectral_match(y, sr, start, end)
    return cs * 0.5 + em * 0.3 + sm * 0.2


def find_section_for_time(segments: List[Dict[str, Any]], t: float) -> str:
    """Find the section label for a given time position."""
    for seg in segments:
        if seg["start_time"] <= t < seg["end_time"]:
            return seg.get("label", seg.get("section_type", "unknown"))
    if segments:
        return segments[-1].get("label", "unknown")
    return "unknown"


def extract_loop_points(
    y: np.ndarray,
    sr: int,
    beat_times: np.ndarray,
    segments: List[Dict[str, Any]],
    bar_times: Optional[np.ndarray] = None,
    beats_per_bar: int = 4
) -> Dict[str, Any]:
    """US-002: Detect bar-aligned loop point candidates.

    Generates candidates for 1, 2, 4, 8, 16 bar lengths, scores each by
    chroma/energy/spectral similarity at loop boundaries.

    Args:
        y: Audio time series.
        sr: Sample rate.
        beat_times: Beat onset times.
        segments: Structural segments from extract_structure.
        bar_times: Pre-computed bar boundary times (optional).
        beats_per_bar: Beats per bar used for bar grid.

    Returns:
        {"recommended": top 5, "all": all with score >= 0.6}
    """
    if bar_times is None:
        bar_times = compute_bar_grid(beat_times, beats_per_bar)

    if len(bar_times) < 2:
        return {"recommended": [], "all": []}

    candidates: List[Dict[str, Any]] = []

    for bar_len in [1, 2, 4, 8, 16]:
        for i in range(len(bar_times) - bar_len):
            start_t = float(bar_times[i])
            end_idx = i + bar_len
            if end_idx >= len(bar_times):
                break
            end_t = float(bar_times[end_idx])
            if end_t - start_t < 0.5:
                continue

            score = compute_loop_quality(y, sr, start_t, end_t)
            section_label = find_section_for_time(segments, start_t)
            loop_beats = bar_len * beats_per_bar

            candidates.append({
                "loop_start_ms": int(start_t * 1000),
                "loop_end_ms": int(end_t * 1000),
                "loop_beats": loop_beats,
                "loop_bars": bar_len,
                "quality_score": round(float(score), 4),
                "section_label": section_label,
                "bar_aligned": True,
                "recommended": False  # will be set below
            })

    # Filter and sort
    passing = [c for c in candidates if c["quality_score"] >= 0.6]
    passing.sort(key=lambda x: x["quality_score"], reverse=True)

    # Deduplicate: keep highest score per unique (start, bars) pair
    seen = set()
    deduped: List[Dict[str, Any]] = []
    for c in passing:
        key = (c["loop_start_ms"], c["loop_bars"])
        if key not in seen:
            seen.add(key)
            deduped.append(c)

    # Top 5 recommended
    recommended = deduped[:5]
    for r in recommended:
        r["recommended"] = True

    return {
        "recommended": recommended,
        "all": deduped
    }


# ---------------------------------------------------------------------------
# US-003: Arrangement Markers
# ---------------------------------------------------------------------------

def detect_key_changes(
    y: np.ndarray,
    sr: int,
    window_sec: float = 4.0,
    hop_sec: float = 2.0,
    hysteresis: float = 0.15
) -> List[Dict[str, Any]]:
    """Detect key changes via windowed chroma analysis with hysteresis.

    Args:
        y: Audio time series.
        sr: Sample rate.
        window_sec: Analysis window size in seconds.
        hop_sec: Hop between windows (50% overlap by default).
        hysteresis: Minimum cosine distance to register a key change.

    Returns:
        List of key_change marker dicts.
    """
    pitch_classes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    win_samples = int(window_sec * sr)
    hop_samples = int(hop_sec * sr)

    markers: List[Dict[str, Any]] = []
    prev_key_idx: Optional[int] = None
    prev_mode: Optional[str] = None

    major_profile = np.array([1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1], dtype=float)
    minor_profile = np.array([1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0], dtype=float)

    pos = 0
    while pos + win_samples <= len(y):
        segment = y[pos:pos + win_samples]
        chroma = librosa.feature.chroma_cqt(y=segment, sr=sr, hop_length=2048)
        chroma_mean = np.mean(chroma, axis=1)
        chroma_norm = np.linalg.norm(chroma_mean)
        if chroma_norm == 0:
            pos += hop_samples
            continue

        # Find dominant key
        best_corr = -1.0
        best_key = 0
        best_mode = "major"
        for k in range(12):
            maj_corr = float(np.dot(np.roll(major_profile, k), chroma_mean)) / chroma_norm
            min_corr = float(np.dot(np.roll(minor_profile, k), chroma_mean)) / chroma_norm
            if maj_corr > best_corr:
                best_corr = maj_corr
                best_key = k
                best_mode = "major"
            if min_corr > best_corr:
                best_corr = min_corr
                best_key = k
                best_mode = "minor"

        time_sec = pos / sr

        if prev_key_idx is not None and (best_key != prev_key_idx or best_mode != prev_mode):
            # Compute cosine distance between previous and current chroma
            if chroma_norm > 0:
                # Use hysteresis to avoid spurious detections
                change_magnitude = 1.0 - best_corr  # rough proxy
                if change_magnitude >= hysteresis:
                    markers.append({
                        "marker_type": "key_change",
                        "position_ms": int(time_sec * 1000),
                        "position_end_ms": None,
                        "description": f"Key change to {pitch_classes[best_key]} {best_mode}",
                        "intensity": round(float(min(1.0, change_magnitude / 0.5)), 4),
                        "metadata": {
                            "from_key": f"{pitch_classes[prev_key_idx]} {prev_mode}",
                            "to_key": f"{pitch_classes[best_key]} {best_mode}",
                            "confidence": round(float(best_corr), 4)
                        }
                    })

        prev_key_idx = best_key
        prev_mode = best_mode
        pos += hop_samples

    return markers


def detect_energy_transitions(y: np.ndarray, sr: int, window_sec: float = 2.0) -> List[Dict[str, Any]]:
    """Detect energy rise and drop transitions via RMS gradient.

    Args:
        y: Audio time series.
        sr: Sample rate.
        window_sec: RMS analysis window.

    Returns:
        List of energy_rise / energy_drop marker dicts.
    """
    hop = int(window_sec * sr)
    rms_values = []
    times = []

    pos = 0
    while pos + hop <= len(y):
        rms_val = float(np.sqrt(np.mean(y[pos:pos + hop] ** 2)))
        rms_values.append(rms_val)
        times.append(pos / sr)
        pos += hop

    if len(rms_values) < 3:
        return []

    rms_arr = np.array(rms_values)
    gradient = np.gradient(rms_arr)
    grad_std = np.std(gradient)
    if grad_std == 0:
        return []

    markers: List[Dict[str, Any]] = []
    threshold = 1.0 * grad_std

    for i in range(1, len(gradient) - 1):
        if gradient[i] > threshold:
            markers.append({
                "marker_type": "energy_rise",
                "position_ms": int(times[i] * 1000),
                "position_end_ms": int(times[min(i + 1, len(times) - 1)] * 1000),
                "description": "Significant energy increase",
                "intensity": round(float(min(1.0, gradient[i] / (2 * grad_std))), 4),
                "metadata": {
                    "gradient": round(float(gradient[i]), 6),
                    "rms_before": round(float(rms_arr[i - 1]), 6),
                    "rms_after": round(float(rms_arr[i]), 6)
                }
            })
        elif gradient[i] < -threshold:
            markers.append({
                "marker_type": "energy_drop",
                "position_ms": int(times[i] * 1000),
                "position_end_ms": int(times[min(i + 1, len(times) - 1)] * 1000),
                "description": "Significant energy decrease",
                "intensity": round(float(min(1.0, abs(gradient[i]) / (2 * grad_std))), 4),
                "metadata": {
                    "gradient": round(float(gradient[i]), 6),
                    "rms_before": round(float(rms_arr[i - 1]), 6),
                    "rms_after": round(float(rms_arr[i]), 6)
                }
            })

    return markers


def detect_drops(y: np.ndarray, sr: int, window_sec: float = 1.0) -> List[Dict[str, Any]]:
    """Detect drops: energy dip followed by a spike.

    A 'drop' is defined as a frame where RMS drops below 0.3x the local mean
    and then rebounds above 1.5x within 2 windows.

    Args:
        y: Audio time series.
        sr: Sample rate.
        window_sec: RMS window size.

    Returns:
        List of drop marker dicts.
    """
    hop = int(window_sec * sr)
    rms_values = []
    times = []

    pos = 0
    while pos + hop <= len(y):
        rms_val = float(np.sqrt(np.mean(y[pos:pos + hop] ** 2)))
        rms_values.append(rms_val)
        times.append(pos / sr)
        pos += hop

    if len(rms_values) < 4:
        return []

    rms_arr = np.array(rms_values)
    mean_rms = np.mean(rms_arr)
    if mean_rms == 0:
        return []

    markers: List[Dict[str, Any]] = []

    for i in range(1, len(rms_arr) - 2):
        # Dip: current significantly lower than neighbors
        if rms_arr[i] < 0.3 * mean_rms:
            # Spike: one of the next 2 frames is significantly higher
            for j in range(1, min(3, len(rms_arr) - i)):
                if rms_arr[i + j] > 1.5 * mean_rms:
                    dip_ratio = rms_arr[i] / mean_rms
                    spike_ratio = rms_arr[i + j] / mean_rms
                    intensity = min(1.0, (spike_ratio - dip_ratio) / 2.0)
                    markers.append({
                        "marker_type": "drop",
                        "position_ms": int(times[i] * 1000),
                        "position_end_ms": int(times[i + j] * 1000),
                        "description": "Drop detected (energy dip then spike)",
                        "intensity": round(float(intensity), 4),
                        "metadata": {
                            "dip_rms": round(float(rms_arr[i]), 6),
                            "spike_rms": round(float(rms_arr[i + j]), 6),
                            "mean_rms": round(float(mean_rms), 6)
                        }
                    })
                    break  # Only one drop per dip

    return markers


def detect_buildups(y: np.ndarray, sr: int, window_sec: float = 2.0, min_frames: int = 3) -> List[Dict[str, Any]]:
    """Detect build-ups: sustained rising energy + spectral widening.

    A 'build_up' is a run of >= min_frames consecutive windows where both
    RMS and spectral bandwidth are increasing.

    Args:
        y: Audio time series.
        sr: Sample rate.
        window_sec: Analysis window size.
        min_frames: Minimum consecutive rising frames to qualify.

    Returns:
        List of build_up marker dicts.
    """
    hop = int(window_sec * sr)
    rms_values = []
    bw_values = []
    times = []

    pos = 0
    while pos + hop <= len(y):
        seg = y[pos:pos + hop]
        rms_val = float(np.sqrt(np.mean(seg ** 2)))
        bw = float(np.mean(librosa.feature.spectral_bandwidth(y=seg, sr=sr)[0]))
        rms_values.append(rms_val)
        bw_values.append(bw)
        times.append(pos / sr)
        pos += hop

    if len(rms_values) < min_frames + 1:
        return []

    rms_arr = np.array(rms_values)
    bw_arr = np.array(bw_values)

    markers: List[Dict[str, Any]] = []
    run_start: Optional[int] = None

    for i in range(1, len(rms_arr)):
        if rms_arr[i] > rms_arr[i - 1] and bw_arr[i] > bw_arr[i - 1]:
            if run_start is None:
                run_start = i - 1
        else:
            if run_start is not None and (i - run_start) >= min_frames:
                energy_increase = rms_arr[i - 1] / max(rms_arr[run_start], 1e-10)
                intensity = min(1.0, (energy_increase - 1.0) / 2.0)
                markers.append({
                    "marker_type": "build_up",
                    "position_ms": int(times[run_start] * 1000),
                    "position_end_ms": int(times[i - 1] * 1000),
                    "description": f"Build-up over {i - run_start} windows ({(i - run_start) * window_sec:.1f}s)",
                    "intensity": round(float(max(0.0, intensity)), 4),
                    "metadata": {
                        "duration_sec": round(float((i - run_start) * window_sec), 2),
                        "energy_increase_ratio": round(float(energy_increase), 4),
                        "start_rms": round(float(rms_arr[run_start]), 6),
                        "end_rms": round(float(rms_arr[i - 1]), 6)
                    }
                })
            run_start = None

    # Handle run that extends to end
    if run_start is not None and (len(rms_arr) - run_start) >= min_frames:
        energy_increase = rms_arr[-1] / max(rms_arr[run_start], 1e-10)
        intensity = min(1.0, (energy_increase - 1.0) / 2.0)
        markers.append({
            "marker_type": "build_up",
            "position_ms": int(times[run_start] * 1000),
            "position_end_ms": int(times[-1] * 1000),
            "description": f"Build-up over {len(rms_arr) - run_start} windows ({(len(rms_arr) - run_start) * window_sec:.1f}s)",
            "intensity": round(float(max(0.0, intensity)), 4),
            "metadata": {
                "duration_sec": round(float((len(rms_arr) - run_start) * window_sec), 2),
                "energy_increase_ratio": round(float(energy_increase), 4),
                "start_rms": round(float(rms_arr[run_start]), 6),
                "end_rms": round(float(rms_arr[-1]), 6)
            }
        })

    return markers


def extract_arrangement_markers(
    y: np.ndarray,
    sr: int,
    beat_times: np.ndarray,
    segments: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """US-003: Detect arrangement markers (key changes, energy transitions, drops, build-ups).

    Args:
        y: Audio time series.
        sr: Sample rate.
        beat_times: Beat onset times.
        segments: Structural segments.

    Returns:
        List of marker dicts sorted by position_ms.
    """
    markers: List[Dict[str, Any]] = []

    markers.extend(detect_key_changes(y, sr))
    markers.extend(detect_energy_transitions(y, sr))
    markers.extend(detect_drops(y, sr))
    markers.extend(detect_buildups(y, sr))

    # Sort by position
    markers.sort(key=lambda m: m["position_ms"])

    return markers


# ---------------------------------------------------------------------------
# US-004: Energy Curve
# ---------------------------------------------------------------------------

def extract_energy_curve(y: np.ndarray, sr: int, resolution: float = 0.5) -> Dict[str, Any]:
    """US-004: Compute a time-series energy curve at the given resolution.

    Args:
        y: Audio time series.
        sr: Sample rate.
        resolution: Time resolution in seconds (default 0.5s).

    Returns:
        {"times": [...], "values": [...]}
    """
    hop = max(1, int(sr * resolution))
    rms = librosa.feature.rms(y=y, hop_length=hop)[0]
    n_frames = len(rms)
    times = librosa.frames_to_time(np.arange(n_frames), sr=sr, hop_length=hop)

    return {
        "times": [round(float(t), 4) for t in times],
        "values": [round(float(v), 6) for v in rms]
    }


# ---------------------------------------------------------------------------
# Updated main analysis function
# ---------------------------------------------------------------------------

def analyze_audio(audio_path: str, features: List[str]) -> Dict[str, Any]:
    """
    Main analysis function - extracts requested features from audio

    Args:
        audio_path: Path to audio file
        features: List of features to extract

    Returns:
        Dictionary containing all extracted features
    """
    # Validate audio file
    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    # Load audio file
    try:
        y, sr = librosa.load(audio_path, sr=None, mono=True)
    except Exception as e:
        raise ValueError(f"Failed to load audio file: {str(e)}")

    # Get duration
    duration = librosa.get_duration(y=y, sr=sr)

    # Initialize results
    results: Dict[str, Any] = {
        "duration": float(duration),
        "sample_rate": int(sr),
        "samples": len(y)
    }

    # Determine which features to extract
    extract_all = 'all' in features

    # -----------------------------------------------------------------------
    # Dependency resolution: some new features depend on others
    # Keep track of intermediate results to avoid redundant computation.
    # -----------------------------------------------------------------------
    _tempo_data: Optional[Dict[str, Any]] = None
    _beat_times: Optional[np.ndarray] = None
    _structure_data: Optional[Dict[str, Any]] = None
    _segments: Optional[List[Dict[str, Any]]] = None
    _bar_times: Optional[np.ndarray] = None
    _beats_per_bar: int = 4

    def _ensure_tempo() -> None:
        nonlocal _tempo_data, _beat_times
        if _tempo_data is not None:
            return
        _tempo_data = extract_tempo(y, sr)
        _beat_times = np.array(_tempo_data["beats"])

    def _ensure_structure() -> None:
        nonlocal _structure_data, _segments, _bar_times, _beats_per_bar
        if _structure_data is not None:
            return
        _ensure_tempo()
        assert _beat_times is not None
        _structure_data = extract_structure(y, sr, _beat_times)
        _segments = _structure_data["segments"]
        _bar_times = np.array(_structure_data["bar_times"])
        _beats_per_bar = _structure_data["time_signature"]["beats_per_bar"]

    # -----------------------------------------------------------------------
    # Original features
    # -----------------------------------------------------------------------
    if extract_all or 'tempo' in features:
        _ensure_tempo()
        assert _tempo_data is not None
        results.update(_tempo_data)

    if extract_all or 'key' in features:
        results.update(extract_key(y, sr))

    if extract_all or 'energy' in features:
        results.update(extract_energy(y, sr))

    if extract_all or 'spectral' in features:
        results.update(extract_spectral(y, sr))

    if extract_all or 'mfcc' in features:
        results.update(extract_mfcc(y, sr))

    if extract_all or 'chroma' in features:
        results.update(extract_chroma(y, sr))

    # -----------------------------------------------------------------------
    # US-001: Structure
    # -----------------------------------------------------------------------
    if extract_all or 'structure' in features:
        _ensure_structure()
        assert _structure_data is not None
        results["structure"] = _structure_data
        # Also ensure tempo is in results (auto-dependency)
        if "tempo" not in results and _tempo_data is not None:
            results.update(_tempo_data)

    # -----------------------------------------------------------------------
    # US-002: Loop Points (depends on structure)
    # -----------------------------------------------------------------------
    if extract_all or 'loop_points' in features:
        _ensure_structure()
        assert _beat_times is not None and _segments is not None
        results["loop_points"] = extract_loop_points(
            y, sr, _beat_times, _segments,
            bar_times=_bar_times, beats_per_bar=_beats_per_bar
        )

    # -----------------------------------------------------------------------
    # US-003: Arrangement Markers (depends on tempo + structure)
    # -----------------------------------------------------------------------
    if extract_all or 'arrangement' in features:
        _ensure_structure()
        assert _beat_times is not None and _segments is not None
        results["arrangement_markers"] = extract_arrangement_markers(
            y, sr, _beat_times, _segments
        )

    # -----------------------------------------------------------------------
    # US-003b: Auto Cues (arrangement markers formatted as cue points)
    # -----------------------------------------------------------------------
    if extract_all or 'auto_cues' in features:
        _ensure_structure()
        assert _beat_times is not None and _segments is not None
        raw_markers = extract_arrangement_markers(y, sr, _beat_times, _segments)

        # Also include structure segment boundaries as cue candidates
        cue_color_map = {
            "key_change": "#9B59B6",   # purple
            "energy_rise": "#E74C3C",  # red
            "energy_drop": "#3498DB",  # blue
            "drop": "#F39C12",         # orange
            "build_up": "#2ECC71",     # green
            "intro": "#1ABC9C",        # teal
            "verse": "#2980B9",        # dark blue
            "chorus": "#E91E63",       # pink
            "bridge": "#FF9800",       # amber
            "outro": "#607D8B",        # grey
        }

        auto_cues = []
        # Convert arrangement markers to cue points
        for marker in raw_markers:
            cue_type = marker.get("marker_type", "unknown")
            color = cue_color_map.get(cue_type, "#95A5A6")
            confidence = marker.get("intensity", 0.5)
            # Use metadata confidence if available (e.g. key_change)
            if "metadata" in marker and "confidence" in marker["metadata"]:
                confidence = marker["metadata"]["confidence"]
            auto_cues.append({
                "position_ms": marker["position_ms"],
                "label": marker.get("description", cue_type),
                "cue_type": cue_type,
                "color": color,
                "confidence": round(float(confidence), 4),
            })

        # Add structure segment boundaries as cues
        if _segments:
            for seg in _segments:
                seg_type = seg.get("label", "unknown").lower()
                color = cue_color_map.get(seg_type, "#95A5A6")
                auto_cues.append({
                    "position_ms": int(seg.get("start_ms", seg.get("start", 0) * 1000)),
                    "label": f"{seg.get('label', 'Section')} start",
                    "cue_type": seg_type,
                    "color": color,
                    "confidence": round(float(seg.get("confidence", 0.7)), 4),
                })

        # Deduplicate: keep highest confidence when cues are within 500ms
        auto_cues.sort(key=lambda c: c["position_ms"])
        deduped: List[Dict[str, Any]] = []
        for cue in auto_cues:
            if deduped and abs(cue["position_ms"] - deduped[-1]["position_ms"]) < 500:
                if cue["confidence"] > deduped[-1]["confidence"]:
                    deduped[-1] = cue
            else:
                deduped.append(cue)

        results["auto_cues"] = deduped

    # -----------------------------------------------------------------------
    # US-004: Energy Curve
    # -----------------------------------------------------------------------
    if extract_all or 'energy_curve' in features:
        results["energy_curve"] = extract_energy_curve(y, sr)

    return results


def main():
    """
    Main entry point for audio analyzer
    """
    parser = argparse.ArgumentParser(
        description='Audio Feature Extraction using librosa',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/audio.mp3 --features tempo,key,energy
  %(prog)s /path/to/audio.mp3 --features all --output json
  %(prog)s /path/to/audio.mp3 --features tempo --output pretty
  %(prog)s /path/to/audio.mp3 --features structure,loop_points,arrangement,energy_curve
        """
    )

    parser.add_argument(
        'audio_file',
        help='Path to audio file to analyze'
    )

    parser.add_argument(
        '--features',
        type=str,
        default='tempo,key,energy',
        help='Comma-separated list of features to extract (default: tempo,key,energy)'
    )

    parser.add_argument(
        '--output',
        choices=['json', 'pretty'],
        default='json',
        help='Output format (default: json)'
    )

    args = parser.parse_args()

    # Parse features
    features = [f.strip() for f in args.features.split(',')]

    # Validate features
    valid_features = {
        'tempo', 'key', 'energy', 'spectral', 'mfcc', 'chroma',
        'structure', 'loop_points', 'arrangement', 'energy_curve',
        'auto_cues', 'all'
    }
    invalid_features = set(features) - valid_features
    if invalid_features:
        print(json.dumps({
            "error": "Invalid features",
            "invalid": list(invalid_features),
            "valid": sorted(list(valid_features))
        }), file=sys.stderr)
        sys.exit(1)

    try:
        # Analyze audio
        results = analyze_audio(args.audio_file, features)

        # Output results
        if args.output == 'json':
            print(json.dumps(results))
        else:  # pretty
            print(json.dumps(results, indent=2))

        sys.exit(0)

    except FileNotFoundError as e:
        print(json.dumps({
            "error": "File not found",
            "message": str(e)
        }), file=sys.stderr)
        sys.exit(1)

    except ValueError as e:
        print(json.dumps({
            "error": "Invalid audio file",
            "message": str(e)
        }), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        print(json.dumps({
            "error": "Analysis failed",
            "message": str(e),
            "type": type(e).__name__
        }), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
