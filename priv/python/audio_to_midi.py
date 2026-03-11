#!/usr/bin/env python3
"""
Audio-to-MIDI Converter - basic-pitch based note detection

Accepts an audio file path and returns MIDI note data as JSON.
Uses Spotify's basic-pitch library for polyphonic audio-to-MIDI conversion.

Usage:
    python3 audio_to_midi.py <audio_path>
"""

import sys
import json
import warnings

warnings.filterwarnings('ignore')

try:
    from basic_pitch.inference import predict
    from basic_pitch import ICASSP_2022_MODEL_PATH
    import numpy as np
except ImportError as e:
    print(json.dumps({
        "error": "Missing dependencies",
        "message": str(e),
        "details": "Please install: pip install basic-pitch"
    }), file=sys.stderr)
    sys.exit(1)


def convert(file_path):
    """
    Convert audio file to MIDI note data.

    Args:
        file_path: Path to audio file (WAV, MP3, etc.)

    Returns:
        List of note dicts with note, onset, offset, velocity, confidence
    """
    model_output, midi_data, note_events = predict(file_path)

    notes = []
    for start_time, end_time, pitch, velocity, confidence in note_events:
        notes.append({
            "note": int(pitch),
            "onset": round(float(start_time), 4),
            "offset": round(float(end_time), 4),
            "velocity": round(float(velocity), 4),
            "confidence": round(float(confidence), 4)
        })

    # Sort by onset time
    notes.sort(key=lambda n: n["onset"])

    return notes


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: audio_to_midi.py <audio_path>"}), file=sys.stderr)
        sys.exit(1)

    audio_path = sys.argv[1]

    try:
        result = convert(audio_path)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({
            "error": "conversion_failed",
            "message": str(e)
        }), file=sys.stderr)
        sys.exit(1)
