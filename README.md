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
조작 Mac에서 Screen Sharing으로 한/영 전환
                    │
                    ▼
          Screen Sharing 대상 Mac
           입력 소스 변경 감지
                    │ TCP 45831
                    ▼
                조작 Mac
           같은 입력 소스로 적용
```

앱은 양쪽 Mac에 모두 설치합니다.

| Mac | InputBridge 역할 | 설정 |
| --- | --- | --- |
| 키보드를 사용하는 Mac | `조작 Mac` | 포트와 공유 키를 입력하고 수신 대기 |
| Screen Sharing 대상 Mac | `대상 Mac` | 조작 Mac 주소, 같은 포트와 공유 키 입력 |

## 요구 사항

- macOS 13 Ventura 이상
- Apple Silicon 또는 Intel Mac
- 양쪽 Mac에 `ABC`와 `한국어 - 두벌식` 입력 소스 등록
- 양쪽 Mac이 서로 접근할 수 있는 LAN 또는 VPN

## 사용 방법

1. 키보드를 사용하는 Mac에서 `조작 Mac`을 선택합니다.
2. 포트와 공유 키를 입력하고 시작합니다.
3. Screen Sharing 대상 Mac에서 `대상 Mac`을 선택합니다.
4. 조작 Mac의 주소와 동일한 포트·공유 키를 입력하고 시작합니다.
5. Screen Sharing 창에서 한/영을 변경합니다.

대상 Mac에서 `Screen Sharing 주소 찾기`를 누르면 직접 연결된 접속자의 주소를
검색합니다. 발견된 주소를 확인한 뒤 `적용`을 누르면 조작 Mac 주소에 입력됩니다.
감지할 수 없거나 여러 대가 접속한 경우에는 주소를 직접 입력합니다.

같은 LAN에서는 IP 대신 Bonjour 호스트 이름을 사용할 수 있습니다.

```sh
scutil --get LocalHostName
```

결과가 `Chris-MacBook`이면 대상 Mac의 주소 입력란에
`Chris-MacBook.local`을 입력합니다.

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

```sh
./Scripts/package-unsigned.sh 0.1.3
```

결과:

```text
dist/InputBridge-0.1.3-unsigned-universal.zip
```

## 현재 구현

- macOS 입력 소스 변경 알림 및 0.2초 폴링
- ABC와 기본 한글 두벌식의 portable ID 매핑
- Network.framework TCP 송수신
- 직접 연결된 Screen Sharing 접속자의 주소 자동 감지
- 연결 실패 시 자동 재연결
- 공유 키 HMAC-SHA256 메시지 인증
- timestamp와 sequence 기반 기본 replay 방지
- Apple Silicon 및 Intel Universal 앱 패키징

## 문제 해결

대상 Mac에서 포트가 열렸는지 확인:

```sh
lsof -nP -iTCP:45831 -sTCP:LISTEN
```

조작 Mac에서 로컬 수신 확인:

```sh
nc -vz 127.0.0.1 45831
```

대상 Mac에서 조작 Mac으로 연결 확인:

```sh
nc -G 3 -vz <조작-Mac-주소> 45831
```

- `Connection refused`: 조작 Mac이 수신 대기 중인지 확인합니다.
- `Operation timed out`: 주소, macOS 방화벽 또는 VPN 경로를 확인합니다.
- `인증되지 않았거나 오래된 메시지 무시`: 양쪽 공유 키와 시스템 시간을 확인합니다.

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
