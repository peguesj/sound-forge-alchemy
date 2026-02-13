#!/usr/bin/env python3
"""
Demucs Runner - Stem Separation Wrapper

@description Wraps Demucs for stem separation with progress reporting
@features Stem separation (vocals, drums, bass, other)
@author Sound Forge Alchemy Team
@version 2.0.0
@license MIT
"""

import sys
import json
import subprocess
import os
import argparse
from pathlib import Path


def run_demucs(audio_path: str, model: str = "htdemucs", output_dir: str = "/tmp/demucs"):
    """
    Run Demucs stem separation on an audio file

    Args:
        audio_path: Path to the audio file to process
        model: Demucs model to use (htdemucs, htdemucs_ft, mdx_extra)
        output_dir: Directory to store output stems

    Returns:
        Dictionary containing paths to separated stems
    """
    # Validate input file
    if not os.path.exists(audio_path):
        error_msg = json.dumps({
            "type": "error",
            "message": f"Audio file not found: {audio_path}"
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    # Create output directory
    try:
        os.makedirs(output_dir, exist_ok=True)
    except Exception as e:
        error_msg = json.dumps({
            "type": "error",
            "message": f"Failed to create output directory: {str(e)}"
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    # Build Demucs command using the same Python that's running this script
    cmd = [
        sys.executable, "-m", "demucs",
        "--mp3",           # Output as MP3
        "-n", model,       # Model name
        "-o", output_dir,  # Output directory
        audio_path         # Input audio file
    ]

    # Report progress - starting
    print(json.dumps({
        "type": "progress",
        "percent": 0,
        "message": "Starting Demucs stem separation"
    }))

    # Run Demucs
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Monitor process output
        for line in process.stderr:
            # Demucs outputs progress to stderr
            if "%" in line:
                # Try to extract percentage
                try:
                    parts = line.split("%")
                    if len(parts) > 0:
                        percent_str = parts[0].strip().split()[-1]
                        percent = int(float(percent_str))
                        print(json.dumps({
                            "type": "progress",
                            "percent": percent,
                            "message": f"Processing: {percent}%"
                        }))
                except (ValueError, IndexError):
                    pass

        stdout, stderr = process.communicate()

        if process.returncode != 0:
            error_msg = json.dumps({
                "type": "error",
                "message": f"Demucs failed with exit code {process.returncode}",
                "stderr": stderr
            })
            print(error_msg, file=sys.stderr)
            sys.exit(1)

    except FileNotFoundError:
        error_msg = json.dumps({
            "type": "error",
            "message": "Demucs not found. Please install: pip install demucs"
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_msg = json.dumps({
            "type": "error",
            "message": f"Demucs execution failed: {str(e)}"
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    # Locate output stems
    track_name = Path(audio_path).stem
    stem_dir = os.path.join(output_dir, model, track_name)

    if not os.path.exists(stem_dir):
        error_msg = json.dumps({
            "type": "error",
            "message": f"Output directory not found: {stem_dir}"
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    # Find stem files - stem types depend on model
    stems = {}
    if model == "htdemucs_6s":
        stem_types = ["vocals", "drums", "bass", "guitar", "piano", "other"]
    else:
        stem_types = ["vocals", "drums", "bass", "other"]

    for stem_type in stem_types:
        stem_path = os.path.join(stem_dir, f"{stem_type}.mp3")
        if os.path.exists(stem_path):
            stems[stem_type] = stem_path
        else:
            # Try without extension
            stem_path_no_ext = os.path.join(stem_dir, stem_type)
            if os.path.exists(stem_path_no_ext):
                stems[stem_type] = stem_path_no_ext

    # Verify we got all expected stems
    expected = len(stem_types)
    if len(stems) != expected:
        error_msg = json.dumps({
            "type": "error",
            "message": f"Expected {expected} stems, found {len(stems)}",
            "found": list(stems.keys())
        })
        print(error_msg, file=sys.stderr)
        sys.exit(1)

    # Report success
    result = json.dumps({
        "type": "result",
        "stems": stems,
        "model": model,
        "output_dir": stem_dir
    })
    print(result)
    sys.exit(0)


def main():
    """
    Main entry point for Demucs runner
    """
    parser = argparse.ArgumentParser(
        description='Demucs Stem Separation Wrapper',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/audio.mp3
  %(prog)s /path/to/audio.mp3 --model htdemucs_ft
  %(prog)s /path/to/audio.mp3 --output /custom/output/dir
        """
    )

    parser.add_argument(
        'audio_file',
        help='Path to audio file to process'
    )

    parser.add_argument(
        '--model',
        type=str,
        default='htdemucs',
        choices=['htdemucs', 'htdemucs_ft', 'htdemucs_6s', 'mdx_extra'],
        help='Demucs model to use (default: htdemucs)'
    )

    parser.add_argument(
        '--output',
        type=str,
        default='/tmp/demucs',
        help='Output directory for stems (default: /tmp/demucs)'
    )

    args = parser.parse_args()

    # Run Demucs
    run_demucs(args.audio_file, args.model, args.output)


if __name__ == "__main__":
    main()
