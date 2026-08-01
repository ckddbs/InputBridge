# InputBridge

<p align="center">
  <img src="Assets/AppIcon-master.png" width="180" alt="InputBridge keycap icon">
</p>

InputBridge는 macOS Screen Sharing 사용 중 두 Mac의 한/영 입력 소스가 어긋나는
문제를 완화하는 메뉴 막대 앱입니다.

Screen Sharing 대상 Mac에서 입력 소스가 바뀌면 별도의 TCP 연결을 통해 조작 Mac에
상태를 전달하고, 조작 Mac의 입력 소스를 같은 상태로 맞춥니다. 입력한 글자나 키 입력은
수집하거나 전송하지 않습니다.

> [!IMPORTANT]
> 현재 버전은 기능 검증을 위한 PoC입니다. 통신 메시지는 공유 키로 인증되지만
> 암호화되지 않으므로 신뢰할 수 있는 LAN 또는 Tailscale 안에서만 사용하세요.

## 동작 구조

```text
조작 Mac ── TCP 45831 연결 시작 ──▶ Screen Sharing 대상 Mac
조작 Mac ◀── 같은 연결로 입력 소스 전송 ── 대상 Mac
```

`자동` 모드는 Screen Sharing과 같은 방향으로 연결하므로 NAT나 비대칭 라우팅의
영향을 줄입니다. 이 방향이 불가능하면 대상 Mac이 기존 방향으로 연결을 시도합니다.

앱은 양쪽 Mac에 모두 설치합니다.

| Mac | InputBridge 역할 | 설정 |
| --- | --- | --- |
| 키보드를 사용하는 Mac | `조작 Mac` | 대상 Mac 주소, 포트와 공유 키 입력 |
| Screen Sharing 대상 Mac | `대상 Mac` | 같은 포트와 공유 키를 입력하고 연결 대기 |

## 요구 사항

- macOS 13 Ventura 이상
- Apple Silicon 또는 Intel Mac
- 양쪽 Mac에 `ABC`와 `한국어 - 두벌식` 입력 소스 등록
- 조작 Mac에서 대상 Mac의 InputBridge TCP 포트로 접근할 수 있는 LAN 또는 VPN

## 설치 및 업데이트

양쪽 Mac에서 기존 InputBridge를 완전히 종료한 뒤 새 앱으로 교체합니다. 실행 중인
앱 파일만 덮어쓰면 이전 프로세스는 메모리에 남아 있으므로 먼저 다음을 실행하는 것이
안전합니다.

```sh
killall InputBridge 2>/dev/null || true
```

압축을 풀고 `InputBridge.app`을 `/Applications`로 옮깁니다. 인터넷에서 받은 앱으로
인식되어 실행이 차단되면 앱을 한 번 열어 본 다음 `시스템 설정 → 개인정보 보호 및
보안 → 보안 → 그래도 열기`를 선택합니다.

새 ad-hoc 서명 빌드로 교체한 뒤 인바운드 연결이 시간 초과되면
`시스템 설정 → 네트워크 → 방화벽 → 옵션`에서 InputBridge의 들어오는 연결을
허용했는지 다시 확인합니다.

## 사용 방법

1. 대상 Mac에서 `대상 Mac`, `자동 (권장)`을 선택하고 포트와 공유 키를 입력해
   시작합니다.
2. 키보드를 사용하는 Mac에서 `조작 Mac`, `자동 (권장)`을 선택합니다.
3. `Screen Sharing 대상 찾기`를 눌러 주소를 적용합니다.
4. 대상 Mac이 이미 실행 중이면 `포트 찾기`로 열린 InputBridge 포트를 자동
   적용하거나, 대상 Mac과 같은 포트를 직접 입력합니다.
5. 같은 공유 키를 입력하고 시작합니다.
6. Screen Sharing 창에서 한/영을 변경합니다.

조작 Mac의 `Screen Sharing 대상 찾기`는 나가는 Screen Sharing 연결의 원격 주소를
검색합니다. 발견된 주소를 확인한 뒤 `적용`을 누르면 대상 Mac 주소에 입력됩니다.
감지할 수 없거나 여러 대상에 접속한 경우에는 주소를 직접 입력합니다.

`포트 찾기`는 대상 Mac이 먼저 실행된 상태에서 `45831...45840`, `48000`,
`50000`, `55000`을 병렬 검사합니다. 대상 Mac은 설정된 포트 하나만 열며,
조작 Mac은 열린 후보가 정확히 하나일 때만 해당 포트를 자동 적용합니다.

주소 검색은 조작 Mac의 TCP 연결 테이블에서 원격 포트가 5900인 직접 연결을
확인합니다. `자동` 모드의 기존 방식 fallback은 대상 Mac에서 로컬 포트가 5900인
접속자도 확인합니다. InputBridge는 일반 사용자의 `lsof`에 보이지 않는
`screensharingd` 연결을 찾기 위해 `netstat`의 TCP 테이블을 사용합니다.

## 연결 방식

| 모드 | 연결 시작 | 주소 입력 | 용도 |
| --- | --- | --- | --- |
| `자동 (권장)` | 조작 Mac → 대상 Mac 우선 | 조작 Mac에 대상 주소 | Screen Sharing과 같은 방향을 사용하고 실패 시 기존 방향 시도 |
| `기존 방식` | 대상 Mac → 조작 Mac | 대상 Mac에 조작 주소 | 이전 버전의 연결 방향을 명시적으로 사용 |

자동 모드에서도 대상 Mac은 설정한 포트 하나만 엽니다. 조작 Mac의 `포트 찾기`가
후보 포트에 짧은 TCP 연결을 병렬로 시도하며, 검색 연결은 결과 확인 직후 모두
종료됩니다.

같은 LAN에서는 IP 대신 Bonjour 호스트 이름을 사용할 수 있습니다.

```sh
scutil --get LocalHostName
```

결과가 `Target-Mac`이면 조작 Mac의 대상 주소 입력란에
`Target-Mac.local`을 입력합니다.

정상 동작 시 상태가 다음 순서로 표시됩니다.

```text
대상 Mac: 감지 및 전송 → 전송 완료
조작 Mac: 적용: com.apple…
```

## 소스에서 실행

```sh
swift run
```

테스트:

```sh
swift test
```

## unsigned 앱 만들기

Developer ID 없이 Apple Silicon과 Intel을 지원하는 `.app.zip`을 만듭니다.
Apple Silicon 실행에 필요한 ad-hoc 서명만 적용되며, 받는 Mac에서는 최초 실행 시
시스템 설정의 개인정보 보호 및 보안에서 `그래도 열기`를 선택해야 합니다.
경고를 닫은 뒤 해당 설정 화면에서 InputBridge의 `확인 없이 열기`를 선택하거나,
직접 받은 빌드를 신뢰하는 경우 다음 명령으로 격리 속성을 제거할 수 있습니다.

```sh
xattr -dr com.apple.quarantine /Applications/InputBridge.app
open /Applications/InputBridge.app
```

패키지 생성:

```sh
./Scripts/package-unsigned.sh 0.1.7
```

결과:

```text
dist/InputBridge-0.1.7-unsigned-universal.zip
```

## 현재 구현

- macOS 입력 소스 변경 알림 및 0.2초 폴링
- ABC와 기본 한글 두벌식의 portable ID 매핑
- Network.framework TCP 송수신
- 나가거나 들어오는 직접 Screen Sharing 상대 주소 자동 감지
- 조작 Mac에서 시작하는 연결과 기존 방향 자동 fallback
- 실행 중인 대상 InputBridge 포트 자동 검색
- 연결 실패 시 자동 재연결
- 연결·리스너의 명시적 dispose와 포트 변경 시 정리
- 공유 키 HMAC-SHA256 메시지 인증
- timestamp와 sequence 기반 기본 replay 방지
- Apple Silicon 및 Intel Universal 앱 패키징

## 문제 해결

### 계속 `연결 중` 또는 `연결 대기`로 표시됨

1. 대상 Mac의 InputBridge를 먼저 시작합니다.
2. 조작 Mac에서 `Screen Sharing 대상 찾기`와 `포트 찾기`를 순서대로 실행합니다.
3. 양쪽 포트와 공유 키가 같은지 확인합니다.
4. 조작 Mac에서 실제 TCP 접근을 검사합니다.

```sh
nc -G 3 -vz <대상-Mac-주소> <포트>
```

- `succeeded`: TCP 경로는 정상입니다. 공유 키, 시스템 시간, 입력 소스 등록을
  확인합니다.
- `Connection refused`: 대상까지 도달했지만 해당 포트에서 앱이 수신 중이지
  않습니다. 대상 Mac의 역할·포트·실행 상태를 확인합니다.
- `Operation timed out`: 중간 방화벽 또는 macOS 방화벽이 패킷을 드롭할 가능성이
  큽니다.
- `Network is unreachable`: 대상 주소로 가는 라우팅이 없습니다.

### `NWError 48` 또는 포트가 이미 사용 중이라고 표시됨

오류 48은 `Address already in use`입니다. 같은 포트를 쓰는 프로세스를 확인합니다.

```sh
lsof -nP -iTCP:<포트>
```

이전 InputBridge가 남아 있으면 완전히 종료한 뒤 다시 실행합니다.

```sh
killall InputBridge
```

포트를 변경할 때는 앱을 중지하고 잠시 기다린 뒤 다시 시작합니다. 0.1.7부터 연결,
리스너, 재연결 작업과 콜백 핸들러를 명시적으로 정리합니다.

### 명령으로 상세 진단

자동 모드에서 대상 Mac의 포트가 열렸는지 확인:

```sh
lsof -nP -iTCP:45831 -sTCP:LISTEN
```

조작 Mac에서 대상 Mac으로 연결 확인:

```sh
nc -G 3 -vz <대상-Mac-주소> 45831
```

기존 방식에서 대상 Mac에서 조작 Mac으로 연결 확인:

```sh
nc -G 3 -vz <조작-Mac-주소> 45831
```

들어오거나 나가는 Screen Sharing 상대 주소 검색과 InputBridge 포트 연결을 한 번에
진단:

```sh
./Scripts/diagnose-screen-sharing-peer.sh
```

기본값이 아닌 포트를 사용하면 포트 번호를 인자로 전달합니다.

```sh
./Scripts/diagnose-screen-sharing-peer.sh 45832
```

- `인증되지 않았거나 오래된 메시지 무시`: 양쪽 공유 키와 시스템 시간을 확인합니다.
- Screen Sharing 주소가 검색되지 않음: 조작 Mac에서 직접 Screen Sharing 연결이
  유지 중인지 확인합니다. 여러 대상 또는 Apple Account 중계 연결은 자동으로
  선택하지 않습니다.

## 보안 및 제한 사항

- 입력 소스 식별자만 전송하며 입력한 텍스트는 전송하지 않습니다.
- HMAC은 메시지를 인증하지만 TCP 내용을 암호화하지는 않습니다.
- 공유 키는 현재 Keychain에 저장되지 않습니다.
- Screen Sharing 주소 자동 감지는 직접 TCP 연결에 한정되며, 다중 접속이나
  Apple Account 중계 연결에서는 수동 주소 입력이 필요할 수 있습니다.
- Bonjour 자동 검색과 코드 기반 페어링은 아직 구현되지 않았습니다.
- Apple Account 기반 Screen Sharing 중계 연결은 InputBridge의 TCP 연결을
  대신 전달하지 않습니다. 별도의 LAN 또는 VPN 경로가 필요합니다.

## 향후 작업

- Bonjour 자동 검색과 페어링 UI
- Keychain 기반 공유 키 저장
- 상호 인증 TLS
- 사용자 지정 입력 소스 매핑
- Screen Sharing 활성 상태에서만 동기화
- 로그인 시 자동 실행
