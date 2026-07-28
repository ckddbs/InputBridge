import Foundation

struct ScreenSharingPeerDetector {
    static let screenSharingPort: UInt16 = 5900

    func detect() -> String? {
        let process = Process()
        let output = Pipe()

        // screensharingd runs as root, so lsof invoked by this user cannot see its
        // sockets. netstat reads the TCP table and exposes the connection without
        // requiring the app to run as root.
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-an", "-p", "tcp"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.peerHost(fromNetstatOutput: text)
    }

    static func peerHost(fromNetstatOutput output: String) -> String? {
        let hosts = Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { peerHost(fromNetstatLine: String($0)) }
        )

        return hosts.count == 1 ? hosts.first : nil
    }

    private static func peerHost(fromNetstatLine line: String) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 6,
              fields[0].hasPrefix("tcp"),
              fields[5] == "ESTABLISHED",
              let local = parseEndpoint(fields[3]),
              let remote = parseEndpoint(fields[4]),
              local.port == screenSharingPort,
              !remote.host.isEmpty,
              remote.host != "127.0.0.1",
              remote.host != "::1" else {
            return nil
        }

        return remote.host
    }

    private static func parseEndpoint(_ endpoint: Substring) -> (host: String, port: UInt16)? {
        guard let separator = endpoint.lastIndex(of: "."),
              let port = UInt16(endpoint[endpoint.index(after: separator)...]) else {
            return nil
        }
        return (String(endpoint[..<separator]), port)
    }
}
