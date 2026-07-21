#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Sound Forge Alchemy"
BUNDLE_ID="com.soundforgealchemy.mac"
MARKETING_VERSION="5.0.0"
BUILD_NUMBER="1"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-14.0}"
ARCH="${LOCAL_ARCH:-arm64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/LocalPackage}"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
SOURCE_DIR="$ROOT_DIR/SoundForgeAlchemy"
ENTITLEMENTS="$SOURCE_DIR/SoundForgeAlchemy.entitlements"

printf '==> Packaging %s for local macOS verification\n' "$APP_NAME"

"$ROOT_DIR/ci/verify_package_readiness.sh" >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

xcrun swiftc \
  -sdk "$SDK_PATH" \
  -target "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
  -O \
  -parse-as-library \
  -module-name SoundForgeAlchemy \
  "$SOURCE_DIR"/*.swift \
  -o "$EXECUTABLE"

cp "$SOURCE_DIR/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $DEPLOYMENT_TARGET" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Delete :NSMainStoryboardFile" "$INFO_PLIST" 2>/dev/null || true

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

ASSETS_DIR="$SOURCE_DIR/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
  if find "$ASSETS_DIR" -type f ! -name Contents.json | grep -q . ||
    grep -R -Eq '"filename"[[:space:]]*:|"color"[[:space:]]*:' "$ASSETS_DIR"; then
    xcrun actool "$ASSETS_DIR" \
    --compile "$RESOURCES_DIR" \
    --output-format human-readable-text \
    --warnings \
    --notices \
    --app-icon AppIcon \
    --accent-color AccentColor \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target "$DEPLOYMENT_TARGET" \
    --platform macosx >/dev/null
  else
    printf '==> Skipping asset catalog compile; no concrete asset payloads found\n'
  fi
fi

codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf '==> Local app package verified: %s\n' "$APP_DIR"
