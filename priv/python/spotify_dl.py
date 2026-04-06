#!/usr/bin/env python3
"""
Spotify Download Helper - Metadata & Audio Download

Replaces the spotdl CLI which hangs due to Spotify deprecating the
audio_features endpoint (returns 403, causing spotdl to retry for 86400s).

Uses spotipy for metadata and yt-dlp for audio downloading directly.

@author Sound Forge Alchemy Team
@version 1.0.0
@license MIT
"""

import sys
import json
import os
import re
import argparse
import tempfile
from pathlib import Path

# Flush stdout for Erlang Port communication
def emit(data):
    """Print JSON to stdout with explicit flush."""
    print(json.dumps(data), flush=True)


def emit_error(data):
    """Print JSON error to stderr with explicit flush."""
    print(json.dumps(data), file=sys.stderr, flush=True)


def get_spotify_client():
    """Create authenticated Spotify client using environment variables."""
    import spotipy
    from spotipy.oauth2 import SpotifyClientCredentials

    client_id = os.environ.get("SPOTIPY_CLIENT_ID", "")
    client_secret = os.environ.get("SPOTIPY_CLIENT_SECRET", "")

    if not client_id or not client_secret:
        raise ValueError(
            "SPOTIPY_CLIENT_ID and SPOTIPY_CLIENT_SECRET must be set"
        )

    return spotipy.Spotify(
        auth_manager=SpotifyClientCredentials(
            client_id=client_id, client_secret=client_secret
        )
    )


def extract_spotify_info(url):
    """Extract type and ID from a Spotify URL."""
    pattern = r"spotify\.com/(track|album|playlist)/([a-zA-Z0-9]+)"
    match = re.search(pattern, url)
    if not match:
        return None, None
    return match.group(1), match.group(2)


def fetch_track_metadata(sp, track_id):
    """Fetch metadata for a single track."""
    track = sp.track(track_id)
    return {
        "name": track["name"],
        "artists": [a["name"] for a in track["artists"]],
        "album_name": track["album"]["name"],
        "album_artist": track["album"]["artists"][0]["name"] if track["album"]["artists"] else "",
        "duration": track["duration_ms"] / 1000,
        "song_id": track["id"],
        "cover_url": track["album"]["images"][0]["url"] if track["album"]["images"] else "",
        "url": track["external_urls"]["spotify"],
        "disc_number": track.get("disc_number", 1),
        "track_number": track.get("track_number", 1),
        "isrc": track.get("external_ids", {}).get("isrc", ""),
    }


def fetch_album_metadata(sp, album_id):
    """Fetch metadata for all tracks in an album."""
    album = sp.album(album_id)
    tracks = []
    for item in album["tracks"]["items"]:
        tracks.append({
            "name": item["name"],
            "artists": [a["name"] for a in item["artists"]],
            "album_name": album["name"],
            "album_artist": album["artists"][0]["name"] if album["artists"] else "",
            "duration": item["duration_ms"] / 1000,
            "song_id": item["id"],
            "cover_url": album["images"][0]["url"] if album["images"] else "",
            "url": item["external_urls"]["spotify"],
            "disc_number": item.get("disc_number", 1),
            "track_number": item.get("track_number", 1),
        })
    return tracks


def _parse_embed_page(content_type, content_id):
    """Fetch and parse the Spotify embed page __NEXT_DATA__ JSON.

    Works without any API credentials for public content.
    Returns the ``entity`` dict from the embed page state.
    """
    import requests

    embed_url = f"https://open.spotify.com/embed/{content_type}/{content_id}"
    resp = requests.get(embed_url, headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
    resp.raise_for_status()

    match = re.search(
        r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', resp.text
    )
    if not match:
        raise ValueError(f"Could not parse {content_type} embed page for {content_id}")

    embed_data = json.loads(match.group(1))
    return embed_data["props"]["pageProps"]["state"]["data"]["entity"]


def _embed_duration_seconds(raw):
    """Convert embed page duration field to seconds.

    The embed page may return duration as a plain integer (milliseconds) or
    as ``{"totalMilliseconds": N}``.
    """
    if isinstance(raw, dict):
        return raw.get("totalMilliseconds", 0) / 1000
    return (raw or 0) / 1000


def fetch_track_metadata_no_creds(track_id):
    """Fetch metadata for a single track via embed page (no API credentials)."""
    entity = _parse_embed_page("track", track_id)

    cover_url = ""
    if entity.get("coverArt", {}).get("sources"):
        cover_url = entity["coverArt"]["sources"][0].get("url", "")

    artists_str = entity.get("subtitle", "")
    artists = [a.strip() for a in artists_str.split(",") if a.strip()]

    album_name = ""
    if entity.get("albumOfTrack"):
        album_name = entity["albumOfTrack"].get("name", "")

    return {
        "name": entity.get("title", ""),
        "artists": artists,
        "album_name": album_name,
        "album_artist": artists[0] if artists else "",
        "duration": _embed_duration_seconds(entity.get("duration", 0)),
        "song_id": track_id,
        "cover_url": cover_url,
        "url": f"https://open.spotify.com/track/{track_id}",
        "disc_number": 1,
        "track_number": 1,
        "isrc": "",
    }


def fetch_album_metadata_no_creds(album_id):
    """Fetch metadata for all tracks in an album via embed page (no API credentials)."""
    entity = _parse_embed_page("album", album_id)

    album_name = entity.get("title", "")
    album_artist_str = entity.get("subtitle", "")
    album_artist = album_artist_str.split(",")[0].strip() if album_artist_str else ""

    cover_url = ""
    if entity.get("coverArt", {}).get("sources"):
        cover_url = entity["coverArt"]["sources"][0].get("url", "")

    track_list = entity.get("trackList", [])
    tracks = []
    for i, item in enumerate(track_list):
        uri = item.get("uri", "")
        if not uri.startswith("spotify:track:"):
            continue
        tid = uri.split(":")[-1]

        artists_str = item.get("subtitle", "")
        artists = [a.strip() for a in artists_str.split(",") if a.strip()]

        track_cover = cover_url
        if item.get("coverArt", {}).get("sources"):
            item_cover = item["coverArt"]["sources"][0].get("url", "")
            if item_cover:
                track_cover = item_cover

        tracks.append({
            "name": item.get("title", ""),
            "artists": artists or [album_artist],
            "album_name": album_name,
            "album_artist": album_artist,
            "duration": _embed_duration_seconds(item.get("duration", 0)),
            "song_id": tid,
            "cover_url": track_cover,
            "url": f"https://open.spotify.com/track/{tid}",
            "disc_number": item.get("disc_number", 1),
            "track_number": i + 1,
            "isrc": "",
        })

    return tracks


def fetch_playlist_metadata(sp, playlist_id):
    """Fetch metadata for all tracks in a playlist.

    Uses the Spotify embed page to get the track list since the Web API
    playlist_items endpoint returns 403 with client credentials flow.
    The embed data provides all fields needed for the pipeline.

    Falls back to individual sp.track() calls for enrichment when possible,
    but works fully from embed data alone if the API is restricted.
    If ``sp`` is None, skips API enrichment entirely.
    """
    import requests

    # Get track list from embed page (no auth required for public playlists)
    embed_url = f"https://open.spotify.com/embed/playlist/{playlist_id}"
    resp = requests.get(embed_url, headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
    resp.raise_for_status()

    match = re.search(
        r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', resp.text
    )
    if not match:
        raise ValueError("Could not parse playlist embed page")

    embed_data = json.loads(match.group(1))
    entity = embed_data["props"]["pageProps"]["state"]["data"]["entity"]
    track_list = entity.get("trackList", [])
    playlist_cover = ""
    if entity.get("coverArt", {}).get("sources"):
        playlist_cover = entity["coverArt"]["sources"][0].get("url", "")

    playlist_info = {
        "name": entity.get("title", ""),
        "cover": playlist_cover,
        "spotify_id": playlist_id,
    }

    if not track_list:
        return {"playlist": playlist_info, "tracks": []}

    # Collect track IDs from embed data
    track_ids = []
    embed_tracks = []
    for i, item in enumerate(track_list):
        uri = item.get("uri", "")
        if not uri.startswith("spotify:track:"):
            continue
        tid = uri.split(":")[-1]
        track_ids.append(tid)
        embed_tracks.append((i, item, tid))

    # Enrich tracks with album data from Spotify API (individual calls).
    # Skipped when sp is None (no-credentials mode) -- embed data used as-is.
    # The embed page doesn't include album names; sp.tracks() batch
    # endpoint returns 403 with client credentials, so use sp.track()
    album_map = {}  # track_id -> {"album_name": ..., "album_artist": ..., "isrc": ...}
    if sp is not None:
        import time
        for tid in track_ids:
            try:
                t = sp.track(tid)
                if t and t.get("album"):
                    album_images = t["album"].get("images", [])
                    album_map[tid] = {
                        "album_name": t["album"]["name"],
                        "album_artist": (
                            t["album"]["artists"][0]["name"]
                            if t["album"].get("artists") else ""
                        ),
                        "isrc": t.get("external_ids", {}).get("isrc", ""),
                        "cover_url": album_images[0]["url"] if album_images else "",
                    }
                time.sleep(0.05)  # Rate limit courtesy
            except Exception as e:
                emit_error({"warning": "enrichment_failed", "track_id": tid, "error": str(e)})

    tracks = []
    for i, item, tid in embed_tracks:
        artists_str = item.get("subtitle", "")

        # Extract per-track cover art; never default to playlist cover
        track_cover = ""
        if item.get("coverArt", {}).get("sources"):
            embed_cover = item["coverArt"]["sources"][0].get("url", "")
            # Only use embed cover if it differs from the playlist mosaic
            if embed_cover and embed_cover != playlist_cover:
                track_cover = embed_cover

        # Use enriched data from API if available, else fall back to embed data
        enriched = album_map.get(tid, {})

        tracks.append({
            "name": item.get("title", ""),
            "artists": [a.strip() for a in artists_str.split(",") if a.strip()],
            "album_name": enriched.get("album_name", ""),
            "album_artist": enriched.get("album_artist", "")
                or (artists_str.split(",")[0].strip() if artists_str else ""),
            "duration": item.get("duration", 0) / 1000,
            "song_id": tid,
            "cover_url": enriched.get("cover_url") or track_cover or "",
            "url": f"https://open.spotify.com/track/{tid}",
            "track_number": i + 1,
            "disc_number": 1,
            "isrc": enriched.get("isrc", ""),
        })

    return {"playlist": playlist_info, "tracks": tracks}


def cmd_metadata(args):
    """Fetch metadata for a Spotify URL and output as JSON."""
    sp = get_spotify_client()
    item_type, item_id = extract_spotify_info(args.url)

    if not item_type:
        emit_error({"error": "Invalid Spotify URL"})
        sys.exit(1)

    if item_type == "track":
        tracks = [fetch_track_metadata(sp, item_id)]
        emit(tracks)
    elif item_type == "album":
        tracks = fetch_album_metadata(sp, item_id)
        emit(tracks)
    elif item_type == "playlist":
        result = fetch_playlist_metadata(sp, item_id)
        emit(result)  # Emits {"playlist": {...}, "tracks": [...]}
    else:
        emit_error({"error": f"Unsupported type: {item_type}"})
        sys.exit(1)


def cmd_metadata_no_creds(args):
    """Fetch metadata for a Spotify URL using embed page scraping (no API credentials).

    Uses the same Spotify embed page approach as fetch_playlist_metadata but
    extended to tracks and albums. No SPOTIPY_CLIENT_ID / SPOTIPY_CLIENT_SECRET
    required. Album names and ISRCs are omitted for playlist tracks (not in embed).
    """
    item_type, item_id = extract_spotify_info(args.url)

    if not item_type:
        emit_error({"error": "Invalid Spotify URL"})
        sys.exit(1)

    if item_type == "track":
        track = fetch_track_metadata_no_creds(item_id)
        emit([track])
    elif item_type == "album":
        tracks = fetch_album_metadata_no_creds(item_id)
        emit(tracks)
    elif item_type == "playlist":
        # Pass sp=None to skip API enrichment; embed data is sufficient
        result = fetch_playlist_metadata(None, item_id)
        emit(result)
    else:
        emit_error({"error": f"Unsupported type: {item_type}"})
        sys.exit(1)


def search_youtube(query, duration_hint=None):
    """Search YouTube for best audio match using yt-dlp."""
    import yt_dlp

    search_query = f"ytsearch5:{query}"
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=False)
    except Exception as e:
        emit_error({"error": f"YouTube search failed: {e}"})
        return None

    if not info or "entries" not in info:
        return None

    entries = [e for e in info["entries"] if e]

    if not entries:
        return None

    # If we have a duration hint, prefer results close to that duration
    if duration_hint and len(entries) > 1:
        for entry in entries:
            entry_dur = entry.get("duration") or 0
            if entry_dur and abs(entry_dur - duration_hint) < 10:
                return entry.get("url") or entry.get("webpage_url")

    # Return first result
    best = entries[0]
    return best.get("url") or best.get("webpage_url")


def _download_from_youtube(query, duration_hint, args, output_template_default):
    """Shared download logic: search YouTube then download via yt-dlp.

    Returns (output_path, file_size) on success, calls sys.exit(1) on failure.
    """
    import yt_dlp

    emit_error({"status": "searching", "query": query})

    yt_url = search_youtube(query, duration_hint=duration_hint)

    if not yt_url:
        emit_error({"error": f"No YouTube results for: {query}"})
        sys.exit(1)

    emit_error({"status": "downloading", "youtube_url": yt_url})

    output_dir = os.path.abspath(args.output_dir) if args.output_dir else tempfile.mkdtemp(prefix="sfa_dl_")
    output_template = args.output_template or output_template_default
    audio_format = args.format or "mp3"
    bitrate = args.bitrate or "320k"

    bitrate_num = bitrate.rstrip("kK")

    output_path = os.path.join(output_dir, f"{output_template}.{audio_format}")

    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": os.path.join(output_dir, f"{output_template}.%(ext)s"),
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": audio_format,
                "preferredquality": bitrate_num,
            }
        ],
        "quiet": True,
        "no_warnings": True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([yt_url])
    except Exception as e:
        emit_error({"error": f"yt-dlp download failed: {e}"})
        sys.exit(1)

    if os.path.exists(output_path):
        file_size = os.path.getsize(output_path)
    else:
        pattern = os.path.join(output_dir, f"{output_template}.*")
        import glob
        matches = glob.glob(pattern)
        if matches:
            output_path = matches[0]
            file_size = os.path.getsize(output_path)
        else:
            emit_error({"error": "Downloaded file not found"})
            sys.exit(1)

    return output_path, file_size


def cmd_download(args):
    """Download audio from a Spotify URL via YouTube.

    Fallback chain:
      1. Spotify embed page scraping (no API credentials required)
      2. Spotify Web API via spotipy (requires SPOTIPY_CLIENT_ID/SECRET)
      3. YouTube search + yt-dlp download
    """
    item_type, item_id = extract_spotify_info(args.url)

    if not item_type:
        emit_error({"error": "Invalid Spotify URL"})
        sys.exit(1)

    if item_type != "track":
        emit_error({"error": "Download only supports single tracks"})
        sys.exit(1)

    # Step 1: embed page (no credentials).
    meta = None
    try:
        meta = fetch_track_metadata_no_creds(item_id)
    except Exception as embed_err:
        emit_error({"warning": "embed_page_failed", "error": str(embed_err)})
    # Step 2: Fall back to Spotify API if embed failed.
    if meta is None:
        try:
            sp = get_spotify_client()
            meta = fetch_track_metadata(sp, item_id)
        except ValueError as cred_err:
            emit_error({"error": f"Embed failed, no Spotify credentials: {cred_err}"})
            sys.exit(1)
        except Exception as api_err:
            emit_error({"error": f"Both embed and Spotify API failed: {api_err}"})
            sys.exit(1)
    artist_str = ", ".join(meta["artists"])
    search_query = f"{meta['name']} {artist_str}"

    output_path, file_size = _download_from_youtube(
        search_query, meta.get("duration"), args, meta["song_id"]
    )

    emit({"path": output_path, "size": file_size, "metadata": meta})


def cmd_download_direct(args):
    """Download audio by searching YouTube directly with provided metadata.

    Skips all Spotify API calls -- uses title/artist/duration from CLI args.
    """
    search_query = f"{args.title} {args.artist}"
    duration_hint = float(args.duration) if args.duration else None

    output_path, file_size = _download_from_youtube(
        search_query, duration_hint, args, args.output_template or "direct"
    )

    emit({"path": output_path, "size": file_size})


def main():
    parser = argparse.ArgumentParser(description="Spotify metadata & download helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # metadata command (requires SPOTIPY_CLIENT_ID + SPOTIPY_CLIENT_SECRET)
    meta_parser = subparsers.add_parser("metadata", help="Fetch Spotify metadata")
    meta_parser.add_argument("url", help="Spotify URL")

    # metadata-no-creds command (embed page scraping, no API credentials required)
    mnc_parser = subparsers.add_parser(
        "metadata-no-creds",
        help="Fetch Spotify metadata via embed page (no API credentials)",
    )
    mnc_parser.add_argument("url", help="Spotify URL")

    # download command
    dl_parser = subparsers.add_parser("download", help="Download audio from Spotify URL")
    dl_parser.add_argument("url", help="Spotify URL")
    dl_parser.add_argument("--output-dir", help="Output directory")
    dl_parser.add_argument("--output-template", help="Output filename template (without extension)")
    dl_parser.add_argument("--format", default="mp3", help="Audio format (default: mp3)")
    dl_parser.add_argument("--bitrate", default="320k", help="Audio bitrate (default: 320k)")

    # download-direct command (no Spotify API -- uses provided metadata)
    dd_parser = subparsers.add_parser(
        "download-direct",
        help="Download audio using metadata (no Spotify API)",
    )
    dd_parser.add_argument("--title", required=True, help="Track title")
    dd_parser.add_argument("--artist", required=True, help="Artist name")
    dd_parser.add_argument("--duration", help="Duration in seconds (used as search hint)")
    dd_parser.add_argument("--output-dir", help="Output directory")
    dd_parser.add_argument("--output-template", help="Output filename template (without extension)")
    dd_parser.add_argument("--format", default="mp3", help="Audio format (default: mp3)")
    dd_parser.add_argument("--bitrate", default="320k", help="Audio bitrate (default: 320k)")

    args = parser.parse_args()

    if args.command == "metadata":
        cmd_metadata(args)
    elif args.command == "metadata-no-creds":
        cmd_metadata_no_creds(args)
    elif args.command == "download":
        cmd_download(args)
    elif args.command == "download-direct":
        cmd_download_direct(args)


if __name__ == "__main__":
    main()
