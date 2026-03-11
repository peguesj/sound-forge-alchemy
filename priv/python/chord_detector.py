#!/usr/bin/env python3
"""
Chord Detector - librosa chroma-based chord detection

Analyzes audio and detects chord progressions using chroma features
and template matching against common chord types.

Usage:
    python3 chord_detector.py <audio_path>
"""

import sys
import json
import warnings

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

# Chord templates: 12 pitch classes (C, C#, D, ..., B)
# Each template is a binary mask of which pitch classes are active
NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

CHORD_TEMPLATES = {}

def _build_templates():
    """Build chord templates for all roots and chord qualities."""
    qualities = {
        'maj': [0, 4, 7],
        'min': [0, 3, 7],
        'dim': [0, 3, 6],
        'aug': [0, 4, 8],
        '7': [0, 4, 7, 10],
        'maj7': [0, 4, 7, 11],
        'min7': [0, 3, 7, 10],
    }

    for root_idx, root_name in enumerate(NOTE_NAMES):
        for qual_name, intervals in qualities.items():
            template = np.zeros(12)
            for interval in intervals:
                template[(root_idx + interval) % 12] = 1.0
            # Normalize
            template /= np.linalg.norm(template)

            if qual_name == 'maj':
                chord_label = root_name
            elif qual_name == 'min':
                chord_label = f"{root_name}m"
            else:
                chord_label = f"{root_name}{qual_name}"

            CHORD_TEMPLATES[chord_label] = template

_build_templates()


def _detect_key(chroma_mean):
    """Detect the overall key from mean chroma vector using Krumhansl profiles."""
    major_profile = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
    minor_profile = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

    best_corr = -1
    best_key = "C"

    for shift in range(12):
        maj_shifted = np.roll(major_profile, shift)
        corr_maj = np.corrcoef(chroma_mean, maj_shifted)[0, 1]
        if corr_maj > best_corr:
            best_corr = corr_maj
            best_key = NOTE_NAMES[shift]

        min_shifted = np.roll(minor_profile, shift)
        corr_min = np.corrcoef(chroma_mean, min_shifted)[0, 1]
        if corr_min > best_corr:
            best_corr = corr_min
            best_key = f"{NOTE_NAMES[shift]}m"

    return best_key


def detect(file_path, hop_length=512, min_duration=0.3):
    """
    Detect chord progressions from audio file.

    Args:
        file_path: Path to audio file
        hop_length: Hop length for chroma extraction
        min_duration: Minimum chord duration in seconds

    Returns:
        Dict with 'chords' list and 'key' string
    """
    y, sr = librosa.load(file_path, sr=22050, mono=True)
    duration = librosa.get_duration(y=y, sr=sr)

    # CQT chroma for better harmonic resolution
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=hop_length)

    # Smooth chroma to reduce noise
    chroma_smooth = librosa.decompose.nn_filter(chroma, aggregate=np.median, metric='cosine')
    chroma_smooth = np.maximum(chroma_smooth, 0)

    # Detect key from mean chroma
    chroma_mean = np.mean(chroma_smooth, axis=1)
    key = _detect_key(chroma_mean)

    # Match each frame to a chord template
    frame_times = librosa.frames_to_time(np.arange(chroma_smooth.shape[1]), sr=sr, hop_length=hop_length)
    frame_chords = []

    for i in range(chroma_smooth.shape[1]):
        frame_chroma = chroma_smooth[:, i]
        norm = np.linalg.norm(frame_chroma)
        if norm < 0.01:
            frame_chords.append(("N", 0.0))  # No chord / silence
            continue

        frame_norm = frame_chroma / norm
        best_chord = "N"
        best_sim = 0.0

        for chord_name, template in CHORD_TEMPLATES.items():
            sim = float(np.dot(frame_norm, template))
            if sim > best_sim:
                best_sim = sim
                best_chord = chord_name

        frame_chords.append((best_chord, best_sim))

    # Merge consecutive identical chords
    chords = []
    if frame_chords:
        current_chord, current_conf = frame_chords[0]
        start_time = frame_times[0] if len(frame_times) > 0 else 0.0
        confidences = [current_conf]

        for i in range(1, len(frame_chords)):
            chord, conf = frame_chords[i]
            if chord == current_chord:
                confidences.append(conf)
            else:
                end_time = frame_times[i] if i < len(frame_times) else duration
                dur = end_time - start_time
                if dur >= min_duration and current_chord != "N":
                    chords.append({
                        "chord": current_chord,
                        "start": round(float(start_time), 4),
                        "end": round(float(end_time), 4),
                        "confidence": round(float(np.mean(confidences)), 4)
                    })
                current_chord = chord
                start_time = frame_times[i] if i < len(frame_times) else end_time
                confidences = [conf]

        # Last segment
        end_time = duration
        dur = end_time - start_time
        if dur >= min_duration and current_chord != "N":
            chords.append({
                "chord": current_chord,
                "start": round(float(start_time), 4),
                "end": round(float(end_time), 4),
                "confidence": round(float(np.mean(confidences)), 4)
            })

    return {"chords": chords, "key": key}


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: chord_detector.py <audio_path>"}), file=sys.stderr)
        sys.exit(1)

    audio_path = sys.argv[1]

    try:
        result = detect(audio_path)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({
            "error": "detection_failed",
            "message": str(e)
        }), file=sys.stderr)
        sys.exit(1)
