#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="AirCopy"
APP_DIR="$DIST_DIR/$APP_NAME.app"
INSTALL_BASE_DIR="${AIRCOPY_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_DIR="$INSTALL_BASE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
MODULE_CACHE="/tmp/aircopy-clang-cache"
ICONSET_DIR="$DIST_DIR/AirCopy.iconset"
ICON_FILE="$RESOURCES_DIR/AirCopy.icns"
WEBSITE_ASSETS_DIR="$ROOT_DIR/website/assets"
WEBSITE_DOWNLOADS_DIR="$ROOT_DIR/website/downloads"

mkdir -p "$MODULE_CACHE"
mkdir -p "$DIST_DIR"
mkdir -p "$INSTALL_BASE_DIR"

build_icon() {
  if ! command -v iconutil >/dev/null 2>&1; then
    echo "iconutil not found; skipping app icon generation." >&2
    return
  fi

  if ! command -v sips >/dev/null 2>&1; then
    echo "sips not found; skipping app icon generation." >&2
    return
  fi

  echo "Building app icon..."
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  cp "$ROOT_DIR/Resources/16.png" "$ICONSET_DIR/icon_16x16.png"
  cp "$ROOT_DIR/Resources/32.png" "$ICONSET_DIR/icon_16x16@2x.png"
  cp "$ROOT_DIR/Resources/32.png" "$ICONSET_DIR/icon_32x32.png"
  cp "$ROOT_DIR/Resources/64.png" "$ICONSET_DIR/icon_32x32@2x.png"

  sips -z 128 128 "$ROOT_DIR/Resources/256.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  cp "$ROOT_DIR/Resources/256.png" "$ICONSET_DIR/icon_128x128@2x.png"
  cp "$ROOT_DIR/Resources/256.png" "$ICONSET_DIR/icon_256x256.png"
  cp "$ROOT_DIR/Resources/512.png" "$ICONSET_DIR/icon_256x256@2x.png"
  cp "$ROOT_DIR/Resources/512.png" "$ICONSET_DIR/icon_512x512.png"
  cp "$ROOT_DIR/Resources/1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$DIST_DIR/AirCopy.icns"
}

echo "Building release binary..."
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift build -c release

BINARY_PATH="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Expected binary not found at $BINARY_PATH" >&2
  exit 1
fi

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
build_icon
if [[ -f "$DIST_DIR/AirCopy.icns" ]]; then
  cp "$DIST_DIR/AirCopy.icns" "$ICON_FILE"
fi

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Installing canonical app bundle..."
rm -rf "$INSTALLED_APP_DIR"
ditto "$APP_DIR" "$INSTALLED_APP_DIR"

ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
rm -f "$ZIP_PATH"
echo "Creating zip archive..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Syncing website assets..."
mkdir -p "$WEBSITE_ASSETS_DIR" "$WEBSITE_DOWNLOADS_DIR"
cp "$ROOT_DIR/Resources/1024.png" "$WEBSITE_ASSETS_DIR/aircopy-logo.png"
cp "$ZIP_PATH" "$WEBSITE_DOWNLOADS_DIR/$APP_NAME-macOS.zip"

echo
echo "Created:"
echo "  $APP_DIR"
echo "Installed:"
echo "  $INSTALLED_APP_DIR"
echo "  $ZIP_PATH"
echo "  $WEBSITE_DOWNLOADS_DIR/$APP_NAME-macOS.zip"
