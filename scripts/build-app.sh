#!/usr/bin/env bash
# Builds BTSKey.app from the SwiftPM executable and signs it.
# Ad-hoc signed unless SIGN_IDENTITY is set ("Developer ID Application: …"), in which case the
# hardened runtime is enabled so the result can be notarized by build-dmg.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="BTSKey"
BUNDLE_ID="${BUNDLE_ID:-kr.newid.btskey}"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
OUT="build/${APP_NAME}.app"
ICON="build/AppIcon.icns"

swift build -c "$CONFIG" --product "$APP_NAME"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

if [ ! -f "$ICON" ] || [ scripts/make-icon.swift -nt "$ICON" ]; then
  swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"
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

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$OUT"
else
  codesign --force --sign - --timestamp=none "$OUT"
fi
echo "built $OUT (version $VERSION build $BUILD_NUMBER)"
