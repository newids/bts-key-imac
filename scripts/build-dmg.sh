#!/usr/bin/env bash
# Packages build/BTSKey.app into a drag-to-Applications DMG for website distribution.
# With SIGN_IDENTITY the DMG is signed; with NOTARY_PROFILE (a `xcrun notarytool store-credentials`
# profile) it is notarized and stapled so Gatekeeper opens it without warnings.
set -euo pipefail
cd "$(dirname "$0")/.."

# A disk image for other people is never signed with the development certificate of this Mac.
DEV_IDENTITY="" ./scripts/build-app.sh release
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"   # 0.0.0 marks a build without a VERSION file
APP="build/BTSKey.app"
STAGING="build/dmg"

# What goes into a release is checked, not assumed: the distribution signature (a Developer ID,
# or ad-hoc when there is none), Apple silicon only, and no trace of the Mac that built it.
EXECUTABLE="$APP/Contents/MacOS/BTSKey"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "$SIGNATURE" | grep -q "^Authority=$SIGN_IDENTITY" || { echo "error: the app is not signed with $SIGN_IDENTITY" >&2; exit 1; }
else
  echo "$SIGNATURE" | grep -q "^Signature=adhoc" || { echo "error: the app carries a signature that is not meant for distribution" >&2; exit 1; }
fi
[ "$(lipo -archs "$EXECUTABLE")" = "arm64" ] || { echo "error: the executable is not arm64 only" >&2; exit 1; }
if LC_ALL=C strings - "$EXECUTABLE" | LC_ALL=C grep -q "/Users/"; then
  echo "error: the executable contains build paths" >&2; exit 1
fi
DMG="build/BTSKey-${VERSION}.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/설치 안내.txt" <<'TXT'
BTS Key 설치

1. BTS Key 아이콘을 Applications 폴더로 끌어 놓습니다.
2. 응용 프로그램 폴더에서 BTS Key를 실행합니다.
3. "확인되지 않은 개발자" 경고가 뜨면: 아이콘을 control-클릭(오른쪽 클릭) → 열기 → 열기.
   또는 시스템 설정 → 개인정보 보호 및 보안 → 아래쪽 "그래도 열기".
4. 첫 실행 안내에 따라 Bluetooth, 손쉬운 사용, 입력 모니터링 권한을 허용합니다.

메뉴바의 키보드 아이콘에서 iMac을 선택해 연결하고, ⌥⌘K로 입력을 오갑니다.
TXT

hdiutil create -volname "BTS Key" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "packaged $DMG"
