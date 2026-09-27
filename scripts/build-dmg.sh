#!/usr/bin/env bash
# Packages build/BTSKey.app into a drag-to-Applications DMG for website distribution.
# With SIGN_IDENTITY the DMG is signed; with NOTARY_PROFILE (a `xcrun notarytool store-credentials`
# profile) it is notarized and stapled so Gatekeeper opens it without warnings.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh release
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
APP="build/BTSKey.app"
STAGING="build/dmg"
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
