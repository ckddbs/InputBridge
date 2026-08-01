import XCTest
@testable import InputBridge

final class SyncTransportTests: XCTestCase {
    func testAutomaticModeSendsOverControllerInitiatedConnection() {
        let port = UInt16.random(in: 50_000...55_000)
        let secret = "automatic-mode-secret"
        let targetReady = expectation(description: "target listener ready")
        let controllerConnected = expectation(description: "controller connected")
        let received = expectation(description: "controller received input source")

        let target = SyncTransport(
            role: .sender,
            mode: .automatic,
            host: "",
            port: port,
            sharedSecret: secret
        )
        target.onStatus = { status in
            if status.contains("연결 대기 중") {
                targetReady.fulfill()
            }
        }
        target.start()
        wait(for: [targetReady], timeout: 2)

        let controller = SyncTransport(
            role: .receiver,
            mode: .automatic,
            host: "127.0.0.1",
            port: port,
            sharedSecret: secret
        )
        controller.onStatus = { status in
            if status == "연결됨" {
                controllerConnected.fulfill()
            }
        }
        controller.onInputSource = { source in
            XCTAssertEqual(source, InputSourceMapper.portableABC)
            received.fulfill()
        }
        controller.start()
        wait(for: [controllerConnected], timeout: 2)

        target.send(inputSource: InputSourceMapper.portableABC)
        wait(for: [received], timeout: 2)

        target.stop()
        controller.stop()
    }

    func testLegacyModeStillSendsOverTargetInitiatedConnection() {
        let port = UInt16.random(in: 55_001...60_000)
        let secret = "legacy-mode-secret"
        let controllerReady = expectation(description: "controller listener ready")
        let targetConnected = expectation(description: "target connected")
        let received = expectation(description: "controller received input source")

        let controller = SyncTransport(
            role: .receiver,
            mode: .legacy,
            host: "",
            port: port,
            sharedSecret: secret
        )
        controller.onStatus = { status in
            if status.contains("연결 대기 중") {
                controllerReady.fulfill()
            }
        }
        controller.onInputSource = { source in
            XCTAssertEqual(source, InputSourceMapper.portableKorean)
            received.fulfill()
        }
        controller.start()
        wait(for: [controllerReady], timeout: 2)

        let target = SyncTransport(
            role: .sender,
            mode: .legacy,
            host: "127.0.0.1",
            port: port,
            sharedSecret: secret
        )
        target.onStatus = { status in
            if status == "연결됨" {
                targetConnected.fulfill()
            }
        }
        target.start()
        wait(for: [targetConnected], timeout: 2)

        target.send(inputSource: InputSourceMapper.portableKorean)
        wait(for: [received], timeout: 2)

        target.stop()
        controller.stop()
    }

    func testAutomaticTargetFallsBackToLegacyController() {
        let port = UInt16.random(in: 45_000...49_999)
        let secret = "fallback-secret"
        let controllerReady = expectation(description: "legacy controller listener ready")
        let targetConnected = expectation(description: "automatic target connected by fallback")
        let received = expectation(description: "legacy controller received input source")

        let controller = SyncTransport(
            role: .receiver,
            mode: .legacy,
            host: "",
            port: port,
            sharedSecret: secret
        )
        controller.onStatus = { status in
            if status.contains("연결 대기 중") {
                controllerReady.fulfill()
            }
        }
        controller.onInputSource = { source in
            XCTAssertEqual(source, InputSourceMapper.portableABC)
            received.fulfill()
        }
        controller.start()
        wait(for: [controllerReady], timeout: 2)

        let target = SyncTransport(
            role: .sender,
            mode: .automatic,
            host: "",
            port: port,
            sharedSecret: secret
        )
        target.onStatus = { status in
            if status == "연결됨" {
                targetConnected.fulfill()
            }
        }
        target.start()
        target.connectLegacyFallback(to: "127.0.0.1")
        wait(for: [targetConnected], timeout: 3)

        target.send(inputSource: InputSourceMapper.portableABC)
        wait(for: [received], timeout: 2)

        target.stop()
        controller.stop()
    }

    func testStopReleasesPortForRestart() {
        let port = UInt16.random(in: 40_000...44_999)
        let firstReady = expectation(description: "first listener ready")
        let secondReady = expectation(description: "second listener ready")

        let first = SyncTransport(
            role: .sender,
            mode: .automatic,
            host: "",
            port: port,
            sharedSecret: "restart-secret"
        )
        first.onStatus = { status in
            if status.contains("연결 대기 중") {
                firstReady.fulfill()
            }
        }
        first.start()
        wait(for: [firstReady], timeout: 2)
        first.stop()

        // NWListener.cancel() is synchronous from InputBridge's perspective,
        // but the kernel can take a moment to release the bound port.
        Thread.sleep(forTimeInterval: 0.25)

        let second = SyncTransport(
            role: .sender,
            mode: .automatic,
            host: "",
            port: port,
            sharedSecret: "restart-secret"
        )
        second.onStatus = { status in
            if status.contains("연결 대기 중") {
                secondReady.fulfill()
            }
        }
        second.start()
        wait(for: [secondReady], timeout: 2)
        second.stop()
    }
}
