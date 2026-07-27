import Foundation

struct InputSourceMapper {
    static let portableABC = "portable:latin"
    static let portableKorean = "portable:korean-2set"

    private let useKoreanDefaults: Bool

    init(useKoreanDefaults: Bool) {
        self.useKoreanDefaults = useKoreanDefaults
    }

    func portableID(for sourceID: String) -> String {
        guard useKoreanDefaults else { return sourceID }
        if sourceID == "com.apple.keylayout.ABC" {
            return Self.portableABC
        }
        if sourceID.localizedCaseInsensitiveContains("Korean"),
           sourceID.localizedCaseInsensitiveContains("2-Set") {
            return Self.portableKorean
        }
        return sourceID
    }

    func destinationID(for portableID: String) -> String {
        guard useKoreanDefaults else { return portableID }
        switch portableID {
        case Self.portableABC:
            return "com.apple.keylayout.ABC"
        case Self.portableKorean:
            return "com.apple.inputmethod.Korean.2SetKorean"
        default:
            return portableID
        }
    }
}
