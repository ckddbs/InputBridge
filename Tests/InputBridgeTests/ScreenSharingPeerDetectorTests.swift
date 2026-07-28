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
}
