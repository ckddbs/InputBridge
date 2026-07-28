import XCTest
@testable import InputBridge

final class ScreenSharingPeerDetectorTests: XCTestCase {
    func testFindsRemoteIPv4AddressForIncomingScreenSharingConnection() {
        let output = """
        p123
        cscreensharingd
        f10
        n192.168.100.53:5900->192.168.200.215:64609
        """

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(fromLsofOutput: output),
            "192.168.200.215"
        )
    }

    func testIgnoresOutgoingScreenSharingConnection() {
        let output = """
        p123
        cScreen Sharing
        f9
        n192.168.200.215:64609->192.168.100.53:5900
        """

        XCTAssertNil(ScreenSharingPeerDetector.peerHost(fromLsofOutput: output))
    }

    func testSupportsIPv6Addresses() {
        let output = """
        p123
        cscreensharingd
        f10
        n[fd00::53]:5900->[fd00::215]:64609
        """

        XCTAssertEqual(
            ScreenSharingPeerDetector.peerHost(fromLsofOutput: output),
            "fd00::215"
        )
    }

    func testDoesNotChooseWhenMultiplePeersAreConnected() {
        let output = """
        n192.168.100.53:5900->192.168.200.215:64609
        n192.168.100.53:5900->192.168.200.216:64610
        """

        XCTAssertNil(ScreenSharingPeerDetector.peerHost(fromLsofOutput: output))
    }
}
