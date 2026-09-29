# Windows용 빌드 안내 (2026-09-29)

Windows 노트북을 호스트(iMac, Windows PC)의 블루투스 키보드·포인터로 쓰는 버전을 어떻게 빌드하는지 정리한다. **Windows용 앱은 아직 없다.** 이 문서는 지금 빌드할 수 있는 부분, 앱을 만드는 경로, 참고 구현을 빌드하는 방법을 적는다.

근거의 종류를 항목마다 적는다.

- **문서**: 제조사 문서나 프로젝트 저장소에서 직접 읽음
- **실측**: 이 저장소에서 직접 실행해 확인
- **보고**: 다른 프로젝트가 자기 저장소에 적은 결과. 재현하지 않음
- **미확인**: 2차 자료 또는 추론

## 1. 현재 상태

| 부분 | macOS | Windows |
|---|---|---|
| 리포트 규격·인코딩·키코드 표·상태 머신 (`HIDCore`) | 있음 | **같은 소스가 빌드됨** (Linux에서 실측, Windows에서는 미실행) |
| 블루투스 전송 | Classic HID (IOBluetooth) | 없음. BLE HID over GATT로 새로 만들어야 함 |
| 입력 캡처 | CGEvent 탭 | 없음. 저수준 훅으로 새로 만들어야 함 |
| 화면 | 메뉴 막대 앱 | 없음. 트레이 앱으로 새로 만들어야 함 |

이전 분석(`docs/analysis-and-design.md` 7절)에서 바뀐 점:

| 이전 결론 | 확인 결과 | 근거 |
|---|---|---|
| Windows에는 Classic HID 장치 역할 API가 없다 | 맞음. Winsock은 RFCOMM만 제공하고 L2CAP은 커널 드라이버 인터페이스다 | 문서 |
| BLE HID는 `GattServiceProvider`로 게시한다 | 맞음. HID 서비스(0x1812)는 Windows가 막는 서비스 목록에 없다 | 문서 (2026-05-27) |
| A안: Swift on Windows + swift-winrt | **약해짐.** 바로 쓸 수 있는 WinRT 바인딩 저장소들이 보관 처리됐고, 블루투스는 공개된 바인딩에 없다 | 문서 |
| C안: windows-ble-hid를 출발점으로 | 저장소는 있으나 만든 지 8주, 작성자 1명, 스스로 "동작하는 시험판"이라고 적는다 | 문서 |

## 2. 권고

**Windows 쪽 전송·입력 캡처·화면은 C#/.NET으로 만들고, `HIDCore`는 Swift 그대로 두되 어느 플랫폼에서나 빌드되게 유지한다.**

| 선택지 | 판단 | 이유 |
|---|---|---|
| A. Swift on Windows + swift-winrt | 앱 전체로는 권하지 않음 | 바인딩 저장소 보관 처리, 배포된 생성기는 2025-01 버전, 블루투스 바인딩을 만든 사례 없음, 함께 배포할 런타임 파일 목록이 공식 문서에 없음 |
| B. Rust | 권하지 않음 | Microsoft의 바인딩은 활발하지만 참고 구현이 없고 세 번째 언어가 생김 |
| **C. C#/.NET** | **권함** | WinRT를 기본 지원. 가장 어려운 부분(BLE HID 게시, macOS 호스트와의 페어링·재연결)이 MIT 라이선스 참고 구현에 있음. 명령 하나로 x64·arm64 단일 실행 파일 생성 |

C안의 비용은 코어 약 1,300줄을 C#으로 옮기는 것이다. 두 코어가 어긋나지 않게 **바이트 단위 시험 벡터**(키 입력 → 리포트 바이트)를 공유한다. 리포트 규격의 원본은 계속 `ReportDescriptor`다.

## 3. 지금 빌드할 수 있는 것: 공용 코어

`Package.swift`는 macOS 전용 타깃(전송, 입력 캡처, 앱)을 `#if os(macOS)` 안에 둔다. 다른 플랫폼에서는 `HIDCore`와 그 테스트만 빌드된다.

### Windows에서

준비 (문서: swift.org, Swift 6.4.0, 2026-09-14 릴리스, Windows 10 이상, x64·arm64):

1. 설정 → 시스템 → 개발자용에서 **개발자 모드**를 켠다.
2. 관리자 권한이 아닌 터미널에서 실행한다.

```powershell
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget
winget install --id Swift.Toolchain -e --source winget
```

Swift 패키지는 Git과 Python이 없으면 함께 설치한다. 설치 뒤 터미널을 새로 연다.

빌드와 테스트:

```powershell
git clone https://github.com/newids/bts-key-imac.git
cd bts-key-imac
swift build
swift test
```

기대 결과: `HIDCore` 빌드, 테스트 134개 통과.

### 확인된 범위

| 환경 | 결과 | 근거 |
|---|---|---|
| macOS 26, Swift 6.4 | 전체 빌드, 전체 테스트 통과 | 실측 |
| Linux 컨테이너, Swift 6.1.3 | `HIDCore` 빌드, 테스트 134개 통과 | 실측 |
| Windows | 실행하지 않음. Linux와 같은 Foundation 구현을 쓴다(Swift 6부터 모든 플랫폼 공통) | 문서 |

이전 `Package.swift`로는 macOS가 아닌 곳에서 `swift test`가 `no such module 'IOBluetooth'`로 실패했다. `swift test`는 `--filter`를 주어도 모든 타깃을 빌드하기 때문이다(실측, SwiftPM 관리자도 같은 내용을 확인).

### Windows에서 자동으로 확인하기

GitHub의 Windows 실행기에서 같은 명령을 돌릴 수 있다. 아래 작업 흐름은 **추가하지 않았고 실행해 보지 않았다.** 버전 문자열은 내려받기 주소에서 추정한 것이다(미확인). 실행기에는 블루투스가 없으므로 순수 로직만 검증된다.

```yaml
jobs:
  windows:
    runs-on: windows-latest
    steps:
      - uses: compnerd/gha-setup-swift@v0.5.0
        with:
          swift-version: swift-6.4.0-release
          swift-build: 6.4.0-RELEASE
      - uses: actions/checkout@v4
      - run: swift build
      - run: swift test
```

## 4. 참고 구현 빌드: windows-ble-hid

Windows에서 BLE HID 키보드·마우스를 게시하는 공개 구현이다. 앱을 만들기 전에 대상 호스트에서 되는지 먼저 확인하는 용도로 쓴다.

| 항목 | 내용 | 근거 |
|---|---|---|
| 저장소 | https://github.com/abhishek-raj/windows-ble-hid | 문서 |
| 라이선스 | MIT | 문서 |
| 상태 | 2026-08-03 생성, 작성자 1명, 릴리스 v0.5.2(2026-09-19), "working spike" | 문서 |
| 요구 사항 | Windows 10 2004(빌드 19041) 이상, .NET SDK 8.0, 주변장치 역할을 지원하는 블루투스 어댑터 | 문서 |

```powershell
winget install --id Microsoft.DotNet.SDK.8 -e --source winget
git clone https://github.com/abhishek-raj/windows-ble-hid.git
cd windows-ble-hid
dotnet build src\BleHid.Cli\BleHid.Cli.csproj
dotnet run --project src\BleHid.Cli\BleHid.Cli.csproj -- --diagnose
dotnet run --project src\BleHid.Cli\BleHid.Cli.csproj
```

- `--diagnose`가 `Peripheral role : False`를 보이면 그 어댑터로는 되지 않는다.
- 배포된 실행 파일은 서명이 없다. **소스를 읽고 직접 빌드해서 쓴다.** 이 프로그램은 모든 키 입력을 가로채는 프로그램이다.
- `winget`의 .NET 패키지 이름은 확인하지 않았다(미확인). 내려받기는 https://dotnet.microsoft.com/download

저장소가 적은 결과(보고, 재현하지 않음):

| 호스트 | 페어링 | 입력 | 앱을 다시 켠 뒤 재연결 |
|---|---|---|---|
| macOS (버전 표기 없음) | 됨 | 됨 | 자동 |
| Windows 11 | 됨. 목록에서 PC로 보이는 항목을 골라야 함 | 됨 | **안 됨** |
| Android 16 | 됨 | 됨 | 조건부 |

| 어댑터 | 결과 |
|---|---|
| Intel 내장, ASUS USB-BT500, TP-Link UB500, Surface(ARM) | 됨 |
| 저가 CSR 4.0 동글 | 안 됨 |

## 5. Windows 앱을 만들 때의 제약

### 블루투스

| 항목 | 내용 | 근거 |
|---|---|---|
| 최소 버전 | `GattServiceProvider`는 Windows 10 빌드 15063부터. 참고 구현은 19041 이상을 요구 | 문서 |
| 막힌 서비스 | 장치 정보, Generic Attribute, Generic Access, Scan Parameters. 만들면 `DisabledByPolicy` | 문서 |
| 장치 정보 | Windows가 직접 게시한다. 앱이 제조사·제품 번호를 정할 수 없다 | 보고 |
| 표시 종류 | GAP Appearance를 정할 수 없어 호스트에는 키보드가 아니라 컴퓨터로 보인다. Windows 11 24H2 호스트의 "장치 추가"는 종류로 거르므로 "모든 장치 표시"를 눌러야 보일 수 있다 | 보고, 문서 |
| 수명 | 게시한 서비스는 프로세스가 끝나면 사라진다 | 보고 |
| 패키지 | Microsoft 문서는 패키지 매니페스트에 `bluetooth` 기능을 선언하라고 적는다. 공개 구현 두 개는 패키지 없이 실행된다 | 문서, 보고 |
| 관리 정책 | `AllowAdvertising` 정책이 광고를 막을 수 있다 | 보고 |

### 호스트가 Mac일 때

| 항목 | 내용 | 근거 |
|---|---|---|
| Apple의 요구 | BLE HID 액세서리는 HID 서비스를 광고해야 하고, 키를 보관해야 하며, 연결 간격은 15ms의 배수(HID는 11.25ms까지 허용) | 문서 (Accessory Design Guidelines R31, 2026-09-21) |
| macOS 15·26에서의 동작 | 1차 자료를 찾지 못했다 | 미확인 |
| 알려진 실패 | 호스트에 "연결됨"으로 보이지만 입력이 가지 않는 상태. 양쪽에서 페어링을 지우면 풀린다 | 미확인 (ZMK 문서) |
| 한/영 전환 | Mac용과 같이 호스트의 보조 키 설정에서 이 키보드를 골라 Caps Lock → 🌐 fn으로 바꾸는 방식이 될 것으로 보인다 | 미확인 |

Mac용은 Classic, Windows용은 BLE라서 **호스트에는 서로 다른 기기로 등록된다.** 연결 순서, 재연결, 끊김 판별(`docs/bluetooth-link-model.md`)은 Windows용에서 다시 측정해야 한다.

### 입력 캡처

| 항목 | 내용 | 근거 |
|---|---|---|
| 키·버튼 가로채기 | `WH_KEYBOARD_LL`, `WH_MOUSE_LL`. 훅 함수가 0이 아닌 값을 돌려주면 입력이 막힌다 | 문서 |
| 전용 스레드 | 훅을 설치한 스레드에 메시지 루프가 있어야 한다. 훅이 제한 시간(Windows 10 1709부터 최대 1초)을 넘기면 **알림 없이 제거된다.** Mac용의 `InputThread`와 같은 이유로 전용 스레드에 둔다 | 문서 |
| 포인터 이동량 | 마우스 훅은 화면 좌표만 준다. 이동량은 Raw Input(`RIDEV_INPUTSINK`)이 주지만 입력을 막지는 못한다. 참고 구현은 커서를 가운데로 되돌리며 차이를 계산한다 | 문서, 보고 |
| 커서 가두기 | `ClipCursor`. 끝나면 반드시 푼다 | 문서 |
| 잡을 수 없는 것 | Ctrl+Alt+Del(Winlogon이 먼저 등록), UAC 창(보안 데스크톱) | 문서 |
| 관리자 권한 창 | 일반 권한 프로세스의 훅은 관리자 권한 창 위에서 동작하지 않는다. UIAccess는 신뢰된 서명이 필요하다 | 문서(2007), 보고 |

## 6. 배포와 서명

| 방법 | 내용 | 근거 |
|---|---|---|
| 서명 없음 | 버전마다 평판이 0에서 시작한다. Windows 11의 스마트 앱 컨트롤은 평판이 없는 서명 없는 파일을 막는다 | 문서 (2026-05-04) |
| EV 인증서 | 2024년부터 SmartScreen을 바로 통과하지 못한다 | 문서 |
| Azure Artifact Signing | 개인은 미국·캐나다만. 조직은 더 많은 나라에서 가능하고 빠른 시작 문서의 목록에 한국이 있다 | 문서 (2026-08-29, 2026-05-21) |
| Microsoft Store (MSIX) | 무료, Microsoft가 다시 서명, SmartScreen 경고 없음. 모든 입력을 가로채는 앱이 심사를 통과하는지는 모른다 | 문서, 미확인 |
| 그 밖 | 하드웨어 토큰의 OV 인증서, 오픈소스용 SignPath Foundation | 문서 |

Mac용의 규칙(릴리스는 배포용 서명으로만, 실행 파일에 빌드 경로를 남기지 않음)은 Windows용에도 그대로 적용한다.

## 7. 코드를 쓰기 전에 할 시험

| # | 사람 | 프로그램·기록 | 답하는 질문 |
|---|---|---|---|
| 1 | 쓸 Windows 노트북에서 참고 구현을 빌드해 `--diagnose` 실행 | 주변장치 역할 지원 여부 | 이 노트북으로 되는가 |
| 2 | 호스트의 Bluetooth 설정에서 Windows 노트북을 찾아 페어링, 입력, 호스트 잠자기·깨우기, 프로그램 재시작 | 페어링 시간, 재연결 여부, 입력 누락 | 대상 호스트가 Windows가 만든 BLE 키보드를 받는가 |
| 3 | 호스트의 보조 키 설정에서 이 키보드를 골라 Caps Lock → 🌐 fn 설정 | Caps Lock 전송 | 한/영 전환이 같은 방식으로 되는가 |
| 4 | 없음 | Windows 실행기에서 `swift test` | `HIDCore`가 Windows에서 빌드되는가 |
| 5 | 관리자 권한 창 위에서 입력, 1초 멈춤을 일부러 만든 뒤 입력 | 훅 유지 여부 | 훅이 빠지는 경우를 알아챌 수 있는가 |
| 6 | 스마트 앱 컨트롤을 켠 새 Windows 11에서 서명 없는 빌드 실행 | 차단 여부 | 서명 없이 배포할 수 있는가 |

1~3이 통과하면 C#으로 코어를 옮기고 트레이 앱을 만든다. 2가 실패하면 Windows용은 Mac 호스트를 지원할 수 없으므로 범위를 다시 정한다.

## 출처

Swift

- 설치: https://www.swift.org/install/windows/ , https://www.swift.org/install/windows/winget/
- Swift 6.4: https://www.swift.org/blog/swift-6.4-released/
- Swift 6 (Foundation, Swift Testing): https://www.swift.org/blog/announcing-swift-6/
- 조건부 타깃 의존성 SE-0273: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0273-swiftpm-conditional-target-dependencies.md
- `swift test`가 모든 타깃을 빌드: https://forums.swift.org/t/swift-test-tries-to-build-all-targets-instead-of-just-those-needed-for-testing/82803
- swift-winrt: https://github.com/thebrowsercompany/swift-winrt , 보관된 바인딩 https://github.com/thebrowsercompany/swift-uwp
- CI: https://github.com/compnerd/gha-setup-swift , https://github.com/swiftlang/github-workflows

Microsoft

- GATT 서버: https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-server
- `GattServiceProvider`: https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.genericattributeprofile.gattserviceprovider
- 주변장치 역할: https://learn.microsoft.com/en-us/uwp/api/windows.devices.bluetooth.bluetoothadapter.isperipheralrolesupported
- 블루투스와 소켓: https://learn.microsoft.com/en-us/windows/win32/bluetooth/bluetooth-and-socket
- 페어링 지침: https://learn.microsoft.com/en-us/windows-hardware/design/accessory-guidelines/bluetooth-accessory-guidelines/bluetooth-accessory-guidelines-pairing-bonding-connecting
- 저수준 훅: https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc , https://learn.microsoft.com/en-us/windows/win32/winmsg/about-hooks
- Raw Input: https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input
- `ClipCursor`: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-clipcursor
- SmartScreen 평판: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- 코드 서명 선택지: https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
- Artifact Signing: https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart

Apple과 그 밖

- Accessory Design Guidelines: https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf
- windows-ble-hid: https://github.com/abhishek-raj/windows-ble-hid
- WindowsHoGPPeripheral: https://github.com/fknaopen/WindowsHoGPPeripheral
- ZMK 연결 문제: https://zmk.dev/docs/troubleshooting/connection-issues
