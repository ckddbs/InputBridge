import XCTest
@testable import InputBridge

@MainActor
final class AppModelTests: XCTestCase {
    func testAutomaticModeRequestsTargetAddressOnControllerOnly() {
        let model = AppModel()
        model.connectionMode = .automatic

        model.role = .receiver
        XCTAssertTrue(model.showsHostField)
        XCTAssertEqual(model.hostFieldPrompt, "대상 Mac 주소 또는 이름")

        model.role = .sender
        XCTAssertFalse(model.showsHostField)
    }

    func testLegacyModeRequestsControllerAddressOnTargetOnly() {
        let model = AppModel()
        model.connectionMode = .legacy

        model.role = .sender
        XCTAssertTrue(model.showsHostField)
        XCTAssertEqual(model.hostFieldPrompt, "조작 Mac 주소 또는 이름")

        model.role = .receiver
        XCTAssertFalse(model.showsHostField)
    }

    func testPortSearchRequiresAutomaticControllerWithTargetHost() {
        let model = AppModel()
        model.role = .receiver
        model.connectionMode = .automatic
        XCTAssertFalse(model.canSearchInputBridgePort)

        model.host = "192.168.100.53"
        XCTAssertTrue(model.canSearchInputBridgePort)

        model.connectionMode = .legacy
        XCTAssertFalse(model.canSearchInputBridgePort)
    }
}
