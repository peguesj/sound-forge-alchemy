#!/usr/bin/env python3
"""
loop_extractor.py — Extract a loop segment from an audio file.

Usage:
  python3 loop_extractor.py --input <path> --start <seconds> --end <seconds> --output <path>

Arguments:
  --input   Path to the source audio file (WAV, MP3, AIFF, FLAC)
  --start   Start time in seconds (float)
  --end     End time in seconds (float)
  --output  Path to write the extracted WAV segment

Output:
  Writes a lossless WAV file to --output.
  Prints JSON result to stdout:
    {"ok": true, "output": "/path/to/output.wav", "duration_ms": 4000}
    or
    {"ok": false, "error": "error message"}

Exit codes:
  0 — success
  1 — error
"""

import argparse
import json
import sys
import os


def main():
    parser = argparse.ArgumentParser(description="Extract a loop segment from an audio file")
    parser.add_argument("--input", required=True, help="Input audio file path")
    parser.add_argument("--start", required=True, type=float, help="Start time in seconds")
    parser.add_argument("--end", required=True, type=float, help="End time in seconds")
    parser.add_argument("--output", required=True, help="Output WAV file path")
    args = parser.parse_args()

    try:
        from pydub import AudioSegment
    except ImportError:
        error_result(1, "pydub not available — install with: pip install pydub")
        return

    if not os.path.isfile(args.input):
        error_result(1, f"Input file not found: {args.input}")
        return

    if args.end <= args.start:
        error_result(1, f"end ({args.end}) must be greater than start ({args.start})")
        return

    try:
        # Load audio — pydub auto-detects format from extension
        audio = AudioSegment.from_file(args.input)

        # Convert seconds to milliseconds
        start_ms = int(args.start * 1000)
        end_ms = int(args.end * 1000)

        # Clamp to actual audio duration
        duration_ms = len(audio)
        start_ms = max(0, min(start_ms, duration_ms))
        end_ms = max(start_ms + 1, min(end_ms, duration_ms))

        # Slice the segment
        segment = audio[start_ms:end_ms]

        # Ensure output directory exists
        output_dir = os.path.dirname(args.output)
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)

        # Export as lossless WAV
        segment.export(args.output, format="wav")

        actual_duration_ms = len(segment)
        result = {
            "ok": True,
            "output": args.output,
            "duration_ms": actual_duration_ms,
            "start_ms": start_ms,
            "end_ms": end_ms
        }
        print(json.dumps(result))
        sys.exit(0)

    except Exception as e:
        error_result(1, str(e))


def error_result(code, message):
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(code)


if __name__ == "__main__":
    main()
