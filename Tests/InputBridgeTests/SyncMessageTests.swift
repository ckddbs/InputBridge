import XCTest
@testable import InputBridge

final class SyncMessageTests: XCTestCase {
    func testAuthenticatesWithSameSecret() {
        let now = Date()
        let message = SyncMessage.make(
            sequence: 1,
            inputSourceID: InputSourceMapper.portableABC,
            secret: "pairing-secret",
            now: now
        )

        XCTAssertTrue(message.isAuthentic(secret: "pairing-secret", now: now))
        XCTAssertFalse(message.isAuthentic(secret: "wrong-secret", now: now))
    }

    func testRejectsExpiredMessage() {
        let created = Date(timeIntervalSince1970: 100)
        let message = SyncMessage.make(
            sequence: 1,
            inputSourceID: InputSourceMapper.portableABC,
            secret: "pairing-secret",
            now: created
        )

        XCTAssertFalse(
            message.isAuthentic(
                secret: "pairing-secret",
                now: created.addingTimeInterval(31)
            )
        )
    }
}
