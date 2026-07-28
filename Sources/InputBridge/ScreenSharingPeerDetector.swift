import Foundation

struct ScreenSharingPeerDetector {
    static let screenSharingPort: UInt16 = 5900

    func detect() -> String? {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-nP",
            "-iTCP:\(Self.screenSharingPort)",
            "-sTCP:ESTABLISHED",
            "-Fn"
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Self.peerHost(fromLsofOutput: text)
    }

    static func peerHost(fromLsofOutput output: String) -> String? {
        let hosts = Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    guard line.first == "n" else { return nil }
                    return peerHost(fromConnection: String(line.dropFirst()))
                }
        )

        // 자동 선택은 현재 Screen Sharing 접속자가 정확히 한 대일 때만 안전하다.
        return hosts.count == 1 ? hosts.first : nil
    }

    private static func peerHost(fromConnection connection: String) -> String? {
        let endpoints = connection.components(separatedBy: "->")
        guard endpoints.count == 2,
              let local = parseEndpoint(endpoints[0]),
              let remote = parseEndpoint(endpoints[1]),
              local.port == screenSharingPort,
              !remote.host.isEmpty,
              remote.host != "127.0.0.1",
              remote.host != "::1" else {
            return nil
        }

        return remote.host
    }

    private static func parseEndpoint(_ endpoint: String) -> (host: String, port: UInt16)? {
        if endpoint.hasPrefix("["),
           let closingBracket = endpoint.lastIndex(of: "]"),
           endpoint.index(after: closingBracket) < endpoint.endIndex {
            let colon = endpoint.index(after: closingBracket)
            guard endpoint[colon] == ":",
                  let port = UInt16(endpoint[endpoint.index(after: colon)...]) else {
                return nil
            }
            return (String(endpoint[endpoint.index(after: endpoint.startIndex)..<closingBracket]), port)
        }

        guard let colon = endpoint.lastIndex(of: ":"),
              let port = UInt16(endpoint[endpoint.index(after: colon)...]) else {
            return nil
        }
        return (String(endpoint[..<colon]), port)
    }
}
