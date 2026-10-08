import Darwin
import Foundation

enum ScreenSharingConnectionDirection: Equatable {
    case incoming
    case outgoing
}

struct TCPConnection: Equatable {
    let localPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
}

struct ScreenSharingPeerDetector {
    static let screenSharingPort: UInt16 = 5900

    func detect(direction: ScreenSharingConnectionDirection) -> String? {
        // Since macOS 27 the TCP table that netstat reads comes back empty when an
        // app without Local Network access launches it. Socket info of processes
        // owned by this user (such as the Screen Sharing app) is still readable,
        // so check those first and keep netstat for root-owned screensharingd.
        let connections = Self.establishedConnectionsOfAccessibleProcesses()
        if !Self.peerHosts(from: connections, direction: direction).isEmpty {
            return Self.peerHost(from: connections, direction: direction)
        }
        return detectWithNetstat(direction: direction)
    }

    private func detectWithNetstat(direction: ScreenSharingConnectionDirection) -> String? {
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
        from connections: [TCPConnection],
        direction: ScreenSharingConnectionDirection
    ) -> String? {
        let hosts = peerHosts(from: connections, direction: direction)
        return hosts.count == 1 ? hosts.first : nil
    }

    private static func peerHosts(
        from connections: [TCPConnection],
        direction: ScreenSharingConnectionDirection
    ) -> Set<String> {
        Set(connections.compactMap { connection in
            let expectedPort = direction == .incoming
                ? connection.localPort
                : connection.remotePort
            guard expectedPort == screenSharingPort,
                  isRemotePeer(connection.remoteHost) else {
                return nil
            }
            return connection.remoteHost
        })
    }

    static func peerHost(
        fromNetstatOutput output: String,
        direction: ScreenSharingConnectionDirection = .incoming
    ) -> String? {
        let connections = output
            .split(whereSeparator: \.isNewline)
            .compactMap { connection(fromNetstatLine: String($0)) }
        return peerHost(from: connections, direction: direction)
    }

    private static func connection(fromNetstatLine line: String) -> TCPConnection? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 6,
              fields[0].hasPrefix("tcp"),
              fields[5] == "ESTABLISHED",
              let local = parseEndpoint(fields[3]),
              let remote = parseEndpoint(fields[4]) else {
            return nil
        }
        return TCPConnection(localPort: local.port, remoteHost: remote.host, remotePort: remote.port)
    }

    private static func isRemotePeer(_ host: String) -> Bool {
        !host.isEmpty && host != "127.0.0.1" && host != "::1"
    }

    private static func parseEndpoint(_ endpoint: Substring) -> (host: String, port: UInt16)? {
        guard let separator = endpoint.lastIndex(of: "."),
              let port = UInt16(endpoint[endpoint.index(after: separator)...]) else {
            return nil
        }
        return (String(endpoint[..<separator]), port)
    }
}

// MARK: - libproc

extension ScreenSharingPeerDetector {
    private static let tcpEstablishedState: Int32 = 4 // TSI_S_ESTABLISHED
    private static let ipv4Flag: UInt8 = 0x1 // INI_IPV4
    private static let ipv6Flag: UInt8 = 0x2 // INI_IPV6

    static func establishedConnectionsOfAccessibleProcesses() -> [TCPConnection] {
        processIDs().flatMap(establishedConnections(ofProcess:))
    }

    private static func processIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }

        // Leave room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private static func establishedConnections(ofProcess pid: pid_t) -> [TCPConnection] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let capacity = Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let filledSize = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard filledSize > 0 else { return [] }

        return descriptors
            .prefix(Int(filledSize) / MemoryLayout<proc_fdinfo>.stride)
            .filter { $0.proc_fdtype == PROX_FDTYPE_SOCKET }
            .compactMap { establishedConnection(ofProcess: pid, descriptor: $0.proc_fd) }
    }

    private static func establishedConnection(
        ofProcess pid: pid_t,
        descriptor: Int32
    ) -> TCPConnection? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, descriptor, PROC_PIDFDSOCKETINFO, &info, size) == size,
              info.psi.soi_kind == SOCKINFO_TCP else {
            return nil
        }

        let tcp = info.psi.soi_proto.pri_tcp
        guard tcp.tcpsi_state == tcpEstablishedState,
              let remoteHost = remoteAddress(of: tcp.tcpsi_ini) else {
            return nil
        }

        return TCPConnection(
            localPort: UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)),
            remoteHost: remoteHost,
            remotePort: UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_fport))
        )
    }

    private static func remoteAddress(of endpoint: in_sockinfo) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))

        if endpoint.insi_vflag & ipv4Flag != 0 {
            var address = endpoint.insi_faddr.ina_46.i46a_addr4
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }

        if endpoint.insi_vflag & ipv6Flag != 0 {
            var address = endpoint.insi_faddr.ina_6
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }

        return nil
    }
}
