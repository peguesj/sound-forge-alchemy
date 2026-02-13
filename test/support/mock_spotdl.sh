#!/bin/bash
# Mock spotdl for testing.
# Behavior depends on the subcommand and arguments.

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  save)
    # Check if URL contains "invalid" to simulate failure
    for arg in "$@"; do
      if [[ "$arg" == *"invalid"* ]] || [[ "$arg" == *"not-a-spotify"* ]]; then
        echo "Error: Invalid URL" >&2
        exit 1
      fi
    done
    # Output mock track metadata as JSON array
    cat <<'MOCK_JSON'
[{"name": "Test Song", "artists": ["Test Artist"], "artist": "Test Artist", "album_name": "Test Album", "album_artist": "Test Artist", "duration": 180, "song_id": "abc123", "cover_url": "https://example.com/art.jpg", "url": "https://open.spotify.com/track/abc123", "isrc": "USRC12345678"}]
MOCK_JSON
    exit 0
    ;;
  download)
    # Check for failure URLs
    for arg in "$@"; do
      if [[ "$arg" == *"fail"* ]]; then
        echo "Error: Download failed" >&2
        exit 1
      fi
    done
    # Simulate download by creating a fake MP3 file
    # Find the --output argument
    OUTPUT_DIR=""
    OUTPUT_FILE=""
    for i in $(seq 1 $#); do
      arg="${!i}"
      if [[ "$arg" == "--output" ]]; then
        next=$((i + 1))
        OUTPUT_FILE="${!next}"
      fi
    done
    if [[ -n "$OUTPUT_FILE" ]]; then
      # Create a fake MP3 file with ID3 header
      mkdir -p "$(dirname "$OUTPUT_FILE")"
      printf 'ID3' > "$OUTPUT_FILE"
      dd if=/dev/urandom bs=2048 count=1 >> "$OUTPUT_FILE" 2>/dev/null
    fi
    exit 0
    ;;
  --version)
    echo "spotdl 4.2.0"
    exit 0
    ;;
  *)
    echo "Unknown command: $SUBCOMMAND" >&2
    exit 1
    ;;
esac
