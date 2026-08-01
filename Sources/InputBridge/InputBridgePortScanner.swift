import Foundation
import Network

enum InputBridgePortScanResult: Equatable {
    case found(UInt16)
    case notFound
    case multiple([UInt16])
}

struct InputBridgePortScanner {
    static let defaultCandidates: [UInt16] =
        Array(45_831...45_840) + [48_000, 50_000, 55_000]

    func scan(
        host: String,
        candidates: [UInt16] = Self.defaultCandidates,
        timeout: TimeInterval = 2.5
    ) -> InputBridgePortScanResult {
        let uniqueCandidates = Array(Set(candidates)).sorted()
        guard !host.isEmpty, !uniqueCandidates.isEmpty else { return .notFound }

        let queue = DispatchQueue(label: "net.inputbridge.port-scanner")
        let group = DispatchGroup()
        var unfinished = Set(uniqueCandidates)
        var openPorts = Set<UInt16>()
        var connections: [NWConnection] = []

        for candidate in uniqueCandidates {
            guard let endpointPort = NWEndpoint.Port(rawValue: candidate) else { continue }

            group.enter()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )
            connections.append(connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard unfinished.remove(candidate) != nil else { return }
                    openPorts.insert(candidate)
                    group.leave()
                    connection.cancel()
                case .failed, .cancelled:
                    guard unfinished.remove(candidate) != nil else { return }
                    group.leave()
                case .waiting:
                    guard unfinished.remove(candidate) != nil else { return }
                    group.leave()
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        _ = group.wait(timeout: .now() + timeout)
        queue.sync {
            for connection in connections {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
            for _ in unfinished {
                group.leave()
            }
            unfinished.removeAll()
        }

        let sortedPorts = openPorts.sorted()
        switch sortedPorts.count {
        case 0:
            return .notFound
        case 1:
            return .found(sortedPorts[0])
        default:
            return .multiple(sortedPorts)
        }
    }
}
