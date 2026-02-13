#!/usr/bin/env python3
"""
Audio Analyzer - Librosa-based Feature Extraction

@description Extracts audio features using librosa for Sound Forge Alchemy
@features tempo, key, energy, spectral, mfcc, chroma, beat tracking
@author Sound Forge Alchemy Team
@version 2.0.0
@license MIT
"""

import sys
import json
import argparse
import os
import warnings
from typing import Dict, List, Any, Optional

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
    # This is a simplified approach - production should use more sophisticated methods
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

    # Extract features
    if extract_all or 'tempo' in features:
        results.update(extract_tempo(y, sr))

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
    valid_features = {'tempo', 'key', 'energy', 'spectral', 'mfcc', 'chroma', 'all'}
    invalid_features = set(features) - valid_features
    if invalid_features:
        print(json.dumps({
            "error": "Invalid features",
            "invalid": list(invalid_features),
            "valid": list(valid_features)
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
