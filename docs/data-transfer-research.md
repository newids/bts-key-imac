# 파일·클립보드 전달 방법 조사 (2026-09-29)

블루투스로 연결된 상태에서 MacBook과 호스트(iMac, 나중에 Windows PC) 사이에 글자와 파일을 옮기는 방법을 조사했다. **문서 조사와 이 Mac의 SDK 확인까지만 했고, 실기 시험은 하지 않았다.** 각 항목에 근거의 종류를 적는다.

- **문서**: 제조사 문서, 규격, 프로젝트 저장소에서 직접 읽음
- **미확인**: 2차 자료 또는 추론. 시험이 필요함

## 1. 조건

| # | 조건 |
|---|---|
| 1 | 호스트에 아무것도 설치할 수 없다. 관리자가 매주 초기화한다 |
| 2 | 호스트에서 터미널 명령을 입력하게 할 수 없다. 시스템 설정 변경과 기본 앱·웹 브라우저 사용은 가능하다 |
| 3 | 호스트는 대개 사용자의 Apple 계정으로 로그인돼 있지 않다 |
| 4 | MacBook과 호스트는 이미 페어링돼 있고 키보드 연결(HID)이 올라와 있다 |

## 2. 결론

| 방향 | 내용 | 1순위 | 2순위 |
|---|---|---|---|
| MacBook → 호스트 | 글자 | **클립보드를 키 입력으로 보내기** (호스트 준비 없음) | AirDrop |
| MacBook → 호스트 | 파일 | AirDrop (허용돼 있고 Wi-Fi가 켜져 있을 때) | 블루투스 파일 전송(OBEX)으로 호스트의 Bluetooth 공유에 보내기 |
| 호스트 → MacBook | 글자 | 웹 페이지를 통한 통로(WebHID 또는 Web Serial). Chrome·Edge가 있어야 함 | 글자를 파일로 저장해 블루투스 파일 전송 |
| 호스트 → MacBook | 파일 | AirDrop | 호스트의 Bluetooth File Exchange로 MacBook에 보내기 |

1. **앱만 고쳐서 바로 만들 수 있는 것은 "클립보드를 키 입력으로 보내기" 하나다.** 호스트 쪽 준비가 없고, 같은 종류의 제품들이 모두 이 방법을 쓴다(8절).
2. **호스트에서 MacBook으로 글자를 보내는 길은 호스트에서 무언가 실행돼야만 열린다.** 키보드 규격에서 호스트가 스스로 보내는 것은 Caps Lock 등 표시등 상태뿐이다(6절). 설치 없이 실행할 수 있는 것은 웹 페이지다.
3. **파일은 블루투스로 보내면 느리다.** 보고된 속도는 초당 30~140KB이다(미확인). 1MB에 10초쯤, 100MB는 실용적이지 않다. 큰 파일은 AirDrop이나 블루투스가 아닌 방법이 맞다.
4. 호스트에 아무것도 설치하지 않고 키보드 연결로 파일을 옮기는 제품은 찾지 못했다.

## 3. 클립보드를 키 입력으로 보내기

MacBook의 클립보드 글자를 키 입력으로 바꿔 차례로 보낸다. 호스트는 사람이 빠르게 친 것으로 받는다.

| 항목 | 내용 | 근거 |
|---|---|---|
| 선례 | PiKVM(기본 1,024자 제한, 자판 배열표 사용), TinyPilot, Typeeto(1,024자), KeyPad | 문서 |
| 속도 | HID 규격이 권하는 포인터 전송률은 초당 80회. 누름·뗌이 한 쌍이므로 초당 40타쯤. 이 앱은 포인터를 8ms 간격(초당 125회)으로 이미 보낸다 | 규격은 문서, 호스트가 받아내는 한계는 미확인 |
| 자판 의존 | HID는 글자가 아니라 키 위치를 보낸다. 어떤 글자가 되는지는 호스트의 입력 소스가 정한다 | 문서 |
| 한글 | macOS의 기본 한글 입력 소스는 두벌식. 음절을 자모로 풀어 두벌식 키 순서로 보낸다. 음절당 2~5타 | 기본값은 문서, 방식은 미확인 |
| 그 밖의 글자 | macOS의 "Unicode Hex Input" 입력 소스는 호스트에 추가돼 있어야 한다. Windows의 Alt+숫자 16진 입력은 레지스트리 변경과 로그아웃이 필요해 조건 2에 어긋난다 | 미확인 |

이 앱에서 풀어야 하는 것:

- **호스트의 현재 입력 소스를 앱이 알 수 없다.** 영문 구간과 한글 구간 사이에 한/영 키를 보내야 하는데, 한/영 키는 "바꾸기"라서 시작 상태를 모르면 전체가 뒤집힌다. "영문 상태에서 시작"을 사용자와 약속하거나, 보내기 전에 확인을 받아야 한다. 한/영 전환은 호스트의 보조 키 설정에 달려 있다(`docs/input-source-switching.md`).
- **글자가 바뀌는 경우**: 편집기의 자동 완성·자동 들여쓰기·맞춤법 자동 수정, 한글 조합 중 상태, 보내는 도중 포커스 이동, 암호 입력 칸, 빠른 전송에서 빠지는 리포트.
- **길이 제한과 취소**: 선례는 1,024자 안팎으로 제한한다. 보내는 중에 멈출 수 있어야 한다.
- 글자를 키 순서로 바꾸는 부분은 순수 로직이라 `HIDCore`에 두고 단위 테스트로 검증할 수 있다.

## 4. 블루투스 파일 전송 (OBEX)

### 호스트에 이미 있는 것

| 항목 | 내용 | 근거 |
|---|---|---|
| Bluetooth File Exchange 앱 | macOS 15와 26의 사용 설명서에 있다. 파일 보내기, 기기 탐색, 받기. macOS 26.7.1에 앱과 `OBEXAgent`가 들어 있음을 이 Mac에서 확인 | 문서, 실물 확인 |
| Bluetooth 공유 | 시스템 설정 → 일반 → 공유. 받을 때의 동작(수락 후 저장 / 수락 후 열기 / 묻기 / 허용 안 함), 저장 폴더(기본 다운로드), 탐색 허용 폴더(기본 공용) | 문서 |
| 기본 상태 | Apple 문서는 "켠다"고만 적는다. 기본으로 꺼져 있다는 것은 2차 자료 | 미확인 |
| 관리 제한 | `allowBluetoothSharingModification`(macOS 14 이상), `allowBluetoothModification`, `allowAirDrop`. 설정 변경을 막는 항목이다 | 문서 |
| Windows | 설정 → Bluetooth 및 장치 → "Bluetooth를 통해 파일 보내기 또는 받기". 받는 쪽이 "파일 받기"를 먼저 열고 기다려야 한다 | 문서 |

호스트 사용자가 할 일: Bluetooth 공유를 한 번 켠다. 매주 초기화되면 다시 켜야 한다.

### MacBook 쪽 개발 API

| 항목 | 내용 | 근거 |
|---|---|---|
| `OBEXFileTransferServices`, `IOBluetoothOBEXSession`, `OBEXSession` | 폐기 표시 없음. 이 Mac의 SDK 27.0 헤더에는 iOS·watchOS·tvOS 사용 불가 표시만 있다 | 문서, SDK 확인 |
| `IOBluetoothRFCOMMChannel` | 동기식 `write:length:sleep:` 등 옛 메서드만 폐기 | 문서, SDK 확인 |
| 알려진 문제 | macOS 12 이후 RFCOMM 채널이 열리지 않는다는 개발자 포럼 보고 | 미확인 |

### 키보드 연결과 함께 쓰기

- HID 규격 1.1.1은 여러 프로파일이 한 링크를 함께 쓰는 경우를 전제로 적혀 있다(문서). 전송 중 입력 지연이 얼마나 늘어나는지는 자료를 찾지 못했다(미확인).
- **이 앱에서의 위험**(7차 감사까지의 실측에서 추론, 미확인):
  - 호스트가 여는 채널은 앱 프로세스에 전달되지 않았다. 호스트가 앱의 OBEX 서비스로 보내는 방식도 같은 이유로 실패할 수 있다. 호스트가 보내는 파일은 앱이 아니라 MacBook의 시스템 Bluetooth 공유가 받게 하는 편이 안전하다.
  - 앱 프로세스에서 페어링 목록을 한 번 읽는 것만으로 이후 채널 열기가 모두 실패했다. OBEX 호출이 같은 부작용을 내는지 확인하기 전에는 앱 프로세스에 넣지 않는다. 넣는다면 페어링 목록처럼 보조 프로세스로 분리하는 것을 먼저 검토한다.
  - 파일 전송이 끝난 뒤 링크를 닫는 동작이 키보드 채널까지 닫는지 확인이 필요하다.

## 5. 웹 페이지를 통한 통로

호스트에 Chrome이나 Edge가 있으면 웹 페이지가 블루투스 기기와 직접 데이터를 주고받을 수 있다. **Safari와 Firefox는 지원하지 않는다**(문서).

| 방식 | 동작 | 필요한 것 | 근거 |
|---|---|---|---|
| WebHID | 키보드·마우스 리포트는 웹 페이지가 쓸 수 없게 막혀 있지만, 막는 단위가 컬렉션이라 같은 기기의 제조사 정의 컬렉션은 열 수 있다 | 디스크립터에 제조사 정의 컬렉션 추가. 호스트가 디스크립터를 저장해 두므로 다시 페어링해야 한다 | 문서(Chromium 소스) |
| Web Serial | Chrome 117 이상 데스크톱. 페어링된 기기의 직렬 포트 서비스를 연다. macOS·Windows·Linux | MacBook이 RFCOMM 직렬 포트 서비스를 게시. 호스트가 여는 채널이므로 4절의 위험이 그대로 있다 | 문서 |
| Web Bluetooth | BLE GATT만. Chrome의 macOS·Windows 지원 | MacBook이 BLE 주변장치로 서비스 게시. 키보드 연결과 별개의 링크 | 문서. 이미 페어링된 Mac과의 동작은 미확인 |

제약:

- **페이지는 보안 컨텍스트여야 한다.** HTTPS, `localhost`, `file://`만 해당한다(문서). 호스트가 인터넷에 연결돼 있거나, 페이지 파일을 호스트에 옮겨 두어야 한다.
- **관리되는 Chrome은 정책으로 막혀 있을 수 있다.** `DefaultWebHidGuardSetting`, `DefaultSerialGuardSetting`, `DefaultWebBluetoothGuardSetting`. 값 2는 차단, 설정이 없으면 묻는다(문서).
- macOS가 브라우저에 입력 모니터링 권한을 요구하는지는 2차 자료뿐이다(미확인).
- 사용자가 페이지에서 기기를 고르는 단계가 매번 있다.

## 6. 호스트가 스스로 보내는 것

키보드 규격에서 호스트가 프로그램 없이 기기에 보내는 것은 표시등 출력 리포트(Num Lock, Caps Lock, Scroll Lock, Compose, Kana 비트)와 프로토콜 요청뿐이다. 기능 리포트 쓰기는 규격이 "응용 프로그램용"으로 적고 있다(문서). 따라서 호스트에서 프로그램(웹 페이지 포함)이 돌지 않으면 사용자 데이터를 실을 통로가 없다.

## 7. Apple의 공유 기능

| 기능 | 필요한 것 | 조건 3에서 | 근거 |
|---|---|---|---|
| AirDrop | 양쪽 Wi-Fi와 Bluetooth 켬, 10m 이내. 인터넷은 필요 없음. 연락처에 없는 상대는 받는 쪽이 만든 AirDrop 코드 사용 | Apple 계정에 로그인하지 않은 호스트에서 되는지 Apple 문서에 없다. 시험 필요 | 문서, 일부 미확인 |
| 공통 클립보드·Handoff | 같은 Apple 계정 | 쓸 수 없음 | 문서 |
| Universal Control | 같은 Apple 계정, 이중 인증 | 쓸 수 없음 | 문서 |

## 8. 같은 종류의 제품

| 제품 | 호스트 설치 | 글자·파일 전달 방식 |
|---|---|---|
| across | 키보드·마우스는 없음. 클립보드(블루투스, 글자 1,023바이트까지)와 파일(네트워크)은 호스트에 클라이언트 설치 | 블루투스 HID + 네트워크 |
| KeyPad, Typeeto, 1Keyboard | 없음 | 글자를 키 입력으로 |
| Logitech Flow | 양쪽 설치, 같은 네트워크 | 네트워크 |
| Input Leap, Barrier, Synergy | 모든 기기에 설치 | 네트워크 |
| Mouse Without Borders | 양쪽 PowerToys, 같은 네트워크, 파일 100MB까지 | 네트워크 |

## 9. 블루투스가 아닌 방법 (비교용, 미확인)

| 방법 | 장점 | 한계 |
|---|---|---|
| USB 저장 장치 | 빠름 | 관리되는 호스트에서 막혀 있는 경우가 많음 |
| 클라우드·웹 업로드 | 크기 제한 적음 | 인터넷과 공용 기기에서의 로그인 필요 |
| MacBook의 로컬 웹 서버 | 빠름, 호스트는 브라우저만 | 같은 네트워크 필요, 공용 Wi-Fi의 기기 간 차단 |
| QR 코드 | 설치 없음 | 짧은 글자만, 카메라 필요 |

## 10. 확인에 필요한 시험

코드를 쓰기 전에 아래 순서로 시험한다. 1, 2, 5는 코드 없이 할 수 있다.

| # | 사람 | 프로그램·기록 | 답하는 질문 |
|---|---|---|---|
| 1 | 호스트에서 Bluetooth 공유를 켠다. 앱이 연결된 상태에서 MacBook의 Bluetooth File Exchange로 1MB 파일을 보낸다 | 전송 속도, 전송 중 포인터 지연, 전송 뒤 키보드 연결 유지 여부 | 파일 전송과 키보드 연결이 함께 되는가 |
| 2 | MacBook에서 Bluetooth 공유를 켠다. 호스트의 Bluetooth File Exchange로 MacBook에 파일을 보낸다 | 같은 항목 | 호스트가 시작한 전송이 시스템 공유로 들어오는가 |
| 3 | 호스트에서 텍스트 편집기를 연다 | 영문 1,000자와 한글 200음절을 초당 20·40·80 리포트로 보내고 틀린 글자 수를 센다 | 안전한 입력 속도 |
| 4 | 호스트에서 페어링을 지우고 다시 페어링한 뒤 Chrome으로 시험 페이지를 연다 | 제조사 정의 컬렉션을 추가한 시험 빌드. 기기 선택 목록, 권한 요청, 데이터 도착 여부 | WebHID가 블루투스 키보드에서 되는가 |
| 5 | Apple 계정에 로그인하지 않은 호스트와 "모든 사람" 모드로 AirDrop을 주고받는다 | 없음 | AirDrop이 조건 3에서 되는가 |

## 11. 권고 순서

1. **클립보드를 키 입력으로 보내기**: 영문·숫자·기호부터. 시험 3으로 속도를 정한 뒤 한글 두벌식을 더한다.
2. **안내 문서**: 파일은 AirDrop 또는 Bluetooth File Exchange를 쓰는 방법을 사용 안내에 적는다. 시험 1, 2, 5의 결과에 따른다. 앱 코드는 필요 없다.
3. **앱에서 파일 보내기(OBEX)**: 시험 1이 통과하고 보조 프로세스 방식이 키보드 연결을 해치지 않을 때만.
4. **웹 페이지 통로**: 호스트에서 MacBook으로 글자를 보내는 유일한 방법이지만, 호스트의 브라우저 종류와 정책에 달려 있고 다시 페어링해야 한다. 시험 4 뒤에 결정한다.

## 출처

Apple

- Bluetooth File Exchange: https://support.apple.com/guide/mac-help/mchle7fa9e15/mac
- Bluetooth 공유 설정: https://support.apple.com/guide/mac-help/mchlp1673/mac
- Mac 제한 항목: https://support.apple.com/guide/deployment/restrictions-for-mac-depba790e53/web
- 관리 프로파일 정의: https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.applicationaccess.yaml
- IOBluetooth OBEX·RFCOMM: https://developer.apple.com/documentation/iobluetooth/obexfiletransferservices , https://developer.apple.com/documentation/iobluetooth/iobluetoothobexsession , https://developer.apple.com/documentation/iobluetooth/iobluetoothrfcommchannel
- AirDrop: https://support.apple.com/guide/mac-help/mh35868/mac , https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web
- 공통 클립보드: https://support.apple.com/en-us/102430
- Universal Control: https://support.apple.com/en-us/102459
- 한국어 입력기: https://support.apple.com/guide/korean-input-method/welcome/mac
- CoreBluetooth 주변장치: https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager

규격

- Bluetooth HID Profile 1.1.1: https://www.bluetooth.com/specifications/specs/human-interface-device-profile-1-1-1/
- USB HID 1.11: https://www.usb.org/sites/default/files/hid1_11.pdf

브라우저

- WebHID: https://developer.chrome.com/docs/capabilities/hid , https://github.com/WICG/webhid/blob/main/EXPLAINER.md
- WebHID 차단 목록: https://github.com/chromium/chromium/blob/main/services/device/public/cpp/hid/hid_blocklist.cc , https://github.com/chromium/chromium/blob/main/services/device/public/cpp/hid/hid_report_utils.cc
- Web Serial 블루투스: https://developer.chrome.com/blog/serial-over-bluetooth , https://developer.chrome.com/blog/bluetooth-rfcomm-updates-web-serial , https://github.com/whatwg/serial/blob/main/EXPLAINER_BLUETOOTH.md
- Web Bluetooth: https://developer.chrome.com/docs/capabilities/bluetooth , https://github.com/WebBluetoothCG/web-bluetooth/blob/main/implementation-status.md
- 보안 컨텍스트: https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts
- Chrome 정책: https://chromeenterprise.google/policies/default-web-hid-guard-setting/

Microsoft

- 블루투스 파일 전송: https://support.microsoft.com/en-us/windows/send-and-receive-files-over-bluetooth-in-windows-36f8cf26-d1ff-50d1-4b73-3a56e5b43e6a
- 근거리 공유: https://support.microsoft.com/en-us/windows/share-things-with-nearby-devices-in-windows-0efbfe40-e3e2-581b-13f4-1a0e9936c2d9
- 클립보드: https://support.microsoft.com/en-us/windows/apps/using-the-clipboard
- Mouse Without Borders: https://learn.microsoft.com/en-us/windows/powertoys/mouse-without-borders

선례

- PiKVM: https://github.com/pikvm/kvmd/blob/master/kvmd/keyboard/printer.py , https://github.com/pikvm/pikvm/issues/1293
- TinyPilot: https://tinypilotkvm.com/blogs/news/tinypilot-h264-latency-update-long-text-paste
- Typeeto: https://mac.eltima.com/bluetooth-keyboard.html
- KeyPad: https://bluetooth-keyboard.com/clipboard-paste-from-mac-to-the-iphone-and-ipad/
- across: https://www.acrosscenter.com/
- Logitech Flow: https://support.logi.com/hc/en-us/articles/1500005634742
- Input Leap: https://github.com/input-leap/input-leap
