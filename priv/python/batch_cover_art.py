#!/usr/bin/env python3
"""
Batch fetch album art for Spotify tracks using oEmbed API.

Reads track IDs from a file (first argument), fetches album art URLs
from Spotify's public oEmbed endpoint, outputs JSON mapping {track_id: cover_url}.

No API credentials needed.
"""

import sys
import json
import concurrent.futures
from urllib.request import urlopen, Request


def fetch_cover_art(track_id):
    """Fetch album art URL from Spotify oEmbed API."""
    url = f"https://open.spotify.com/oembed?url=spotify:track:{track_id}"
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            thumbnail = data.get("thumbnail_url")
            if thumbnail:
                return track_id, thumbnail
        return track_id, None
    except Exception as e:
        print(json.dumps({"warning": f"Failed for {track_id}: {str(e)}"}), file=sys.stderr, flush=True)
        return track_id, None


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: batch_cover_art.py <ids_file>"}), flush=True)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        track_ids = [line.strip() for line in f if line.strip()]

    if not track_ids:
        print(json.dumps({}), flush=True)
        return

    print(json.dumps({"status": f"Fetching cover art for {len(track_ids)} tracks..."}), file=sys.stderr, flush=True)

    updates = {}
    # Use thread pool for concurrent fetches (5 at a time to be polite)
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(fetch_cover_art, tid): tid for tid in track_ids}
        for i, future in enumerate(concurrent.futures.as_completed(futures)):
            track_id, cover_url = future.result()
            if cover_url:
                updates[track_id] = cover_url
            if (i + 1) % 20 == 0:
                print(json.dumps({"status": f"Processed {i+1}/{len(track_ids)}"}), file=sys.stderr, flush=True)

    print(json.dumps({"status": f"Got cover art for {len(updates)}/{len(track_ids)} tracks"}), file=sys.stderr, flush=True)
    print(json.dumps(updates), flush=True)


if __name__ == "__main__":
    main()
