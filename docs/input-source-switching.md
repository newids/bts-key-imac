# 입력 소스(한/영) 전환

MacBook의 키 하나(Caps Lock)로 호스트의 한/영을 바꾸는 방법을 정리한다. 2026-09-29 조사와 실기 결과를 담는다.

## 결론

앱은 Caps Lock을 그대로 보내고, iMac의 보조 키 설정에서 **MacBook 키보드를 골라** Caps Lock을 🌐 fn으로 바꾼다. iMac의 다른 키보드에 하던 설정을 MacBook 키보드에도 한 번 하는 것이다. 터미널이 필요 없고 iMac-D(macOS 15.7.4)에서 동작을 확인했다.

1. iMac의 시스템 설정 → 키보드 → 키보드 단축키… → 보조 키
2. 맨 위 "키보드 선택" 단추를 눌러 MacBook의 이름을 고른다.
3. Caps Lock 키 → 🌐 fn 기능
4. "🌐 키를 누를 때"는 "입력 소스 변경"

MacBook 쪽만으로 해결하는 방법은 찾지 못했다. 이유는 아래 "원인 확정"에 있다.

## 요구

- MacBook의 Caps Lock을 짧게 누르면 호스트의 입력 소스가 한글과 영문 사이를 오간다.
- 호스트(여러 사람이 쓰는 관리되는 iMac)의 설정 변경은 가능한 한 없어야 한다. 설치는 할 수 없다.
- 나중에 Windows 호스트에서도 같은 키로 동작해야 한다.

## 공용 iMac에서 흔한 설정

- 🌐(fn) 키를 누를 때: 입력 소스 변경
- 보조 키: Caps Lock → 🌐 fn 기능
- 일부는 ⌃스페이스를 쓴다.

iMac 자체 키보드에서는 Caps Lock이 🌐로 바뀌어 한/영이 전환된다. 보조 키 설정은 키보드별로 적용된다.

## 앱이 보내는 키

| 메뉴 항목 | 보내는 것 |
|---|---|
| Caps Lock 그대로 (기본) | 키보드 페이지 0x07, 사용 0x39 |
| 🌐 키로 바꿔 보내기 | Apple 벤더 페이지 0xFF, 사용 0x03 바이트를 누르는 동안 1 |
| ⌃스페이스로 바꿔 보내기 | 왼쪽 Control + 0x2C 한 번 |

선택은 호스트 주소별로 저장된다(`CapsLockPreferences`).

시험해 보고 뺀 것: ⌘스페이스, ⌃⌥스페이스, 한/영 키(LANG1 0x90), 표준 🌐(소비자 제어 0x029D, 리포트 ID 3). 아래 실기 결과 참고.

## 조사 결과

| 보내는 키 | macOS 호스트 | Windows 호스트 (한국어 IME) | 호스트 설정 | 근거 |
|---|---|---|---|---|
| Caps Lock 0x39 | 설정이 있으면 전환 | 대문자 고정 | 보조 키에서 이 키보드의 Caps Lock → 🌐, 또는 "Caps Lock 키로 ABC 입력 소스 전환" | Apple 지원 문서, 사용자 보고 |
| Apple 🌐 바이트 0xFF/0x03 | 호스트가 기기에 `AppleVendorSupported`를 붙인 경우에만 처리 | 무시 | 🌐 → 입력 소스 변경 | IOHIDFamily `IOHIDEventDriver.cpp` |
| 소비자 제어 0x0C/0x029D | 조합키는 동작. 단독 누름은 서드파티 키보드에서 동작한 적 없다는 보고 | 미확인 | 🌐 → 입력 소스 변경 | IOHIDFamily(`SupportsGlobeKey`), ZMK PR 1938, Chrysalis 1310 |
| ⌃스페이스 | 기본 단축키(이전 입력 소스). 바뀌어 있을 수 있음 | 해당 없음 | 단축키 유지 | Apple 지원 문서 |
| LANG1 0x90 | 일본어 かな 키로 처리. 한/영 전환 근거 없음 | 스캔 코드 0xF2 → VK_HANGUL | Windows: 한국어 자판 | Apple 변환표, Microsoft 변환표 |
| 오른쪽 Alt 0xE6 | Option | 101키 종류 1 자판에서 한/영 전환 | 없음 | Microsoft 한국어 IME 문서 |

🌐 바이트가 호스트마다 다르게 동작하는 이유: macOS의 HID 드라이버는 기기에 `AppleVendorSupported` 속성이 있을 때만 이 바이트를 Fn으로 저장한다. 이 속성은 공개되지 않은 Apple 드라이버가 붙이며, 어떤 조건에서 붙는지는 확인하지 못했다. 앱이 보내는 디스크립터와 리포트는 0.1.0부터 바뀌지 않았다.

## 실기 결과 (iMac-D, macOS 15.7.4)

| 방식 | iMac 설정 | 반응 |
|---|---|---|
| Caps Lock 그대로 | 보조 키에서 MacBook 키보드의 Caps Lock → 🌐 fn | **한/영 전환** |
| Caps Lock 그대로 | 없음 | 대문자 고정 |
| 🌐 바이트 (Caps Lock으로) | 없음 | 없음 |
| 🌐 바이트 (MacBook의 🌐 키) | 없음 | 없음 |
| 표준 🌐 0x029D | 없음, 다시 페어링함 | 없음 |
| ⌃스페이스 | 없음 | Spotlight (단축키가 바뀌어 있음) |
| ⌘스페이스 | 없음 | 없음 |
| ⌃⌥스페이스 | 없음 | 다른 동작 |
| 한/영 키 LANG1 | 없음 | 없음 |

## 원인 확정 (2026-09-29, iMac-D에서 확인)

MacBook 쪽 전달은 정상이다. 입력 소스 키에 한해 세 지점을 기록해 확인했다.

| 키 | 앱이 받음 | 보낸 리포트 |
|---|---|---|
| Caps Lock | `HID monitor: Caps Lock down/up` (약 170ms) | `01: 00 00 39 00 00 00 00 00 00` |
| MacBook의 🌐 | `event tap: flags changed by key 63 (fn=true/false)` | `01: 00 00 00 00 00 00 00 00 01` |

MacBook의 한/영이 함께 바뀌는 것은 macOS가 Caps Lock을 이벤트 탭보다 아래에서 처리하기 때문이며, 전달에는 영향이 없다.

iMac이 가상 키보드를 등록한 모습:

| 항목 | 값 |
|---|---|
| 제조사 / 제품 | Apple의 제조사 번호와 그 MacBook의 제품 번호 (MacBook의 블루투스 장치 식별 정보. MacBook마다 다르고 앱이 정할 수 없다) |
| 장치 드라이버 | `IOBluetoothHIDDriver` (일반 블루투스 키보드용) |
| 이벤트 드라이버 | `AppleUserHIDEventDriver` |
| `AppleVendorSupported` | 없음. iMac의 USB 키보드(`AppleHIDKeyboardEventDriver`)에만 있음 |
| `SupportsGlobeKey` | 있음 (시험 중이던 디스크립터의 0x029D 때문. 그 뒤 디스크립터는 원래대로 되돌림) |

따라서:

1. Apple 방식 🌐 바이트는 드라이버가 버린다. Apple 키보드 드라이버는 Apple 제조사 번호와 특정 Apple 키보드의 제품 번호로만 붙는다.
2. 표준 🌐(0x029D)는 "🌐 키가 있는 키보드"로 등록되지만 단독 누름이 입력 소스를 바꾸지 않는다.
3. 보조 키의 "Caps Lock → 🌐 fn"은 키보드별로 저장된다. 처음 확인한 값은 iMac의 USB 키보드용이었고 가상 키보드에는 적용되지 않았다. 설정 화면 맨 위의 "키보드 선택" 단추로 가상 키보드를 고를 수 있다.

## 같은 설정을 터미널로 넣는 방법

설정 화면과 같은 일을 한다. 일반 사용자에게 권하지 않으며, 확인용으로 남긴다.

```bash
# MacBook 키보드의 제조사·제품 번호 확인 (연결된 상태에서). 첫 두 칸이 VendorID, ProductID다.
hidutil list | grep -i bluetooth

# 즉시 적용, 재부팅·재연결 때 사라짐 (동작 확인됨). <제조사>, <제품>은 위에서 본 값
hidutil property --matching '{"VendorID":<제조사>,"ProductID":<제품>}' \
  --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0xFF00000003}]}'

# 저장 (설정 화면이 쓰는 형식. 이 방법으로 저장한 뒤의 동작은 확인하지 않음). 번호는 십진수로 적는다
defaults -currentHost write -g com.apple.keyboard.modifiermapping.<제조사>-<제품>-0 -array \
  '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771129</integer><key>HIDKeyboardModifierMappingDst</key><integer>1095216660483</integer></dict>'
```

`0x700000039`는 Caps Lock, `0xFF00000003`은 🌐 fn이다. 이 변환은 드라이버 다음 단계(키보드 필터)에서 일어나므로 Apple 키보드 인식 여부와 무관하다.

iMac이 읽는 키보드 속성을 보는 명령:

```bash
ioreg -l -w0 | grep -E '\+-o |"(AppleVendorSupported|SupportsGlobeKey)" =' | grep -B1 -E '"(AppleVendorSupported|SupportsGlobeKey)" =' | cut -c1-90
for k in Product Transport HIDVirtualDevice HIDSubinterfaceID Built-In; do hidutil property --matching '{"PrimaryUsagePage":1,"PrimaryUsage":6}' --get "$k" | tail -n +2; done
```

## 남은 일

1. **Windows**: 조사로는 오른쪽 Alt(0xE6)가 한국어 IME 기본 설정에서 한/영을 바꾸고, LANG1(0x90)이 대안이다. 둘을 함께 보내면 두 번 전환된다. 실기 확인은 하지 않았다.
2. 이전 iMac(iMac-A~C)에서 🌐 바이트가 동작했는지는 확인하지 못했다. 디스크립터와 리포트는 0.1.0부터 같다.

## 출처

- IOHIDFamily: https://github.com/apple-oss-distributions/IOHIDFamily
- QMK Apple Fn: https://gist.github.com/fauxpark/010dcf5d6377c3a71ac98ce37414c6c4
- QMK 🌐 키: https://skip.house/blog/qmk-globe-key
- ZMK 키 코드 목록: https://zmk.dev/docs/keymaps/list-of-keycodes
- ZMK PR 1938: https://github.com/zmkfirmware/zmk/pull/1938
- ZMK 이슈 2701, 3217: https://github.com/zmkfirmware/zmk/issues/2701 , https://github.com/zmkfirmware/zmk/issues/3217
- Chrysalis 이슈 1310: https://github.com/keyboardio/Chrysalis/issues/1310
- Karabiner-Elements 토론 4095: https://github.com/pqrs-org/Karabiner-Elements/discussions/4095
- Apple 지원, 입력 소스 설정: https://support.apple.com/guide/mac-help/change-input-sources-settings-mchl84525d76/mac
- Microsoft 한국어 IME: https://learn.microsoft.com/en-us/globalization/input/korean-ime
- Microsoft 키보드 입력 개요: https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input
- Microsoft HID → 스캔 코드 변환표: https://download.microsoft.com/download/1/6/1/161ba512-40e2-4cc9-843a-923143f3456c/translate.pdf
