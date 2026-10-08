import XCTest
@testable import InputBridge

final class ScreenSharingPeerDetectorTests: XCTestCase {
    func testFindsRemoteIPv4AddressForIncomingScreenSharingConnection() {
        let output = """
        Active Internet connections (including servers)
        Proto Recv-Q Send-Q  Local Address              Foreign Address            (state)
        tcp4       0      0  192.168.100.53.5900        192.168.200.215.51548       ESTABLISHED
        """

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(fromNetstatOutput: output),
            "192.168.200.215"
        )
    }

    func testIgnoresOutgoingScreenSharingConnection() {
        let output = """
        tcp4 0 0 192.168.200.215.51548 192.168.100.53.5900 ESTABLISHED
        """

        XCTAssertNil(ScreenSharingPeerDetector.peerHost(fromNetstatOutput: output))
    }

    func testFindsRemoteHostForOutgoingScreenSharingConnection() {
        let output = """
        tcp4 0 0 192.168.0.12.51548 192.168.100.53.5900 ESTABLISHED
        """

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(
                fromNetstatOutput: output,
                direction: .outgoing
            ),
            "192.168.100.53"
        )
    }

    func testOutgoingSearchIgnoresIncomingScreenSharingConnection() {
        let output = """
        tcp4 0 0 192.168.100.53.5900 192.168.0.12.51548 ESTABLISHED
        """

        XCTAssertNil(
            ScreenSharingPeerDetector.peerHost(
                fromNetstatOutput: output,
                direction: .outgoing
            )
        )
    }

    func testSupportsIPv6Addresses() {
        let output = """
        tcp6 0 0 fd00::53.5900 fd00::215.51548 ESTABLISHED
        """

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(fromNetstatOutput: output),
            "fd00::215"
        )
    }

    func testDoesNotChooseWhenMultiplePeersAreConnected() {
        let output = """
        tcp4 0 0 192.168.100.53.5900 192.168.200.215.51548 ESTABLISHED
        tcp4 0 0 192.168.100.53.5900 192.168.200.216.51549 ESTABLISHED
        """

        XCTAssertNil(ScreenSharingPeerDetector.peerHost(fromNetstatOutput: output))
    }

    func testIgnoresListenerAndClosedConnections() {
        let output = """
        tcp4 0 0 *.5900 *.* LISTEN
        tcp4 0 0 192.168.100.53.5900 192.168.200.215.51548 CLOSED
        """

        XCTAssertNil(ScreenSharingPeerDetector.peerHost(fromNetstatOutput: output))
    }

    func testFindsOutgoingPeerFromProcessSocketConnections() {
        let connections = [
            TCPConnection(localPort: 52650, remoteHost: "192.168.100.50", remotePort: 5900),
            TCPConnection(localPort: 52651, remoteHost: "160.79.104.10", remotePort: 443),
        ]

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(from: connections, direction: .outgoing),
            "192.168.100.50"
        )
        XCTAssertNil(ScreenSharingPeerDetector.peerHost(from: connections, direction: .incoming))
    }

    func testProcessSocketConnectionsIgnoreLoopbackAndAmbiguousPeers() {
        let loopback = [
            TCPConnection(localPort: 52650, remoteHost: "127.0.0.1", remotePort: 5900),
        ]
        XCTAssertNil(ScreenSharingPeerDetector.peerHost(from: loopback, direction: .outgoing))

        let multiple = [
            TCPConnection(localPort: 52650, remoteHost: "192.168.100.50", remotePort: 5900),
            TCPConnection(localPort: 52651, remoteHost: "192.168.100.51", remotePort: 5900),
        ]
        XCTAssertNil(ScreenSharingPeerDetector.peerHost(from: multiple, direction: .outgoing))
    }
}
