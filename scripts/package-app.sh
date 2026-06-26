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
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SPARKLE_KEY_FILE="${AIRCOPY_SPARKLE_KEY_FILE:-$HOME/.config/aircopy/sparkle_ed_private_key}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
MODULE_CACHE="/tmp/aircopy-clang-cache"
ICONSET_DIR="$DIST_DIR/AirCopy.iconset"
ICON_FILE="$RESOURCES_DIR/AirCopy.icns"
WEBSITE_ASSETS_DIR="$ROOT_DIR/website/assets"
WEBSITE_DOWNLOADS_DIR="$ROOT_DIR/website/downloads"
SIGN_IDENTITY="${AIRCOPY_CODE_SIGN_IDENTITY:-}"
KEEP_STAGING_APP="${AIRCOPY_KEEP_STAGING_APP:-0}"

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

SIGN_IS_DEVELOPER_ID=0
resolve_sign_identity() {
  if [[ -n "$SIGN_IDENTITY" ]]; then
    [[ "$SIGN_IDENTITY" == *"Developer ID"* ]] && SIGN_IS_DEVELOPER_ID=1
    return
  fi

  if ! command -v security >/dev/null 2>&1; then
    return
  fi

  # Prefer a Developer ID Application cert (required for notarization /
  # distribution outside the App Store); fall back to a development cert.
  SIGN_IDENTITY="$(
    security find-identity -p codesigning -v 2>/dev/null \
      | awk -F '"' '/Developer ID Application/ { print $2; exit }'
  )"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    SIGN_IS_DEVELOPER_ID=1
    return
  fi

  SIGN_IDENTITY="$(
    security find-identity -p codesigning -v 2>/dev/null \
      | awk -F '"' '/Apple Development/ { print $2; exit }'
  )"
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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
build_icon
if [[ -f "$DIST_DIR/AirCopy.icns" ]]; then
  cp "$DIST_DIR/AirCopy.icns" "$ICON_FILE"
fi

# Embed Sparkle.framework (the auto-updater) and point the executable's rpath at
# Contents/Frameworks so it loads at runtime.
SPARKLE_FW="$(find "$BUILD_DIR/artifacts" -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" -type d 2>/dev/null | head -1)"
if [[ -n "$SPARKLE_FW" ]]; then
  echo "Embedding Sparkle.framework..."
  ditto "$SPARKLE_FW" "$FRAMEWORKS_DIR/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
else
  echo "WARNING: Sparkle.framework not found under .build/artifacts; auto-update will not work." >&2
fi

if command -v codesign >/dev/null 2>&1; then
  resolve_sign_identity

  if [[ "$SIGN_IS_DEVELOPER_ID" == "1" ]]; then
    echo "Signing with Developer ID + hardened runtime: $SIGN_IDENTITY"
    # Real (Apple) timestamp + hardened runtime are required for notarization.
    SIGN_FLAGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")

    # Sparkle ships ad-hoc-signed; re-sign its nested code inside-out so the
    # whole bundle is Developer-ID-signed and notarizable.
    SPARKLE_BUNDLE="$FRAMEWORKS_DIR/Sparkle.framework"
    if [[ -d "$SPARKLE_BUNDLE" ]]; then
      echo "Signing Sparkle.framework components..."
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE/Versions/B/XPCServices/Downloader.xpc"
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE/Versions/B/XPCServices/Installer.xpc"
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE/Versions/B/Updater.app/Contents/MacOS/Updater"
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE/Versions/B/Updater.app"
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE/Versions/B/Autoupdate"
      codesign "${SIGN_FLAGS[@]}" "$SPARKLE_BUNDLE"
    fi

    codesign "${SIGN_FLAGS[@]}" "$MACOS_DIR/$APP_NAME"
    codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
    echo "Verifying bundle signature…"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | tail -2
  elif [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Applying development signature (not notarizable): $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
  else
    echo "Falling back to ad-hoc signature..."
    codesign --force --deep --sign - "$APP_DIR"
  fi
fi

echo "Installing canonical app bundle..."
rm -rf "$INSTALLED_APP_DIR"
ditto "$APP_DIR" "$INSTALLED_APP_DIR"

ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
rm -f "$ZIP_PATH"
echo "Creating zip archive..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# Notarize with Apple so Gatekeeper trusts the download (no "untrusted app"
# warning on first launch). Requires a Developer ID signature and a one-time
# stored credential profile created by the user:
#   xcrun notarytool store-credentials "AC_NOTARY" \
#       --apple-id <you@example.com> --team-id 9LZ5TSWPZ9 --password <app-specific-password>
# (app-specific password from appleid.apple.com — NOT your Apple ID password).
# Skipped gracefully when the cert or profile isn't present.
NOTARY_PROFILE="${AIRCOPY_NOTARY_PROFILE:-AC_NOTARY}"
if [[ "$SIGN_IS_DEVELOPER_ID" == "1" ]] && command -v xcrun >/dev/null 2>&1 \
   && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)…"
  if xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait; then
    echo "Stapling notarization ticket to the app…"
    xcrun stapler staple "$APP_DIR"
    echo "Re-zipping the stapled app…"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
    rm -rf "$INSTALLED_APP_DIR"
    ditto "$APP_DIR" "$INSTALLED_APP_DIR"
    echo "Notarized and stapled."
  else
    echo "WARNING: notarization failed; shipping the un-notarized build." >&2
  fi
else
  echo "Skipping notarization (need a Developer ID cert + notarytool profile '$NOTARY_PROFILE')."
fi

echo "Syncing website assets..."
mkdir -p "$WEBSITE_ASSETS_DIR" "$WEBSITE_DOWNLOADS_DIR"
cp "$ROOT_DIR/Resources/1024.png" "$WEBSITE_ASSETS_DIR/aircopy-logo.png"
cp "$ZIP_PATH" "$WEBSITE_DOWNLOADS_DIR/$APP_NAME-macOS.zip"

# Generate the Sparkle appcast (EdDSA-signed) so the in-app updater can find and
# verify this release. SUFeedURL in Info.plist points at this file.
SPARKLE_SIGN="$(find "$BUILD_DIR/artifacts" -path "*/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)"
if [[ -n "$SPARKLE_SIGN" && -f "$SPARKLE_KEY_FILE" ]]; then
  echo "Generating signed appcast.xml..."
  SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST")"
  BUILD_VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO_PLIST")"
  MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$INFO_PLIST")"
  SIG_ATTRS="$("$SPARKLE_SIGN" --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP_PATH")"
  PUBDATE="$(date '+%a, %d %b %Y %H:%M:%S %z')"
  cat > "$ROOT_DIR/website/appcast.xml" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>AirCopy</title>
    <link>https://aircopyapp.com/appcast.xml</link>
    <item>
      <title>Version ${SHORT_VER}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${BUILD_VER}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VER}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <enclosure url="https://aircopyapp.com/downloads/${APP_NAME}-macOS.zip" ${SIG_ATTRS} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
  echo "  website/appcast.xml (v$SHORT_VER, build $BUILD_VER)"
else
  echo "Skipping appcast (need Sparkle sign_update + key file at $SPARKLE_KEY_FILE)." >&2
fi

if [[ "$KEEP_STAGING_APP" != "1" ]]; then
  echo "Removing staging app bundle from dist..."
  rm -rf "$APP_DIR"
fi

echo
echo "Created:"
echo "  $ZIP_PATH"
echo "  $WEBSITE_DOWNLOADS_DIR/$APP_NAME-macOS.zip"
echo "Installed:"
echo "  $INSTALLED_APP_DIR"
