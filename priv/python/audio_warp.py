#!/usr/bin/env python3
"""
Audio Warp - pyrubberband-based time-stretching and pitch-shifting

Supports independent time-stretch and pitch-shift operations on audio files.

Usage:
    python3 audio_warp.py <input_path> <output_path> [--tempo-factor=1.0] [--pitch-semitones=0]
"""

import sys
import json
import argparse
import warnings

warnings.filterwarnings('ignore')

try:
    import soundfile as sf
    import numpy as np
    import pyrubberband as pyrb
except ImportError as e:
    print(json.dumps({
        "error": "Missing dependencies",
        "message": str(e),
        "details": "Please install: pip install pyrubberband soundfile numpy"
    }), file=sys.stderr)
    sys.exit(1)


def warp(file_path, output_path, tempo_factor=1.0, pitch_semitones=0):
    """
    Warp an audio file with independent time-stretch and pitch-shift.

    Args:
        file_path: Input audio path (WAV)
        output_path: Output audio path (WAV)
        tempo_factor: Speed multiplier (1.0 = original, 2.0 = double speed, 0.5 = half speed)
        pitch_semitones: Pitch shift in semitones (positive = up, negative = down)

    Returns:
        Dict with success, output_path, duration
    """
    y, sr = sf.read(file_path)

    # Apply time-stretching if needed
    if abs(tempo_factor - 1.0) > 0.001:
        y = pyrb.time_stretch(y, sr, tempo_factor)

    # Apply pitch-shifting if needed
    if abs(pitch_semitones) > 0.001:
        y = pyrb.pitch_shift(y, sr, pitch_semitones)

    sf.write(output_path, y, sr)

    duration = len(y) / sr if y.ndim == 1 else len(y) / sr

    return {
        "success": True,
        "output_path": output_path,
        "duration": round(float(duration), 4)
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Audio warp: time-stretch and pitch-shift")
    parser.add_argument("input_path", help="Input audio file path")
    parser.add_argument("output_path", help="Output audio file path")
    parser.add_argument("--tempo-factor", type=float, default=1.0, help="Speed multiplier")
    parser.add_argument("--pitch-semitones", type=float, default=0, help="Pitch shift in semitones")
    args = parser.parse_args()

    try:
        result = warp(args.input_path, args.output_path, args.tempo_factor, args.pitch_semitones)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({
            "error": "warp_failed",
            "message": str(e)
        }), file=sys.stderr)
        sys.exit(1)
