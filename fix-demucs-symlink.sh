#!/bin/bash
# Fix /tmp/demucs symlink to point to correct external volume
# This script requires sudo password
# Usage: ./fix-demucs-symlink.sh

set -e

echo "Fixing /tmp/demucs symlink..."
echo "Current symlink status:"
ls -la /tmp/demucs 2>/dev/null || echo "  /tmp/demucs does not exist or is inaccessible"

echo ""
echo "Verifying target directory exists and is writable..."
if [ -w '/Volumes/YJ_MORE 1/924SFA/tmp/demucs' ]; then
    echo "✓ Target directory is writable: /Volumes/YJ_MORE 1/924SFA/tmp/demucs"
else
    echo "✗ ERROR: Target directory is not writable!"
    exit 1
fi

echo ""
echo "Removing old broken symlink..."
sudo rm -f /tmp/demucs

echo "Creating new symlink to correct target..."
sudo ln -s '/Volumes/YJ_MORE 1/924SFA/tmp/demucs' /tmp/demucs

echo ""
echo "Verifying new symlink..."
ls -la /tmp/demucs

echo ""
echo "✓ Symlink fixed successfully!"
echo "You can now run 'mix ecto.migrate' and start the dev server."
