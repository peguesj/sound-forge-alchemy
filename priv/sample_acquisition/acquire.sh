#!/usr/bin/env bash
# acquire.sh — Generate a sample manifest JSON from a directory
#
# Usage: ./acquire.sh /path/to/samples > manifest.json
#
# Scans the given directory for audio files and outputs a JSON manifest
# suitable for SoundForge.SampleLibrary.import_from_manifest/2.

set -euo pipefail

SOURCE_DIR="${1:-}"

if [[ -z "$SOURCE_DIR" ]]; then
  echo "Usage: $0 /path/to/samples > manifest.json" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Directory not found: $SOURCE_DIR" >&2
  exit 1
fi

AUDIO_EXTS="wav|mp3|aif|aiff|flac|ogg"

echo "["
first=true

find "$SOURCE_DIR" -maxdepth 2 -type f | sort | while read -r filepath; do
  ext="${filepath##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  if echo "$AUDIO_EXTS" | grep -qw "$ext_lower"; then
    filename=$(basename "$filepath")
    name="${filename%.*}"
    filesize=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null || echo 0)

    # Infer category from path
    category="misc"
    for cat in drums bass synths vocals sfx loops; do
      if echo "$filepath" | grep -qi "$cat"; then
        category="$cat"
        break
      fi
    done

    if [[ "$first" == "false" ]]; then
      echo ","
    fi
    first=false

    printf '  {"name": "%s", "file_path": "%s", "category": "%s", "file_size": %d}' \
      "$name" "$filepath" "$category" "$filesize"
  fi
done

echo ""
echo "]"
