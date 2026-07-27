import CryptoKit
import Foundation

struct SyncMessage: Codable, Equatable {
    let version: Int
    let sequence: UInt64
    let inputSourceID: String
    let timestamp: UInt64
    let authentication: String

    static func make(
        sequence: UInt64,
        inputSourceID: String,
        secret: String,
        now: Date = Date()
    ) -> SyncMessage {
        let timestamp = UInt64(now.timeIntervalSince1970 * 1_000)
        return SyncMessage(
            version: 1,
            sequence: sequence,
            inputSourceID: inputSourceID,
            timestamp: timestamp,
            authentication: signature(
                sequence: sequence,
                inputSourceID: inputSourceID,
                timestamp: timestamp,
                secret: secret
            )
        )
    }

    func isAuthentic(secret: String, now: Date = Date()) -> Bool {
        let age = abs(Int64(now.timeIntervalSince1970 * 1_000) - Int64(timestamp))
        guard version == 1, age < 30_000 else { return false }
        return authentication == Self.signature(
            sequence: sequence,
            inputSourceID: inputSourceID,
            timestamp: timestamp,
            secret: secret
        )
    }

    private static func signature(
        sequence: UInt64,
        inputSourceID: String,
        timestamp: UInt64,
        secret: String
    ) -> String {
        let payload = "\(sequence)|\(inputSourceID)|\(timestamp)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(code).base64EncodedString()
    }
}
