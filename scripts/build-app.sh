#!/usr/bin/env bash
# Builds BTSKey.app from the SwiftPM executable and signs it.
# With SIGN_IDENTITY ("Developer ID Application: …") the hardened runtime is enabled so the result
# can be notarized by build-dmg.sh; see the signing section below for the other cases.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="BTSKey"
BUNDLE_ID="${BUNDLE_ID:-kr.newid.btskey}"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT="build/${APP_NAME}.app"
ICON="build/AppIcon.icns"

# UNIVERSAL=1 builds for Apple silicon and Intel (what build-dmg.sh ships); the default builds
# for this Mac only, which is faster.
ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS="--arch arm64 --arch x86_64"; fi
# shellcheck disable=SC2086
swift build -c "$CONFIG" --product "$APP_NAME" $ARCH_FLAGS
# shellcheck disable=SC2086
BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/${APP_NAME}"

if [ ! -f "$ICON" ] || [ scripts/make-icon.swift -nt "$ICON" ]; then
  swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"
# The linker leaves the paths of the object files in the executable, and with them the name of
# the account that built it. Nothing in a distributed app should say where it was built.
strip -S -x "$OUT/Contents/MacOS/$APP_NAME"
cp "$ICON" "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BTS Key</string>
  <key>CFBundleDisplayName</key><string>BTS Key</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 newid</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>iMac에 블루투스 키보드·마우스로 연결하기 위해 필요합니다.</string>
</dict>
</plist>
PLIST

# Signing, in order of preference:
#   SIGN_IDENTITY  a Developer ID, for distribution (hardened runtime, notarizable)
#   DEV_IDENTITY   a self-signed certificate in the login keychain; the signature stays the same
#                  across rebuilds, so Accessibility / Input Monitoring grants survive them
#                  (set DEV_IDENTITY to an empty string to skip it, as build-dmg.sh does)
#   ad-hoc         every rebuild is a new app to macOS and both grants must be given again
DEV_IDENTITY="${DEV_IDENTITY-BTSKey Dev}"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$OUT"
  SIGNED_WITH="$SIGN_IDENTITY"
elif [ -n "$DEV_IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$DEV_IDENTITY\""; then
  codesign --force --sign "$DEV_IDENTITY" --timestamp=none "$OUT"
  SIGNED_WITH="$DEV_IDENTITY (self-signed, this Mac only)"
else
  codesign --force --sign - --timestamp=none "$OUT"
  SIGNED_WITH="ad-hoc"
fi
echo "built $OUT (version $VERSION build $BUILD_NUMBER, signed: $SIGNED_WITH)"
