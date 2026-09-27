# MacBook → iMac 블루투스 키보드/트랙패드 앱 — 분석 및 설계

작성일: 2026-09-23 (같은 날 실측 결과 반영하여 개정)
상태: 설계 v2 (Classic HID 경로 실기 검증 완료, 트랙패드 성능 스파이크 필요 — §8 참조)

## 1. 목표와 제약

| 우선순위 | 요구사항 |
|---|---|
| 1 (필수) | MacBook이 iMac에 **블루투스 키보드**로 인식되어 키 입력을 전달한다. |
| 2 | MacBook **트랙패드**가 iMac에 블루투스 포인팅 장치로 인식되어 이동·클릭·스크롤을 전달한다. |
| 3 | MacBook 로컬 입력 ↔ iMac 원격 입력 **모드 전환이 매끄럽고 명확**하다. |
| 부가 | Windows용 프로그램을 **단일 소스**로 만들 수 있는지 분석한다. |

제약 (이전 세션에서 확인된 환경):

- iMac은 관리자 권한 요청이 불가능한 관리형 장비다. **iMac 쪽에는 아무것도 설치하지 않는다.** 따라서 네트워크 기반 KVM(Deskflow/Barrier/Synergy)과 Universal Control(동일 Apple ID·Handoff 필요)은 후보에서 제외한다. 단, iMac이 같은 Apple ID로 로그인 가능하면 Universal Control이 코드 없이 요구사항 1·2·3을 모두 만족하므로 먼저 확인할 가치가 있다.
- 복잡한 기능(멀티 디바이스, 클립보드 동기화, 미디어 키 등)은 범위 밖이다.

### 1.1 확인된 환경 (2026-09-23 실측)

| 항목 | 값 |
|---|---|
| iMac | 2019 (Intel), macOS Sequoia 15.7.5, 관리자 권한 없음, 호스트명 `iMac-A`, BT 주소 `AA:AA:AA:AA:AA:01` |
| MacBook | Bluetooth 컨트롤러 BCM_4388 (Apple 실리콘, HID/GATT 서비스 지원), macOS Tahoe |
| KeyPad 2.30 실측 | **키보드 정상**. 트랙패드는 **사용 불가 수준으로 느림**. 일반 사용자 계정으로 페어링 가능(관리자 불필요) 확인. |
| KeyPad 연결 형태 | MacBook 쪽 `system_profiler`에서 iMac이 **Classic ACL**로 연결됨(BLE 아님). |

이 실측으로 다음이 확정되었다.

- iMac(15.7.5, 비관리자)은 Mac이 에뮬레이션한 **Bluetooth Classic HID 키보드**를 페어링·수락한다. 요구사항 1의 기술 리스크는 해소되었다.
- 남은 핵심 과제는 **트랙패드 성능**(요구사항 2)과 **모드 전환 UX**(요구사항 3)다. 즉 "되느냐"가 아니라 "KeyPad보다 얼마나 잘 되느냐"의 문제다.

## 2. 기존 제품·오픈소스 조사

| 이름 | 플랫폼(컨트롤러) | 방식 | 요점 |
|---|---|---|---|
| KeyPad (bluetooth-keyboard.com, Toolbunch) | macOS 11+ | **Bluetooth Classic HID (IOBluetooth)** | 참조 URL의 제품. 키보드+마우스, Mac→Mac 지원, 핫키(⌘⌥P) 토글, Tahoe 지원, Pro $4.99. 이 환경에서 키보드 동작 확인. 내부 구조는 §2.1. |
| Typeeto (Eltima) | macOS | BT HID | iPhone/iPad/Apple TV 대상, $7.99. |
| 1Keyboard | macOS | BT HID | 메뉴바 상주, 장치별 단축키. |
| across (acrosscenter.com) | Windows/macOS/Linux | BT HID + RFCOMM | Windows에서 BT 키보드/마우스 에뮬레이션을 상용으로 구현. 최대 6대 페어링, 4대 동시 제어. |
| darwin-bt-remote (peladam, AGPL-3.0) | macOS 13+, iOS 15+ | **BLE HOGP**(CoreBluetooth) + Classic HIDP(IOBluetooth) | 키보드·마우스·미디어. 대상 OS에 macOS 10.3+ 포함. macOS Classic HIDP는 **아웃바운드 전용**이라 Android만 도달. AGPL이므로 코드 복사 불가, 구조 참고만. |
| windows-ble-hid (abhishek-raj, MIT) | Windows 10 2004+ | **BLE HOGP**(WinRT GattServiceProvider) + WH_KEYBOARD_LL/WH_MOUSE_LL | C#/.NET 8. 키보드(Report 1)+마우스(Report 2). **macOS 대상 자동 재연결 동작 확인.** 어댑터의 주변장치 역할 지원 필수. |
| Bluetooth-Keyboard-Emulator (ArthurYidi, Unlicense) | macOS ≤10.14 | Classic HID(IOBluetooth) | Catalina 이후 페어링/HID 게시 불가로 2020년 아카이브. |

### 2.1 KeyPad 2.30 내부 구조 (이 MacBook의 설치본 분석)

바이너리 링크·문자열·번들 리소스만 확인했다(코드 복사 없음).

- 링크 프레임워크: IOBluetooth, IOBluetoothUI, Carbon, CoreGraphics, GameController. **CoreBluetooth 미사용** → BLE가 아니라 Classic HID.
- `IOBluetoothSDPServiceRecord.publishedServiceRecord(with:)`로 SDP를 게시한다. 실측(`docs/connection-audit.md`) 결과 KeyPad가 성공한 연결은 **iMac이 먼저** PSM 0x11/0x13을 연 인바운드였고, bluetoothd는 SDP를 게시한 서드파티 세션으로 그 채널을 넘긴다. MacBook→iMac 아웃바운드도 동작한다.
- SDP 레코드(`KeyboardDictionary.plist`): ServiceClass 0x1124(HID), HIDDeviceSubclass 0xC0(키보드+포인팅 조합), HIDReconnectInitiate/VirtualCable/NormallyConnectable/BootDevice = true, SupervisionTimeout 0x1F40, CountryCode 0x21(US).
- 리포트 디스크립터(190B): Report 1 = 키보드(8비트 modifiers + 6KRO + 벤더 바이트), Report 2 = Consumer(14비트), **Report 10 = 마우스: 버튼 2개, X/Y/Z/Wheel 각 Int8(-127~127)**.
- 마우스 입력원: **GameController 프레임워크 `GCMouse`의 `mouseMovedHandler`**(원시 장치 델타). 감도·배율·보고 주기 관련 설정 키가 UserDefaults·문자열 어디에도 없다.

트랙패드가 느린 원인(가설, §6.4에서 검증): (a) 트랙패드의 원시 델타는 macOS 트랙패드 드라이버의 가속·스케일링을 거치기 전 값이라 작다, (b) 여기에 배율 없이 Int8로 그대로 실어 보내면 iMac 쪽 마우스 가속 곡선의 저속 구간에 머문다, (c) `GCMouse` 경로가 트랙패드에서 이벤트 레이트를 낮게 주거나 코얼레싱할 가능성. 우리 설계는 이 세 가지를 모두 피한다.

결론: 이 카테고리는 이미 상용·오픈소스로 검증된 영역이다. "구매 vs 개발" 관점에서 KeyPad가 요구사항 1~3을 이미 충족한다. 개발을 진행한다면 참고 구현이 충분히 있으므로 기술 리스크는 낮은 편이다.

## 3. 전송 방식 타당성 분석

### 3.1 후보 비교

| 방식 | macOS 컨트롤러 | Windows 컨트롤러 | iMac(호스트) 인식 | iMac 설치 | 판정 |
|---|---|---|---|---|---|
| **Bluetooth Classic HID (HIDP, L2CAP 0x11/0x13)** | IOBluetooth로 SDP 등록 후 인바운드(iMac이 먼저 연결)와 아웃바운드 모두 가능(macOS 26 실측). SDP를 게시하면 bluetoothd가 HID PSM 인바운드를 앱으로 넘긴다. Ventura의 SDP 게시 크래시는 Sonoma에서 수정됨. | 인박스 스택에 HID 장치 역할 공개 API 없음. | 알려진(본딩된) 주소에서의 인바운드 수락. **KeyPad로 이 iMac(15.7.5)에서 실증.** | 없음 | **1안 (채택)** |
| **BLE HID over GATT (HOGP)** | CoreBluetooth `CBPeripheralManager`. 16비트 `1812`는 "not allowed" 오류지만 **128비트 문자열 `00001812-0000-1000-8000-00805F9B34FB`로 선언하면 게시 가능**(darwin-bt-remote 실사용). | WinRT `GattServiceProvider`. MS 문서의 차단 서비스 목록은 DIS/GATT/GAP/SCP뿐이며 HID는 허용(windows-ble-hid 실사용). | BLE 키보드/마우스로 페어링. macOS는 GATT 캐시가 공격적이라 Service Changed 처리 필요. 이 iMac에서는 미검증. | 없음 | **2안** (Windows 공용 경로, Classic 실패 시 대체) |
| 네트워크 KVM (Deskflow 등) | 가능 | 가능 | 소프트웨어 설치 필요 | **필요** | 제외 |
| Universal Control | 내장 | 불가 | 동일 Apple ID | 없음 | 환경 허용 시 최우선 확인 |
| 하드웨어 동글 (ESP32-S3 등, USB 시리얼 ↔ BT HID) | 가능 | 가능 | 진짜 BT 키보드로 인식 | 없음 | 대안. 펌웨어가 단일 소스가 되지만 하드웨어 필요. |

### 3.2 채택 근거

- **Classic HID는 바로 이 iMac·이 OS 버전·비관리자 계정에서 동작이 실증되었다**(KeyPad). 남은 불확실성이 가장 적다.
- Classic HID 인터럽트 채널은 BLE 알림보다 페이로드·주기 제약이 느슨해 마우스 리포트를 Int16 델타·고주기로 보내기 유리하다.
- 공개 API(IOBluetooth)만 사용한다. Developer ID 배포에 문제없다.
- BLE HOGP는 Windows와 공유 가능한 유일한 경로이므로 전송 계층을 프로토콜(인터페이스) 뒤에 두고 2안으로 유지한다.

### 3.3 알려진 제약

- Classic: 본딩 후 앱이 SDP를 **앱 수명 동안 한 번** 게시한다. 제거 후 재게시하면 bluetoothd가 PSM 등록을 풀지 않아 실패한다. 게시한 세션이 없을 때 iMac이 연결해 오면 MacBook 자체 HID 호스트가 가로채 iMac을 입력 장치로 등록하므로, 앱 실행 중에는 항상 게시·수신 대기 상태를 유지한다. 세부 근거는 `docs/connection-audit.md`.
- Classic: 유휴 시 호스트가 링크를 sniff 모드로 내리므로 첫 입력에 지연이 생길 수 있다. 원격 모드 동안 저주기 keep-alive(빈 마우스 리포트 없이, HID 규격상 허용되는 idle 처리)를 검토한다.
- HOGP(2안): **암호화·본딩 필수**. 오래된 본딩이 남으면 양쪽 재페어링으로만 복구된다. macOS 14.2 이후 호스트가 인증되지 않은 페어링을 더 엄격히 다루므로 Just Works 수용 여부를 PoC로 확인해야 한다.
- 트랙패드는 iMac에 **상대 좌표 마우스**로 보인다. 멀티터치 제스처(핀치, 3손가락 스와이프)는 표준 HID 마우스로 표현되지 않으므로 범위 밖. 두 손가락 스크롤은 휠 리포트로 전달한다.
- BLE(2안)에서는 알림 크기·주기 한계로 델타 폭과 보고 주기가 제한된다. Classic(1안)에서는 Int16 델타를 쓴다(§6.4).

## 4. iMac(호스트) 쪽 동작 시나리오 (1안 Classic)

1. 최초 1회: MacBook과 iMac을 일반 Bluetooth 페어링으로 본딩한다(어느 쪽에서 시작해도 됨, 관리자 불필요 — 실증됨).
2. 앱 시작: SDP에 HID 레코드(§6.1)를 한 번 게시하고 PSM 0x11/0x13 인바운드 알림을 등록한다. 마지막 의도가 "연결"이면 바로 아웃바운드 연결을 시도한다.
3. 아웃바운드: ACL → 제어(0x11) → 인터럽트(0x13) 순으로 연다(실측 0.3~2.3초). 인바운드: iMac이 잠자기 복귀 등으로 0x11→0x13을 열면 선택한 iMac일 때만 수락한다.
4. iMac이 제어 채널로 SET_PROTOCOL·SET_REPORT를 보내고 원격 SDP를 조회해 키보드+마우스(subclass 0xC0)로 등록한다.
5. 끊기면 2→4→8→16→30초 백오프로 재시도하고, Mac 잠자기 복귀 시 즉시 재시도한다. 15초 워치독으로 "연결 중"에 갇히지 않는다.
6. 사용자가 "연결 해제"하면 채널만 닫고 인바운드를 거절한다. SDP 레코드는 앱 종료 때만 제거한다.

2안(BLE)의 시나리오는 광고 → iMac 설정에서 페어링 → GATT 캐시 → 자동 재연결 순이며 §6.1의 GATT 레이아웃을 따른다.

## 5. 아키텍처

```
┌──────────────────────── MacBook (컨트롤러) ────────────────────────┐
│                                                                    │
│  InputCapture (CGEventTap, 세션 레벨)                              │
│    키 다운/업, flagsChanged, 마우스 이동/버튼/스크롤 캡처           │
│    원격 모드에서는 이벤트를 삼킴(return nil), 커서 잠금             │
│            │ PlatformKeyEvent / PointerDelta                       │
│            ▼                                                       │
│  HIDCore (순수 로직, OS 프레임워크 의존 없음)                       │
│    KeycodeMap: macOS vkey → USB HID Usage                          │
│    ReportEncoder: Keyboard(6KRO), Mouse, (Consumer 선택)            │
│    SessionStateMachine: Idle→Advertising→Connected{Local,Remote}   │
│            │ HIDReport(id, bytes)                                  │
│            ▼                                                       │
│  HIDTransport 프로토콜                                              │
│    ├ ClassicHIDTransport (IOBluetooth) — 1안                        │
│    │   SDP 게시, L2CAP 0x11/0x13 아웃바운드, 인터럽트 채널 전송      │
│    └ BLETransport (CoreBluetooth) — 2안/Windows 공용                │
│        GATT 트리, 광고, 구독 추적, updateValue 백프레셔 큐          │
│            │ Bluetooth                                             │
└────────────┼───────────────────────────────────────────────────────┘
             ▼
        iMac (HID 호스트, 무설치)
```

모듈 경계를 SwiftPM 타깃으로 강제한다.

| 타깃 | 의존 | 역할 |
|---|---|---|
| `HIDCore` | Foundation만 | Report Map 상수, 리포트 인코더, 키코드 테이블, 상태 머신. 단위 테스트 대부분이 여기에 몰린다. |
| `ClassicHIDTransport` | IOBluetooth, HIDCore | SDP 레코드 게시/제거, 아웃바운드 L2CAP 채널, 제어 채널 응답(GET/SET_REPORT, SET_PROTOCOL, 가상 케이블 분리), 인터럽트 채널로 리포트 전송. 재접속은 `SessionController`가 3초 백오프로 담당. |
| `BLETransport` | CoreBluetooth, HIDCore | (2안) 주변장치 관리자, GATT 구성, 연결/구독 상태, 전송 큐. |
| `InputCapture` | CoreGraphics/AppKit, HIDCore | 이벤트 탭, 핫키 감지, 커서 잠금/복원, 권한 확인. |
| `BTSKeyApp` | AppKit | `SessionController`(상태 머신·전송·캡처·HUD 결합), 메뉴바 아이템(3상태 아이콘), 대상 장치·포인터 배율 설정, 권한 안내. |

## 6. 상세 설계

### 6.1 전송 계층 사양

#### 6.1.1 Classic HID SDP 레코드 (1안)

`IOBluetoothSDPServiceRecord.publishedServiceRecord(with:)`에 넘길 딕셔너리. KeyPad와 같은 표준 속성 구성을 따르되 리포트 디스크립터는 §6.2의 우리 것을 넣는다.

| 속성 | 값 |
|---|---|
| 0x0001 ServiceClassIDList | 0x1124 (HID) |
| 0x0004 ProtocolDescriptorList | L2CAP PSM 0x0011, HIDP |
| 0x000D AdditionalProtocolDescriptorList | L2CAP PSM 0x0013, HIDP |
| 0x0009 ProfileDescriptorList | 0x1124 v1.1 |
| 0x0201 HIDParserVersion | 0x0111 |
| 0x0202 HIDDeviceSubclass | 0xC0 (키보드+포인팅 조합) |
| 0x0203 HIDCountryCode | 0x21 (US) |
| 0x0204/0x0205/0x020D/0x020E | VirtualCable, ReconnectInitiate, NormallyConnectable, BootDevice = true |
| 0x0206 HIDDescriptorList | 0x22(Report) + §6.2 디스크립터 |
| 0x020C HIDSupervisionTimeout | 0x1F40 |
| 0x0100/0x0102 | 서비스명, 제공자명 |

연결 절차(아웃바운드, 메인 스레드 비동기): `openConnection(target)` → `connectionComplete` → `openL2CAPChannelAsync(0x11)` → 열림 콜백 → `openL2CAPChannelAsync(0x13)`. 인바운드는 `IOBluetoothL2CAPChannel.register(forChannelOpenNotifications:…direction: incoming)`. 백그라운드 스레드에서 IOBluetooth를 쓰면 `kIOReturnError`로 실패한다. 인터럽트 채널로 `0xA1 | ReportID | payload`(DATA, Input) 프레임을 쓴다. 제어 채널로 오는 SET_REPORT(LED)·SET_PROTOCOL은 응답만 하고 무시한다.

#### 6.1.2 GATT 레이아웃 (2안)

모든 SIG UUID는 128비트 문자열로 선언한다(16비트 단축형은 macOS/iOS에서 거부됨).

- **HID Service (1812)** — Include: Battery Service
  - Report Map (2A4B) read, encryption required
  - Report (2A4D) × N — 각 Report에 Report Reference 디스크립터(2908)로 Report ID/Type 지정, notify + read
  - Boot Keyboard Input (2A22) notify, Boot Keyboard Output (2A32) write/write-without-response, Boot Mouse Input (2A33) notify — 일부 호스트가 부트 모드만 인식하므로 포함
  - HID Information (2A4A) read: bcdHID 0x0111, country 0, flags RemoteWake|NormallyConnectable
  - Protocol Mode (2A4E) read/write-without-response
  - HID Control Point (2A4C) write-without-response
- **Battery Service (180F)** — Battery Level (2A19) read/notify. MacBook 실제 배터리 % 반영(IOKit) 또는 100 고정.
- **Device Information (180A)** — Manufacturer Name, Model Number, PnP ID(2A50). 호스트에 키보드 종류 힌트를 준다.

광고 데이터: Local Name + Service UUIDs `[HID]`(HID를 첫 번째로). Appearance는 Keyboard(0x03C1) 또는 Keyboard+Mouse 조합. 연결 후 미구독 상태가 길어지면 임시 서비스 추가/제거로 Service Changed를 유도해 macOS의 GATT 캐시를 무효화한다.

### 6.2 Report Map (구현 기준, `Sources/HIDCore/ReportDescriptor.swift`)

| Report ID | 방향 | 페이로드 |
|---|---|---|
| 1 | Input | 키보드: 1B modifiers, 1B reserved, 6B keycodes (6KRO) |
| 1 | Output | 키보드 LED 5비트 + 패딩 3비트 (Caps Lock 표시용, 수신만 하고 무시) |
| 2 | Input | 마우스: 1B buttons(3), **Int16 X, Int16 Y**(logical −32767..32767), Int8 Wheel, Int8 AC Pan |

Int16 델타는 macOS·Windows 호스트 모두 지원하며, 배율을 올려도 ±127 클램프로 뭉개지지 않게 한다(KeyPad는 Int8). Consumer Control(볼륨·밝기)은 선택 사항으로 남긴다. HIDP 인터럽트 프레임은 `0xA1, ReportID, payload` 순서다.

### 6.3 키보드 매핑

- macOS 가상 키코드 → USB HID Usage(Keyboard/Keypad page 0x07) 정적 테이블. 한글 키보드의 **한/영 전환은 iMac 쪽 설정**(Caps Lock 또는 오른쪽 ⌘)이 처리하므로 원시 키코드만 충실히 전달한다.
- 수정자는 `CGEventFlags` → HID modifier 비트(LCtrl, LShift, LAlt=Option, LGUI=Command, 우측 변형 포함).
- 자동 반복 이벤트는 버린다(호스트가 반복 생성).
- Fn/Globe 키는 이벤트 탭에서 안정적으로 잡히지 않으므로 지원 범위 밖으로 명시한다.
- 모드 전환 시 **all-keys-up 리포트**를 보내 iMac에 눌린 키가 남지 않게 한다.

### 6.4 트랙패드 캡처와 성능 (요구사항 2의 핵심)

KeyPad의 "사용 불가 수준" 느림을 피하기 위한 설계 원칙: **가공된 픽셀 델타를, 배율을 곱해, 16비트로, 빠짐없이, 고주기로** 보낸다.

- **입력원**: `GCMouse` 원시 델타가 아니라 **CGEventTap의 `mouseMoved`/`*Dragged` 이벤트의 `deltaX/deltaY`**를 쓴다. 이 값은 macOS 트랙패드 드라이버의 가속·해상도 처리를 이미 거친 포인터 픽셀 단위라 손가락 움직임과 화면 이동의 비례감이 로컬과 같다.
- **배율과 소수 누적**: 델타에 사용자 배율(기본 1.5, 범위 0.5~4.0)을 곱하고 소수 잔여를 다음 틱으로 이월한다(정수 절삭으로 미세 움직임이 사라지는 문제 방지).
- **16비트 델타**: Report Map의 X/Y를 Int16으로 선언해 빠른 플릭에서도 클램프가 발생하지 않게 한다.
- **코얼레싱, 드롭 금지**: 이벤트를 8ms(125Hz) 틱으로 합산해 한 리포트로 보낸다. 전송 큐가 막히면 델타를 합산해 두었다가 다음 틱에 보내며, 버리지 않는다. 버튼 변화는 틱을 기다리지 않고 즉시 보낸다.
- **커서 잠금**: 원격 모드에서 `CGAssociateMouseAndMouseCursorPosition(false)` + `NSCursor.hide()`로 로컬 커서를 화면과 분리해 델타가 화면 가장자리에서 끊기지 않게 한다. 로컬 복귀 시 원래 위치·표시 상태 복원.
- **클릭**: left/right/other 다운/업 → 버튼 비트, 즉시 전송. 트랙패드 두 손가락 클릭은 macOS가 이미 우클릭 이벤트로 준다.
- **스크롤**: `scrollWheel`의 deltaAxis1/2(픽셀 단위, `scrollWheelEventIsContinuous`)를 누적해 휠/AC Pan 정수 단위로 변환. 관성 phase는 감쇠 계수(설정)로 처리하거나 끈다.
- **Classic sniff 지연**: 원격 모드 진입 시 첫 리포트 지연을 측정한다. 체감 지연이 있으면 앱이 원격 모드 동안 링크를 활성으로 유지하는 방법(주기적 빈 입력이 아닌, IOBluetooth의 sniff 관련 공개 API 여부 확인)을 스파이크에서 검토한다.
- **iMac 쪽 설정**: 시스템 설정 → 마우스 → 이동 속도는 사용자 설정이라 관리자 없이 조정 가능하다. 온보딩에서 안내한다.

성능 목표(스파이크 S3에서 측정): 리포트 주기 ≥ 100Hz, 손가락 움직임 대비 iMac 커서 이동 비율이 로컬 대비 ±20% 이내, 한 번의 빠른 스와이프로 iMac 화면 폭 절반 이상 이동, 체감 지연 없음(정량 목표 < 30ms).

### 6.5 모드 전환 UX (요구사항 3)

상태 머신:

```
Idle ──start──▶ Advertising ──central subscribed──▶ Connected.Local
                     ▲                                   │  ▲
                     │ disconnect (자동 Local 복귀)       │  │ 토글 핫키 / 이스케이프
                     └──────────────── Connected.Remote ◀┘──┘
```

- **토글 핫키** 기본값 `⌥⌘K`(설정에서 변경). 같은 키로 양방향 전환. 핫키 자체는 iMac으로 전달하지 않는다.
- **이스케이프 해치**: 연결 끊김, 앱 종료, 화면 잠금 시 무조건 Local로 복귀. 원격 모드에서 핫키를 3회 연타하면 Local로 강제 복귀(핫키 설정이 꼬였을 때 대비).
- **명확성**:
  - 메뉴바 아이콘 3상태: 회색(미연결) / 외곽선(연결, Local) / 채움+색상(Remote 캡처 중).
  - 전환 시 1초 HUD 오버레이("→ iMac" / "→ MacBook")와 선택적 사운드.
  - Remote 모드 중 MacBook 화면 상단에 얇은 색상 테두리를 그려 현재 입력이 밖으로 나가고 있음을 표시(설정으로 끌 수 있음).
- **부드러움**: 전환 시 all-keys-up + 버튼 해제 리포트 전송, 수정자 상태 초기화, 커서 위치 저장/복원. 전환 지연 목표 < 50ms.
- 화면 가장자리 이동으로 전환하는 "edge switch"는 2단계 이후 옵션.

### 6.6 권한·배포

- Accessibility + Input Monitoring 권한 필요(이벤트 탭). 온보딩 화면에서 상태 확인 및 시스템 설정 딥링크 제공.
- App Sandbox: CoreBluetooth는 `com.apple.security.device.bluetooth` 엔타이틀먼트로 가능하나, 세션 레벨 이벤트 탭은 샌드박스 밖이 안전하다. **비앱스토어 배포(Developer ID + 노타라이즈)**를 기본으로 한다.
- `NSBluetoothAlwaysUsageDescription` 필수.

## 7. Windows 단일 소스 가능성 분석

### 7.1 결론

**프로토콜·로직 계층은 단일 소스가 가능하고, 전송·입력 캡처·UI 계층은 OS별 구현이 불가피하다.** 전체 코드의 대략 절반이 공유 가능하다.

| 계층 | macOS | Windows | 공유 |
|---|---|---|---|
| HID Report Map, 리포트 인코딩, 키코드 테이블, 상태 머신 | 순수 로직 | 순수 로직 | **가능** (플랫폼 키코드 → HID 변환 테이블만 OS별 데이터) |
| BLE 주변장치 | CoreBluetooth (128비트 UUID 우회) | WinRT `GattServiceProvider` (어댑터가 peripheral role 지원해야 함; 저가 어댑터 다수 미지원) | 인터페이스만 공유, 구현 별도 |
| 입력 캡처 | CGEventTap + Accessibility 권한 | `SetWindowsHookEx(WH_KEYBOARD_LL/WH_MOUSE_LL)` + `ClipCursor` | 별도 |
| UI | 메뉴바(SwiftUI/AppKit) | 트레이(WinUI/WPF) | 별도 |

Classic HID는 Windows 인박스 스택에 장치 역할 API가 없으므로 단일 소스 후보가 아니다. BLE HOGP만이 양 OS에서 공개 API로 동작한다. 따라서 Mac 1안(Classic)을 채택한 현재 구조에서 Windows를 추가하면 전송 구현이 세 개(Classic-Mac, BLE-Mac, BLE-Win)가 되며, 공유되는 것은 `HIDCore`와 리포트 규격뿐이다.

### 7.2 언어·스택 선택지

| 선택지 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **A. Swift 코어 + OS별 셸** (Mac: Swift, Win: Swift on Windows + swift-winrt) | Mac 1순위 요구에 최적. `HIDCore`는 순수 Swift라 Windows 툴체인에서 그대로 빌드. | Windows 쪽 Swift/WinRT 생태계가 소수. Windows 셸 개발 난이도 높음. | Mac 우선이면 최선 |
| B. Rust 코어 + 얇은 셸 | `ble-peripheral-rust`가 macOS(CoreBluetooth)·Windows(WinRT) 주변장치를 한 API로 제공. 코어+전송까지 공유 폭 최대. | Mac 메뉴바·권한·이벤트 탭은 결국 Swift/ObjC FFI 필요. 빌드 복잡도 상승. | Windows가 확정 요구면 최선 |
| C. C#/.NET | windows-ble-hid(MIT)를 그대로 출발점으로 사용 가능. .NET for macOS에 CoreBluetooth/CoreGraphics 바인딩 존재. | Mac 쪽 배포·권한 UX가 비관용적, 앱 크기 큼. | Windows 우선이면 고려 |
| D. 하드웨어 동글 펌웨어 | 컨트롤러 OS 무관, 진짜 단일 소스. | 하드웨어 구매·휴대 필요. | 대안 |

### 7.3 권고

1순위 요구가 macOS이므로 **A안**으로 시작하되, `HIDCore`를 Foundation 의존만으로 유지하고 전송·캡처를 프로토콜(인터페이스) 뒤에 둔다. Windows 필요가 확정되는 시점에 (a) `HIDCore`를 Swift on Windows로 그대로 빌드하거나, (b) 규모가 작은 코어(예상 1~2천 줄)를 C#으로 포팅해 windows-ble-hid와 결합한다. 어느 쪽이든 리포트 포맷과 상태 머신 사양은 이 문서를 단일 진실 원천으로 삼는다.

## 8. 리스크와 검증 스파이크 (구현 전 순서대로)

| # | 상태 | 검증 항목 | 성공 기준 | 실패 시 대안 |
|---|---|---|---|---|
| S0 | **완료** (KeyPad 실측) | iMac 15.7.5 비관리자 계정이 Mac 에뮬레이션 Classic HID 키보드를 페어링·수락 | 키 입력 정상 | — |
| S1 | 링크 완료 | 우리 SDP 레코드 게시 + 아웃바운드 L2CAP 0x11/0x13 개방, iMac의 SET_PROTOCOL 수신 | 채널 개방 확인(2026-09-23) | 실제 키 입력 표시는 사용자 확인 필요 |
| S2 | 부분 완료 | 앱 재시작·재연결(0.1~2.3초), 백오프·워치독 구현. iMac 절전 복귀 시 인바운드 수락은 미검증 | 10초 내, 재페어링 불필요 | `docs/connection-audit.md` |
| **S3** | 대기, **최우선** | §6.4 설계대로 마우스 리포트(Int16, 125Hz, 배율) 전송 → KeyPad와 나란히 비교 | §6.4 성능 목표 충족 | 배율·틱 조정, sniff 처리, 최후에는 BLE 경로 비교 |
| S4 | 대기 | CGEventTap으로 로컬 이벤트 삼킴 + 커서 잠금 + 핫키 복귀 | 키가 MacBook에 새지 않고 복귀 100% | NSEvent 모니터 + 포커스 트릭 |
| S5 | 대기 | 한글 입력(iMac 쪽 입력 소스 전환) | Caps Lock/우⌘ 전환 정상 | 전환 키 별도 매핑 |
| S6 | 2안 전용 | macOS 14.2+ 호스트의 Just Works BLE 본딩 수용 여부 | 키 입력 수락 | 패스키 표시형 페어링 |

빠른 진단(코드 없이 지금 가능): iMac 시스템 설정 → 마우스 → 이동 속도를 최대로 올린 뒤 KeyPad 트랙패드를 다시 써 본다. 크게 나아지면 원인은 배율(§6.4 배율·Int16로 해결), 여전히 끊기거나 늦으면 원인은 보고 주기·sniff(§6.4 코얼레싱·sniff 항목)다. 이 결과는 S3의 우선 조정 방향을 정한다.

기타 리스크:

- 2019 iMac은 Bluetooth 4.2 세대다. 1안(Classic)에는 영향이 없고, 2안(BLE)에서는 LE 2M PHY가 없어 알림 처리량이 더 제한된다.
- MacBook이 Classic 컴퓨터로도 보이므로 iMac 목록에 항목이 둘 보일 수 있다(온보딩 안내로 완화).
- AGPL 코드(darwin-bt-remote)는 참고만 하고 복사하지 않는다. KeyPad는 바이너리 구조만 확인했으며 리소스·코드를 재사용하지 않는다.

## 9. 로드맵

| 단계 | 산출물 | 범위 |
|---|---|---|
| 0 | S1·S3 스파이크(Classic 키 1개 + 트랙패드 성능 비교) 결과 기록(docs/spikes/) | 타당성·차별점 확정 |
| 1 | `HIDCore` + 단위 테스트(리포트 인코딩, 키코드 매핑, 델타 배율·이월, 상태 머신) | TDD, 80%+ |
| 2 | `ClassicHIDTransport` + 메뉴바 최소 앱 → 키보드 전달(요구사항 1) | 수동 E2E |
| 3 | `InputCapture` 트랙패드 → 마우스 리포트, 성능 튜닝(요구사항 2) | S3 목표 재측정 |
| 4 | 모드 전환 UX 완성: 핫키·HUD·아이콘·이스케이프 해치(요구사항 3) | |
| 5 | 온보딩(권한·페어링 안내), 설정(핫키·감도), Developer ID 노타라이즈 | 배포 |
| 6 (선택) | `BLETransport`(2안) 구현 → Windows 포팅: `HIDCore` 재사용 + WinRT 전송 + LL 훅 | §7 |

## 10. 참고 자료

- KeyPad 기능/제품: https://bluetooth-keyboard.com/features/ , https://bluetooth-keyboard.com/mouse/ , App Store id1491684442
- darwin-bt-remote (AGPL-3.0): https://github.com/peladam/darwin-bt-remote — `BTRemote/LowEnergy/HIDProfile.swift`, `HIDPeripheral.swift`, `DirectInputController.swift`
- windows-ble-hid (MIT): https://github.com/abhishek-raj/windows-ble-hid
- Bluetooth-Keyboard-Emulator (아카이브): https://github.com/ArthurYidi/Bluetooth-Keyboard-Emulator
- CoreBluetooth HID 128비트 UUID 우회 논의: https://gist.github.com/conath/c606d95d58bbcb50e9715864eeeecf07
- IOBluetooth SDP 게시 시 bluetoothd 크래시(Ventura, Sonoma 수정): https://developer.apple.com/forums/thread/730439
- Windows GATT Server 문서(차단 서비스 목록): https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/gatt-server
- macOS HID 호스트 인바운드 연결 동작(CVE-2023-45866 분석): https://github.com/skysafe/reblog/blob/main/cve-2024-0230/README.md
- across (Windows BT HID 에뮬레이션 상용): https://www.acrosscenter.com/manual/bluetooth-connection
- ble-peripheral-rust: https://github.com/rohitsangwan01/ble-peripheral-rust
- Universal Control 요구사항: https://support.apple.com/en-us/102459
