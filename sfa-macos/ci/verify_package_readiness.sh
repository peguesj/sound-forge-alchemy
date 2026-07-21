#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/SoundForgeAlchemy.xcodeproj/project.pbxproj"
INFO_PLIST="$ROOT_DIR/SoundForgeAlchemy/Info.plist"
ENTITLEMENTS="$ROOT_DIR/SoundForgeAlchemy/SoundForgeAlchemy.entitlements"
BASE_XCCONFIG="$ROOT_DIR/xcconfig/Base.xcconfig"
RELEASE_XCCONFIG="$ROOT_DIR/xcconfig/Release.xcconfig"
EXPORT_OPTIONS="$ROOT_DIR/ExportOptions.plist"
LOCAL_PACKAGER="$ROOT_DIR/ci/package_local_app.sh"
APP_STATE="$ROOT_DIR/SoundForgeAlchemy/AppState.swift"
APP_DELEGATE="$ROOT_DIR/SoundForgeAlchemy/AppDelegate.swift"
SHOWCASE="$ROOT_DIR/SoundForgeAlchemy/ShowcaseBridge.swift"

fail() {
  printf 'package-readiness: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing required file: $1"
}

assert_plist_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || true)"
  [ "$actual" = "$expected" ] || fail "$file :$key expected '$expected' but found '$actual'"
}

assert_grep() {
  local pattern="$1"
  local file="$2"

  grep -Eq -- "$pattern" "$file" || fail "$file does not contain expected pattern: $pattern"
}

assert_absent() {
  local pattern="$1"
  shift

  if grep -REq "$pattern" "$@"; then
    fail "found forbidden runtime dependency pattern: $pattern"
  fi
}

assert_file "$PROJECT_FILE"
assert_file "$INFO_PLIST"
assert_file "$ENTITLEMENTS"
assert_file "$BASE_XCCONFIG"
assert_file "$RELEASE_XCCONFIG"
assert_file "$EXPORT_OPTIONS"
assert_file "$LOCAL_PACKAGER"
assert_file "$APP_STATE"
assert_file "$APP_DELEGATE"
assert_file "$SHOWCASE"

assert_plist_value "$INFO_PLIST" "CFBundleIdentifier" "\$(PRODUCT_BUNDLE_IDENTIFIER)"
assert_plist_value "$INFO_PLIST" "CFBundleDevelopmentRegion" "\$(DEVELOPMENT_LANGUAGE)"
assert_plist_value "$INFO_PLIST" "LSMinimumSystemVersion" "\$(MACOSX_DEPLOYMENT_TARGET)"
assert_plist_value "$INFO_PLIST" "NSDocumentsFolderUsageDescription" "Sound Forge Alchemy accesses your Documents folder to import and export audio files."
assert_plist_value "$INFO_PLIST" "NSMusicFolderUsageDescription" "Sound Forge Alchemy accesses your Music folder to import audio tracks."
assert_plist_value "$INFO_PLIST" "NSDownloadsFolderUsageDescription" "Sound Forge Alchemy saves downloaded tracks to your Downloads folder."
assert_plist_value "$INFO_PLIST" "NSMicrophoneUsageDescription" "Sound Forge Alchemy uses the microphone for live audio input and recording."

assert_plist_value "$ENTITLEMENTS" "com.apple.security.app-sandbox" "false"
assert_plist_value "$ENTITLEMENTS" "com.apple.security.files.user-selected.read-write" "true"
assert_plist_value "$ENTITLEMENTS" "com.apple.security.files.downloads.read-write" "true"
assert_plist_value "$ENTITLEMENTS" "com.apple.security.device.audio-input" "true"
assert_plist_value "$ENTITLEMENTS" "com.apple.security.network.client" "true"
assert_plist_value "$ENTITLEMENTS" "com.apple.security.network.server" "true"

assert_plist_value "$EXPORT_OPTIONS" "method" "developer-id"
assert_plist_value "$EXPORT_OPTIONS" "signingStyle" "automatic"
assert_plist_value "$EXPORT_OPTIONS" "stripSwiftSymbols" "true"

assert_grep '^PRODUCT_BUNDLE_IDENTIFIER = com\.soundforgealchemy\.mac$' "$BASE_XCCONFIG"
assert_grep '^ENABLE_HARDENED_RUNTIME = YES$' "$BASE_XCCONFIG"
assert_grep '^SFA_RUNTIME_MODE = bundled$' "$BASE_XCCONFIG"
assert_grep '^CODE_SIGN_STYLE = Manual$' "$RELEASE_XCCONFIG"
assert_grep '^CODE_SIGN_IDENTITY = Developer ID Application$' "$RELEASE_XCCONFIG"
assert_grep 'xcrun swiftc' "$LOCAL_PACKAGER"
assert_grep 'SIGN_IDENTITY' "$LOCAL_PACKAGER"
assert_grep '--options runtime' "$LOCAL_PACKAGER"

assert_grep 'baseConfigurationReference = .*Release\.xcconfig' "$PROJECT_FILE"
assert_grep 'CODE_SIGN_ENTITLEMENTS = SoundForgeAlchemy/SoundForgeAlchemy\.entitlements;' "$PROJECT_FILE"
assert_grep 'CODE_SIGN_STYLE = Manual;' "$PROJECT_FILE"
assert_grep 'DEVELOPMENT_TEAM = "\$\(TEAM_ID\)";' "$PROJECT_FILE"
assert_grep 'CODE_SIGN_IDENTITY = "Developer ID Application";' "$PROJECT_FILE"
assert_grep 'ENABLE_HARDENED_RUNTIME = YES;' "$PROJECT_FILE"
assert_grep 'PRODUCT_BUNDLE_IDENTIFIER = com\.soundforgealchemy\.mac;' "$PROJECT_FILE"

assert_absent 'SFA_AUTOSTART_BACKEND|mix phx|phx\.server|BackendClient' \
  "$APP_STATE" \
  "$APP_DELEGATE" \
  "$SHOWCASE"

if grep -Eq 'showcase\.start\(root: repoRoot\)' "$APP_STATE"; then
  fail "Showcase must be started explicitly from the development cockpit, not during app startup"
fi

printf 'package-readiness: ok\n'
