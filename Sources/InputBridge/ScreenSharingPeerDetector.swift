import Foundation

enum ScreenSharingConnectionDirection: Equatable {
    case incoming
    case outgoing
}

struct ScreenSharingPeerDetector {
    static let screenSharingPort: UInt16 = 5900

    func detect(direction: ScreenSharingConnectionDirection) -> String? {
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
        return Self.peerHost(fromNetstatOutput: text, direction: direction)
    }

    static func peerHost(
        fromNetstatOutput output: String,
        direction: ScreenSharingConnectionDirection = .incoming
    ) -> String? {
        let hosts = Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap {
                    peerHost(fromNetstatLine: String($0), direction: direction)
                }
        )

        return hosts.count == 1 ? hosts.first : nil
    }

    private static func peerHost(
        fromNetstatLine line: String,
        direction: ScreenSharingConnectionDirection
    ) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 6,
              fields[0].hasPrefix("tcp"),
              fields[5] == "ESTABLISHED",
              let local = parseEndpoint(fields[3]),
              let remote = parseEndpoint(fields[4]) else {
            return nil
        }

        let expectedPort = direction == .incoming ? local.port : remote.port
        guard expectedPort == screenSharingPort,
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
