#!/bin/sh

set -u

screen_sharing_port=5900
input_bridge_port="${1:-45831}"

case "$input_bridge_port" in
    ''|*[!0-9]*)
        echo "Usage: $0 [InputBridge-port]" >&2
        exit 2
        ;;
esac

if [ "$input_bridge_port" -lt 1 ] || [ "$input_bridge_port" -gt 65535 ]; then
    echo "InputBridge port must be between 1 and 65535." >&2
    exit 2
fi

echo "InputBridge 네트워크 진단"
echo

local_host_name="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || true)"
if [ -n "$local_host_name" ]; then
    echo "Bonjour 이름: ${local_host_name}.local"
fi

local_addresses="$(
    /sbin/ifconfig 2>/dev/null |
        /usr/bin/awk '
            /^[[:alnum:]]/ {
                interface = $1
                sub(/:$/, "", interface)
            }
            /^[[:space:]]+inet / && $2 != "127.0.0.1" {
                address[interface] = $2
            }
            END {
                for (interface in address) {
                    print interface, address[interface]
                }
            }
        ' |
        /usr/bin/sort
)"

if [ -n "$local_addresses" ]; then
    echo "이 Mac의 IPv4 주소:"
    echo "$local_addresses" | while read -r interface address; do
        echo "  $interface: $address"
    done
else
    echo "이 Mac의 IPv4 주소를 찾지 못했습니다."
fi

echo
netstat_output_file="$(/usr/bin/mktemp -t inputbridge-netstat.XXXXXX)" || exit 1
netstat_error_file="$(/usr/bin/mktemp -t inputbridge-netstat-error.XXXXXX)" || {
    rm -f "$netstat_output_file"
    exit 1
}
trap 'rm -f "$netstat_output_file" "$netstat_error_file"' EXIT HUP INT TERM

if ! /usr/sbin/netstat -an -p tcp >"$netstat_output_file" 2>"$netstat_error_file"; then
    echo "TCP 연결 테이블을 읽지 못했습니다." >&2
    if [ -s "$netstat_error_file" ]; then
        sed 's/^/  /' "$netstat_error_file" >&2
    fi
    echo >&2
    echo "샌드박스 밖의 Terminal에서 이 스크립트를 실행하세요." >&2
    exit 1
fi

connections="$(
    /usr/bin/awk -v port="$screen_sharing_port" '
        $1 ~ /^tcp/ && $6 == "ESTABLISHED" {
            local_endpoint = $4
            remote_endpoint = $5
            local_port = local_endpoint
            remote_port = remote_endpoint
            remote_host = remote_endpoint
            sub(/^.*\./, "", local_port)
            sub(/^.*\./, "", remote_port)
            sub(/\.[^.]*$/, "", remote_host)
            if (local_port == port && remote_host != "127.0.0.1" && remote_host != "::1") {
                print "incoming", remote_host
            } else if (remote_port == port && remote_host != "127.0.0.1" && remote_host != "::1") {
                print "outgoing", remote_host
            }
        }
    ' "$netstat_output_file" |
        /usr/bin/sort -u
)"

connection_count="$(printf '%s\n' "$connections" | /usr/bin/awk 'NF { count++ } END { print count + 0 }')"

case "$connection_count" in
    0)
        echo "Screen Sharing 접속자: 찾지 못함"
        echo "Screen Sharing 연결을 유지한 채 다시 실행하세요."
        exit 3
        ;;
    1)
        direction="$(printf '%s\n' "$connections" | /usr/bin/awk '{ print $1 }')"
        peer_address="$(printf '%s\n' "$connections" | /usr/bin/awk '{ print $2 }')"
        ;;
    *)
        echo "Screen Sharing 연결 (${connection_count}개):"
        printf '%s\n' "$connections" | /usr/bin/awk '
            $1 == "incoming" { print "  들어오는 연결: " $2 }
            $1 == "outgoing" { print "  나가는 연결: " $2 }
        '
        echo "연결이 여러 개여서 InputBridge가 주소를 자동 선택할 수 없습니다."
        exit 4
        ;;
esac

if [ "$direction" = "incoming" ]; then
    echo "Screen Sharing 접속자: $peer_address (들어오는 연결)"
    echo "판단한 역할: 대상 Mac"
else
    echo "Screen Sharing 대상: $peer_address (나가는 연결)"
    echo "판단한 역할: 조작 Mac"
fi

echo
if [ "$direction" = "incoming" ]; then
    listening_count="$(
        /usr/bin/awk -v port="$input_bridge_port" '
            $1 ~ /^tcp/ && $6 == "LISTEN" {
                local_port = $4
                sub(/^.*\./, "", local_port)
                if (local_port == port) count++
            }
            END { print count + 0 }
        ' "$netstat_output_file"
    )"
    if [ "$listening_count" -gt 0 ]; then
        echo "포트 ${input_bridge_port}에서 InputBridge 연결을 기다리고 있습니다."
        exit 0
    fi
    echo "포트 ${input_bridge_port}이(가) 열려 있지 않습니다. 대상 Mac에서 InputBridge를 시작하세요."
    exit 5
fi

echo "대상 Mac $peer_address:$input_bridge_port 연결 확인 중..."
connect_result="$(/usr/bin/nc -G 3 -vz "$peer_address" "$input_bridge_port" 2>&1)"
connect_status=$?
echo "  $connect_result"

if [ "$connect_status" -eq 0 ]; then
    echo "결과: 조작 Mac의 대상 주소로 ${peer_address}을(를) 사용하세요."
    exit 0
fi

echo "결과: 대상 주소는 ${peer_address}이지만 InputBridge 포트 ${input_bridge_port}에는 연결할 수 없습니다."
echo "대상 Mac에서 InputBridge를 시작하고 macOS 방화벽을 확인하세요."
exit 5
