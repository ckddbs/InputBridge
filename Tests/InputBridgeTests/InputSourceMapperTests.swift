import XCTest
@testable import InputBridge

final class InputSourceMapperTests: XCTestCase {
    func testKoreanDefaultsRoundTripPortableIDs() {
        let mapper = InputSourceMapper(useKoreanDefaults: true)

        XCTAssertEqual(
            mapper.portableID(for: "com.apple.keylayout.ABC"),
            InputSourceMapper.portableABC
        )
        XCTAssertEqual(
            mapper.destinationID(for: InputSourceMapper.portableKorean),
            "com.apple.inputmethod.Korean.2SetKorean"
        )
    }

    func testUnknownSourcePassesThrough() {
        let mapper = InputSourceMapper(useKoreanDefaults: true)
        XCTAssertEqual(mapper.portableID(for: "custom.input.source"), "custom.input.source")
    }
}
