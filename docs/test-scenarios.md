# 연결 시험 절차

실기 시험을 사람이 하는 일과 프로그램이 하는 일로 나눠 적는다. 프로그램 쪽 결과는 로그로 확인한다.

## 준비

```bash
./scripts/build-app.sh && open build/BTSKey.app
/usr/bin/log stream --level info --predicate 'subsystem == "btskey"' --style compact
```

- 서명 인증서 `BTSKey Dev`가 로그인 키체인에 있으면 다시 빌드해도 권한이 유지된다(`docs/distribution.md`).
- 시작 로그의 `permissions granted: true`와 `paired: … new/returning/untried` 줄로 권한과 기기 분류를 확인한다.
- 시험 대상이 아닌 iMac에 연결되면 안 될 때는 시작 전에 저장된 대상을 지운다.

```bash
defaults write kr.newid.btskey wantsConnection -bool false
defaults delete kr.newid.btskey targetAddress; defaults delete kr.newid.btskey targetName
```

## 시험 항목

### A. 새 iMac 첫 연결

| 단계 | 사람 | 프로그램 | 확인할 로그 |
|---|---|---|---|
| A0 | 손쉬운 사용·입력 모니터링 허용 | 권한 확인, 대기 | `permissions granted: true` |
| A1 | MacBook의 Bluetooth 설정 화면을 연 채로, 새 iMac에서 MacBook 옆 "연결" → 양쪽 승인 | 5초 안에 감지, 새 기기로 분류 | `pairing added: … class unknown`, `adopting newly paired host … (new)` |
| A2 | HUD 확인 | 링크 → 1.5초 대기 → 채널 0x11 → 0x13 | `step +…: HID link up`, `control <- 71`, `control -> 00` |
| A3 | ⌥⌘K 후 iMac에서 타이핑·포인터 이동, ⌥⌘K로 복귀 | 입력 전달 | `main thread stalled` 없음 |

### B. iMac이 연결을 끊음

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| iMac의 Bluetooth 설정에서 MacBook "연결 해제", 30초 관찰 | 의도적 해제로 분류, 재시도 없이 대기 | `PSM 17 closed by host (link still up: true)`, `host closed the link on purpose` |

### C. 수동 재연결

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| 메뉴 → 지금 다시 연결 | 한 번 시도 | `attempt: … retriesUsed=0`, `HID link up` |

### D. 앱 재시작

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| 앱 종료 후 실행 | 첫 목록 확인 뒤 마지막 대상에 연결 | `attempt: … familiarity=returning`, `HID link up` |

### E. iMac 쪽에서 연결 시작

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| B 상태에서 15초 뒤 iMac의 Bluetooth 설정에서 MacBook "연결", 40초 관찰 | iMac이 올린 링크가 끊어질 때(약 19초 뒤) 감지, 1초 뒤 MacBook 쪽에서 한 번 연결 | `a link the host … brought up has dropped`, `host … in range; connecting in 1.0s`, `HID link up` |
| 같은 동작을 연결 실패 뒤 한 번 더 | 두 번째 신호는 무시 | `paged again; ignored until the user asks` |

### F. 링크가 끊김

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| iMac의 Bluetooth를 끄거나 iMac을 잠재움, 60초 관찰 | 4초 뒤 한 번 재시도 후 대기. 그 뒤 연결 요청 없음 | `retry #1 in 4.0s`, `automatic retry spent; waiting for the user` |
| iMac을 되돌린 뒤 메뉴 → 지금 다시 연결 | 연결 | `HID link up` |

### G. 앱이 꺼진 동안 페어링

| 사람 | 프로그램 | 확인할 로그 |
|---|---|---|
| 앱 종료 → 새 iMac 페어링 → 앱 실행 | 첫 목록에서 새 페어링 감지, 이전 대상은 호출하지 않음 | `pairing added`, `adopting newly paired host`, 이전 대상 주소로 `connecting to` 없음 |

### H. 입력 소스 전환

| 사람 | 프로그램 |
|---|---|
| iMac의 보조 키에서 MacBook 키보드를 골라 Caps Lock → 🌐 fn으로 설정. ⌥⌘K 후 Caps Lock을 짧게 누름 | Caps Lock을 그대로 전송. 로그 `HID monitor: Caps Lock down`, `radio: report 1 [00 00 39 …]` |

## 2026-09-29 결과 (0.1.4, 새 iMac인 iMac-D, macOS 15.7.4)

| 항목 | 결과 | 비고 |
|---|---|---|
| A0 | 통과 | |
| A1 | 통과 | 첫 시도는 MacBook이 검색 불가 상태여서 페어링 자체가 안 됨. Bluetooth 화면을 열어 두고 통과 |
| A2 | 통과 | 5.51초 (링크 3.54초) |
| A3 | 통과 | 키보드·포인터 정상, 멈춤 없음 |
| B | 통과 | 해제 뒤 80초간 연결 요청 0건 |
| C | 통과 | 4.67초 |
| D | 통과 | 3.91초, 2.02초, 3.02초, 2.90초 (4회) |
| E | 통과 | iMac의 시도부터 연결까지 24.5초. 그중 19초는 iMac이 올린 링크가 끊어지기를 기다린 시간 |
| F | 통과 | iMac의 Bluetooth를 끄자 의도적 해제로 분류, 60초간 요청 0건. 꺼진 상태에서 수동 연결은 15초 시간 초과 → 재시도 1회 → 멈춤. 다시 켠 뒤 iMac은 스스로 찾지 않았고 수동 연결 4.05초. 갑작스러운 끊김(거리)은 만들지 못함 |
| G | 통과 | 페어링 기록에서 새 iMac을 뺀 상태로 앱을 시작해 확인 |
| H | 통과 | iMac의 보조 키에서 MacBook 키보드를 골라 Caps Lock → 🌐 fn으로 설정한 뒤 통과. 설정 없이는 어떤 방식도 동작하지 않음 |

### H의 상세

앱은 Caps Lock을 그대로 보내고, iMac의 보조 키 설정에서 MacBook 키보드의 Caps Lock을 🌐 fn으로 바꾼다. 방식별 반응과 원인은 `docs/input-source-switching.md`.
