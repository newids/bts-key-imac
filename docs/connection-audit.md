# 블루투스 연결 과정 감사 (2026-09-23)

MacBook의 `bluetoothd` 통합 로그, 앱 로그, 스파이크 프로그램 실측으로 연결 과정을 추적했다. 셸에서는 zsh 내장 `log`와 충돌하므로 `/usr/bin/log`를 쓴다.

## 관측된 사실

| # | 관측 | 근거 |
|---|---|---|
| 1 | SDP 레코드를 `remove()` 후 다시 게시하면 bluetoothd가 PSM 0x11/0x13 등록을 풀지 않아 게시가 실패한다. | 18:05:20 등 "Failed to register L2CAP Channel with PSM 0x0013 as it is already registered", 앱 로그 "Could not publish the HID service record" 반복 |
| 2 | 실패 시 3초 고정 재시도가 매번 ACL 페이징을 일으켰고, iMac이 15초 뒤 유휴로 ACL을 끊는 순환이 생겼다. | 18:05~18:09에 `CBMsgIdConnectPeer` 16회, "ACL disconnected … reason 10722/10719" 반복 |
| 3 | iMac은 결합된 키보드에 **스스로** HID 채널(PSM 17→19)을 연다. SDP를 게시한 세션이 있으면 bluetoothd가 그 세션으로 넘긴다(`setThirdPartyConnectInd`). | KeyPad 16:14:08 "incoming 1", "RecvConnectReq psm=17/19", "Accepting connection for PSM:0x0011" |
| 4 | 게시한 세션이 없으면 MacBook 자체 HID 호스트가 그 연결을 가로채 iMac을 입력 장치로 등록한다. | 17:51~17:54 4회 "Creating GenericInputDevice for device AA:AA:AA:AA:AA:01", "Delaying handshake … SDP is missing" |
| 5 | MacBook→iMac 아웃바운드 HID 채널은 메인 스레드 비동기 API로 정상 동작한다. 제어 채널로 SET_PROTOCOL(0x71)과 Apple SET_REPORT(0x53…)가 온다. | 스파이크: ACL 후 0.3~0.6초에 두 채널 개방, 30초 유지 |
| 6 | 백그라운드 스레드에서 IOBluetooth 객체를 쓰면 채널 열기가 즉시 `kIOReturnError`(-536870212)로 실패한다. | 스파이크 thread 모드 |
| 7 | 18:05의 앱 실패(`-536870212`)는 17:55 시스템 설정의 페어링 삭제(`DeleteDevice`)와 재페어링 직후에만 발생했고, bluetoothd 재시작 후에는 같은 코드가 정상 동작했다. 재현되지 않았다. | 헤드리스 하니스로 ACL 유무 두 조건 모두 성공 |

## 반영한 수정

- **SDP 게시는 앱 수명 동안 1회**: 앱 시작 시 게시하고 종료 때만 제거한다. 연결 해제·실패 시에는 채널만 닫는다(관측 1).
- **인바운드 수락**: 시작 시 PSM 0x11/0x13 수신 알림을 등록하고, 선택한 iMac의 연결만 받는다. 사용자가 "연결 해제"한 동안에는 거절한다(관측 3, 4).
- **지수 백오프**: 2→4→8→16→30초 상한. 연결 성공 시와 Mac 잠자기 복귀 시 초기화 후 즉시 재시도한다(관측 2).
- **워치독**: 15초 안에 두 채널이 모두 열리지 않으면 실패로 처리해 "연결 중…"에 갇히지 않는다.
- **재시도 불가 오류 구분**: 대상 미선택, 페어링 안 됨, SDP 게시 실패, iMac의 가상 케이블 해제는 재시도하지 않고 바로 안내한다.
- **의도 기억**: 마지막에 "연결"을 선택했으면 앱을 다시 켤 때 자동으로 연결한다.
- **메뉴 표시**: 끊긴 상태에서 다음 재시도까지 남은 초를 보여 준다.

## 검증

- 단위 테스트: 백오프, 인바운드 판정, 상태 전이(유휴 상태에서 iMac이 먼저 연결) 추가.
- 헤드리스 하니스(앱의 실제 전송 코드): 첫 연결 2.3초, 끊은 뒤 재연결 0.1초, 재게시 오류 0건, 페어링 안 된 대상은 즉시 비재시도 오류.
- **미검증**: iMac이 먼저 여는 인바운드 연결을 우리 앱이 수락하는 경로. iMac이 연결을 시작하는 조건(잠자기 복귀, iMac 블루투스 설정에서 장치 클릭)을 이쪽에서 만들 수 없었다. 같은 bluetoothd 라우팅으로 KeyPad가 성공한 경로다.

## 진단 명령

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "btskey"' --style compact
/usr/bin/log show --last 10m --predicate 'process == "bluetoothd" AND (eventMessage CONTAINS "psm=17" OR eventMessage CONTAINS "Failed to register" OR eventMessage CONTAINS "GenericInputDevice")' --style compact
```

## 2차 감사 (2026-09-26): "연결됨 → 끊김" 반복

증상: 양쪽 블루투스 설정에 서로 보이지만, 연결을 누르면 스피너만 돌거나 "연결됨" 직후 끊기기를 반복했다.

| # | 관측 | 근거 |
|---|---|---|
| 1 | 사용자가 자리를 옮겨 iMac이 iMac-A(AA:AA:AA:AA:AA:01)에서 iMac-B(BB:BB:BB:BB:BB:02)로 바뀌었다. 앱에는 이전 iMac이 대상으로 저장돼 있었다. | 앱 설정 `targetAddress`, `system_profiler` |
| 2 | 13:46 iMac-B이 새로 페어링한 직후 PSM 17/19를 열었고, 앱이 "대상이 아님"으로 즉시 닫았다. | `CBClassicMsgIdCloseL2CAPChannel` from `kr.newid.btskey` |
| 3 | 앱에서 "연결"을 누른 적이 없으면 인바운드를 거절하도록 되어 있어, iMac 설정에서 연결하는 사용 방식과 맞지 않았다. | `acceptsIncoming = wantsConnection`(기본 false) |
| 4 | 이후 3회 시도에서 iMac이 SET_PROTOCOL(1바이트)을 보냈으나 응답이 없어 약 3초 뒤 iMac이 끊었다(reason 0x1af). | 13:47:55, 13:48:44, 13:49:25 `l2capDataInd len 0x1` → `l2capDisconnected reson 0x1af` |
| 5 | MacBook 설정에서 iMac을 "연결"하면 스피너만 돈다. iMac은 MacBook에 제공할 프로필이 없는 "데스크톱 컴퓨터"라 정상이다. 연결은 iMac 쪽에서 하거나 앱 메뉴에서 한다. | — |

수정:
- 페어링된 호스트가 걸어오는 연결은 기본으로 받는다. 암호화된 HID 채널은 결합된 호스트만 열 수 있다. 앱에서 "연결 해제"를 누른 동안(`isPaused`)만 거절한다.
- 연결된 호스트가 저장된 대상과 다르면 그 호스트를 새 대상으로 기억한다. 자리를 옮겨도 iMac에서 "연결"만 누르면 된다.
- 권한(손쉬운 사용, 입력 모니터링)이 없어도 링크는 유지한다. 원격 전환만 막고 권한을 안내한다. 링크를 끊으면 iMac에서 같은 반복이 보인다.
- 연결 수명주기 로그를 notice 레벨로 올려 `log show`로 사후 확인이 가능하게 했다. info 레벨은 저장되지 않는다.
- 검증: 헤드리스 하니스로 iMac-B 아웃바운드 연결 1.7초. iMac에서 누르는 인바운드 연결은 사용자 확인이 필요하다.

## 3차 감사 (2026-09-26 오후): "연결 중 ↔ 연결 끊김" 반복

| # | 관측 | 근거 |
|---|---|---|
| 1 | iMac이 연 HID 채널을 bluetoothd는 14:32:29.0에 수락하고 29.1에 iMac의 SET_PROTOCOL을 앱으로 넘겼지만, 앱은 34.4에야 채널을 인지했다. iMac은 32.0에 3초 타임아웃으로 끊었다. 같은 패턴이 14:33:08, 14:34:03, 14:34:41에 반복됐다. | bluetoothd `l2capDataInd`/`l2capDisconnected reson 0x1af`, 앱 notice 로그 |
| 2 | `sample`로 본 앱 메인 스레드가 IOBluetooth 내부 `-[IOBluetoothL2CAPChannel connectionComplete:status:]` → `openL2CAPChannelSync` → `waitforChanneOpen`에서 8초 내내 멈춰 있었다. ACL이 끊긴 상태에서 요청된 채널 열기를 IOBluetooth가 ACL 재연결 후 **메인 스레드에서 동기로** 기다린다. iMac이 응답하지 않으면 무기한 멈춘다. | `sample BTSKey 8` |
| 3 | 메인이 멈춘 탓에 이벤트 탭이 시스템에 의해 비활성화됐다(MacBook 입력 지연). | 앱 로그 "event tap was disabled" 반복 |
| 4 | ACL만 연결해서는 iMac이 HID 채널을 열지 않았다. 앱 로그의 인바운드 시점은 사용자가 iMac에서 "연결"을 누른 것과 앱의 아웃바운드 재시도가 겹친 시점이다. | ACL-only 스파이크: 25초간 인바운드 없음 |
| 5 | 빌드할 때마다 블루투스 권한 창이 다시 뜨고, 응답 전까지 IOBluetooth 호출이 멈춘다. | tccd `AUTHREQ_PROMPTING service=kTCCServiceBluetoothAlways` |

수정:
- 채널 열기 직전에 ACL이 살아 있는지 확인하고, 끊겼으면 즉시 재시도 가능한 실패로 처리한다. 동기 대기 경로에 들어가지 않는다.
- 연결 시점에 ACL이 이미 있으면 iMac이 채널을 여는 중일 수 있으므로 1.5초 기다린 뒤에만 우리 채널을 연다.
- ACL 끊김 알림을 등록해 워치독(15초)을 기다리지 않고 즉시 실패로 처리한다.
- 재연결 첫 간격을 4초로 늘려 iMac 쪽 재연결과 충돌을 줄인다.

검증: 연결 직후 0.3·1.0·1.6·2.2초에 ACL을 강제로 끊는 5회 반복 시험에서 모든 끊김을 즉시 감지했고, 메인 스레드 최대 정지는 0.12초였다(수정 전 샘플에서는 8초 이상).

## 4차 감사 (2026-09-26 저녁): 양쪽 설정은 "연결됨", 앱은 끊김·재시도 반복

| # | 관측 | 근거 |
|---|---|---|
| 1 | iMac이 먼저 연 링크에서 iMac의 SET_PROTOCOL(1바이트)이 bluetoothd까지 도착했으나(`l2capDataInd len 0x1`) 앱 세션의 응답 쓰기가 한 번도 없었고, 3초 뒤 iMac이 끊었다(0x1af). 14:32·14:33·14:34·16:41·16:42 모두 같은 패턴. | bluetoothd, 앱 세션 XPC 메시지에 쓰기 없음 |
| 2 | 앱은 제어 채널을 객체 동일성(`===`)으로 식별했다. 아웃바운드(앱이 연 채널)는 동작했지만 인바운드(알림으로 받은 채널)에서는 델리게이트 콜백의 채널 객체가 달라 요청이 버려졌다. 같은 이유로 `l2capChannelOpenComplete`가 두 번 처리되어 "HID link up"이 두 번 기록됐다. | 앱 로그, 코드 |
| 3 | 앱 쪽 연결 시도가 4ms 만에 "링크 끊김"으로 실패했다. bluetoothd에는 요청조차 도착하지 않았다. 연결 완료 콜백 시점에 `IOBluetoothDevice.isConnected()`가 링크가 살아 있는데도 false를 돌려줘, 3차 감사에서 넣은 "ACL 없으면 열지 않기" 안전장치가 오작동했다. | 앱 로그 16:39:37~16:45, bluetoothd에 ConnectPeer 없음 |
| 4 | 빌드 직후 블루투스 권한 창에 응답한 순간 SDP 게시가 실패했고(15:58, 16:19), 앱은 재시도 없이 레코드 없이 운영됐다. 이때 iMac이 연결하면 MacBook 자체 HID 호스트가 받아 양쪽 설정 화면에는 "연결됨"으로 보이지만 앱은 링크가 없다. 이후 bluetoothd는 "incoming HID connection already exists"로 앱 쪽 HID 연결을 건너뛴다. | 앱 로그 "SDP publish failed", bluetoothd |

수정:
- 채널 식별을 객체 동일성 대신 **PSM(0x11/0x13)과 호스트 주소**로 한다(`HIDChannelRole`). 제어 채널 요청·응답을 notice 로그로 남긴다.
- 연결 완료 콜백은 링크가 살아 있다는 증거이므로 그 경로에서는 `isConnected()`를 믿지 않는다. 안전장치는 유예 경로에만 남긴다.
- SDP 게시 실패 시 1초 간격으로 최대 30회 재시도한다. 게시 전에는 아웃바운드를 "등록 대기" 재시도 가능 오류로 처리한다.
- 연결 알림은 링크당 한 번만 보낸다.
- **재연결 시 iMac 입력 자동 복귀**(메뉴, 기본 켬): iMac 입력 중 링크가 끊겼다가 30분 안에 다시 붙으면 자동으로 iMac 입력으로 돌아간다. iMac이 잠자기에서 깨어 로그인 화면에서 암호를 받는 경우를 위한 것이다.

미검증: iMac이 먼저 여는 링크에서의 응답은 사용자 실기 확인이 필요하다. 이제 로그에 `control <-`/`control ->`가 남으므로 사후 확인이 가능하다.

### 4차 감사 후속: 낡은 ACL 위의 채널 (2026-09-26 17:10)

- 관측: ACL이 이미 있을 때 앱이 연 PSM 0x11 채널이 연결 9ms 뒤 앱 프로세스 쪽에서 닫혔다(`CBClassicMsgIdCloseL2CAPChannel`). 앱 코드의 닫기 경로는 호출되지 않았다(모든 close 지점 계측으로 확인). IOBluetooth 내부 동작이다. 이때 bluetoothd는 "incoming HID connection already exists"로, MacBook 자체 HID 호스트가 그 링크를 잡고 있었다. 양쪽 설정 화면의 "연결됨"은 이 링크다.
- 실측: 같은 상태에서 ACL을 먼저 끊고 새로 연결하면 1.4초 만에 연결되고 iMac의 SET_PROTOCOL·SET_REPORT에 응답하며 유지된다.
- 수정: ACL이 이미 있고 1.5초 안에 iMac이 채널을 열지 않으면 ACL을 끊고(`closeConnection`) 새로 연결한다. 재연결 간격 상한을 10초로 낮춰 잠자기에서 깬 iMac을 빨리 다시 잡는다.
- 검증(하니스): 낡은 ACL → 초기화 → 연결 2.2초. 연결 중 ACL 강제 끊김 → 즉시 감지 → 재연결 1.0초. 두 경우 모두 iMac 초기 요청에 응답.

## 5차 감사 (2026-09-27): 메뉴 무반응, 시스템 입력 정지

| # | 관측 | 근거 |
|---|---|---|
| 1 | 앱의 연결 시도 중 IOBluetooth 채널 열기가 메인 스레드를 9초 막았고, 곧이어 macOS가 이벤트 탭을 비활성화했다("event tap was disabled"). | 앱 로그 15:12:13→15:12:22, 15:12:34 |
| 2 | 이벤트 탭이 메인 런루프에 있어서 메인이 멈추면 탭도 멈추고, macOS는 탭이 응답할 때까지 **시스템 전체** 키·마우스 이벤트를 붙잡는다. 메뉴가 늦게 뜨거나 깜빡이고 다른 앱 입력이 밀린 이유다. | 증상, 탭 설계 |
| 3 | 4차 수정에서 연결 완료 콜백을 믿고 `isConnected()`를 건너뛰었는데, 그 상태에서 채널을 열면 IOBluetooth가 내부적으로 동기 대기에 들어간다(3차 감사의 정지 경로와 같음). | 샘플·로그 |
| 4 | 재시도가 무한히 이어져 정지가 반복됐다. | 앱 로그 재시도 루프 |

수정:
- **이벤트 탭과 Caps Lock 모니터를 전용 스레드(`InputThread`, userInteractive)의 런루프로 옮겼다.** 블루투스 쪽이 몇 초 멈춰도 MacBook 입력은 영향받지 않는다.
- 연결 완료 후 `isConnected()`가 true가 될 때까지 100ms 간격으로 최대 3초 기다린 뒤에만 채널을 연다. 끝내 false면 멈추는 호출 없이 재시도 가능 실패로 처리한다.
- 자동 재시도는 5회까지. 그 뒤에는 iMac이 걸어오는 연결과 사용자 조작만 기다린다(상태줄 안내). 사용자 연결·잠자기 복귀·호스트 연결 성공 시 초기화.

검증(하니스, 메인 정지 감시 50ms): 낡은 링크 → 연결, 링크 강제 끊김 후 즉시 재연결 3회. 전송 코드에 의한 메인 정지 0회(측정된 2.15초는 하니스가 준비용으로 부른 동기 `openConnection()`이며 앱은 비동기 버전만 쓴다).
