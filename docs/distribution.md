# 배포 (웹사이트 다운로드용)

앱스토어 없이 웹사이트에서 내려받아 설치하는 패키지를 만든다.

## 만들기

```bash
echo 0.2.0 > VERSION            # 버전 올리기
./scripts/build-dmg.sh          # build/BTSKey-<버전>.dmg 와 .sha256
```

`build-dmg.sh`는 `build-app.sh`를 먼저 실행한다. `build-app.sh`는 SwiftPM 릴리스 빌드 → `scripts/make-icon.swift`로 아이콘 렌더링(`build/AppIcon.icns`) → `Info.plist`(버전, 빌드 번호 = 커밋 수, 카테고리, 아이콘, 저작권) → 서명 순서다. DMG에는 앱, `Applications` 심볼릭 링크, `설치 안내.txt`가 들어간다.

## 서명과 공증

| 상황 | 방법 | 사용자 경험 |
|---|---|---|
| 서명 인증서 없음(현재) | ad-hoc 서명 | 첫 실행 때 "확인되지 않은 개발자" 경고. control-클릭 → 열기로 통과. `설치 안내.txt`에 적혀 있다. 빌드마다 권한(손쉬운 사용·입력 모니터링·Bluetooth)을 다시 묻는다. |
| Apple Developer 계정 있음 | `SIGN_IDENTITY="Developer ID Application: 이름 (TEAMID)" NOTARY_PROFILE=btskey ./scripts/build-dmg.sh` | 경고 없이 열린다. 권한은 한 번만 묻는다. |

공증 프로필은 한 번만 만든다: `xcrun notarytool store-credentials btskey --apple-id <id> --team-id <TEAMID> --password <앱 암호>`.

## 웹사이트

`site/index.html`이 GitHub Pages(https://newids.github.io/bts-key-imac/)로 배포된다. `main`에 `site/` 변경이 푸시되면 `.github/workflows/pages.yml`이 자동 배포한다. 다운로드 버튼은 GitHub API로 최신 릴리스의 DMG를 찾아 가리키므로 릴리스만 올리면 사이트는 손댈 필요가 없다.

## 웹사이트에 올릴 것

- `build/BTSKey-<버전>.dmg`와 `.sha256`.
- 다운로드 페이지 문구: 요구 사항(macOS 13 이상, Apple 실리콘·Intel 모두), 설치 4단계(`설치 안내.txt`와 같음), 첫 실행 안내가 앱 안에 있다는 점, 지원 연락처(`Sources/BTSKeyApp/AppInfo.swift`의 주소).
- 앱 안의 "지원 웹사이트…"·"사용 방법 보기…"·"문제 해결 안내…" 링크는 `AppInfo.swift`의 URL을 가리킨다. 실제 웹사이트 주소가 정해지면 그 파일만 바꾼다.

## 배포 전 점검

- `swift test` 통과.
- `defaults delete kr.newid.btskey hasCompletedOnboarding` 후 실행해 첫 실행 안내가 뜨는지.
- 메뉴 → 도움말 → 진단 로그 내보내기가 데스크탑에 파일을 만드는지.
- 로그인 시 자동 실행 토글이 시스템 설정 → 일반 → 로그인 항목에 반영되는지.
