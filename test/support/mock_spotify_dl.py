#!/usr/bin/env python3
"""Mock spotify_dl.py for testing."""

import sys
import json
import os
import argparse


def emit(data):
    print(json.dumps(data), flush=True)


def emit_error(data):
    print(json.dumps(data), file=sys.stderr, flush=True)


def cmd_metadata(args):
    url = args.url
    if "invalid" in url or "not-a-spotify" in url:
        emit_error({"error": "Invalid Spotify URL"})
        sys.exit(1)

    # Playlist URLs return the new format with per-track cover art
    if "playlist" in url:
        emit({
            "playlist": {
                "name": "Test Playlist",
                "cover": "https://example.com/playlist-mosaic.jpg",
                "spotify_id": "pl_test123",
            },
            "tracks": [
                {
                    "name": "Playlist Track 1",
                    "artists": ["Artist A"],
                    "album_name": "",
                    "album_artist": "Artist A",
                    "duration": 200,
                    "song_id": "pt1",
                    "cover_url": "https://example.com/album-art-1.jpg",
                    "url": "https://open.spotify.com/track/pt1",
                    "disc_number": 1,
                    "track_number": 1,
                    "isrc": "",
                },
                {
                    "name": "Playlist Track 2",
                    "artists": ["Artist B"],
                    "album_name": "",
                    "album_artist": "Artist B",
                    "duration": 240,
                    "song_id": "pt2",
                    "cover_url": "https://example.com/album-art-2.jpg",
                    "url": "https://open.spotify.com/track/pt2",
                    "disc_number": 1,
                    "track_number": 2,
                    "isrc": "",
                },
            ],
        })
        return

    emit([
        {
            "name": "Test Song",
            "artists": ["Test Artist"],
            "album_name": "Test Album",
            "album_artist": "Test Artist",
            "duration": 180,
            "song_id": "abc123",
            "cover_url": "https://example.com/art.jpg",
            "url": "https://open.spotify.com/track/abc123",
            "disc_number": 1,
            "track_number": 1,
            "isrc": "USRC12345678",
        }
    ])


def cmd_download(args):
    url = args.url
    if "fail" in url:
        emit_error({"error": "Download failed"})
        sys.exit(1)

    output_dir = args.output_dir or "/tmp"
    template = args.output_template or "test_track"
    fmt = args.format or "mp3"
    path = os.path.join(output_dir, f"{template}.{fmt}")

    os.makedirs(output_dir, exist_ok=True)

    # Create a fake MP3 with ID3 header
    with open(path, "wb") as f:
        f.write(b"ID3")
        f.write(os.urandom(2048))

    size = os.path.getsize(path)
    emit({"path": path, "size": size, "metadata": {"name": "Test Song"}})


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    meta_parser = subparsers.add_parser("metadata")
    meta_parser.add_argument("url")

    dl_parser = subparsers.add_parser("download")
    dl_parser.add_argument("url")
    dl_parser.add_argument("--output-dir")
    dl_parser.add_argument("--output-template")
    dl_parser.add_argument("--format", default="mp3")
    dl_parser.add_argument("--bitrate", default="320k")

    args = parser.parse_args()

    if args.command == "metadata":
        cmd_metadata(args)
    elif args.command == "download":
        cmd_download(args)


if __name__ == "__main__":
    main()
