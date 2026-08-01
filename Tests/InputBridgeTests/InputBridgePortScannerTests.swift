import XCTest
@testable import InputBridge

final class InputBridgePortScannerTests: XCTestCase {
    func testFindsSingleListeningCandidate() {
        let openPort = UInt16.random(in: 35_000...37_000)
        let closedPort = openPort + 1
        let listenerReady = expectation(description: "listener ready")
        let target = makeTarget(port: openPort, ready: listenerReady)

        target.start()
        wait(for: [listenerReady], timeout: 2)

        XCTAssertEqual(
            InputBridgePortScanner().scan(
                host: "127.0.0.1",
                candidates: [closedPort, openPort],
                timeout: 1
            ),
            .found(openPort)
        )
        target.stop()
    }

    func testReportsMultipleListeningCandidatesWithoutChoosing() {
        let firstPort = UInt16.random(in: 37_001...39_000)
        let secondPort = firstPort + 1
        let firstReady = expectation(description: "first listener ready")
        let secondReady = expectation(description: "second listener ready")
        let first = makeTarget(port: firstPort, ready: firstReady)
        let second = makeTarget(port: secondPort, ready: secondReady)

        first.start()
        second.start()
        wait(for: [firstReady, secondReady], timeout: 2)

        XCTAssertEqual(
            InputBridgePortScanner().scan(
                host: "127.0.0.1",
                candidates: [secondPort, firstPort],
                timeout: 1
            ),
            .multiple([firstPort, secondPort])
        )
        first.stop()
        second.stop()
    }

    private func makeTarget(port: UInt16, ready: XCTestExpectation) -> SyncTransport {
        let target = SyncTransport(
            role: .sender,
            mode: .automatic,
            host: "",
            port: port,
            sharedSecret: "scanner-test-secret"
        )
        target.onStatus = { status in
            if status.contains("연결 대기 중") {
                ready.fulfill()
            }
        }
        return target
    }
}
