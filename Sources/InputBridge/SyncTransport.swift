import Foundation
import Network

final class SyncTransport {
    var onStatus: ((String) -> Void)?
    var onInputSource: ((String) -> Void)?

    private let role: SyncRole
    private let mode: SyncConnectionMode
    private let host: String
    private let port: NWEndpoint.Port
    private let sharedSecret: String
    private let queue = DispatchQueue(label: "net.inputbridge.transport")
    private let queueKey = DispatchSpecificKey<Void>()
    private var connection: NWConnection?
    private var listener: NWListener?
    private var outboundHost: NWEndpoint.Host?
    private var sequence: UInt64 = 0
    private var lastReceivedSequence: UInt64 = 0
    private var pendingInputSource: String?
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStopped = true

    init(
        role: SyncRole,
        mode: SyncConnectionMode,
        host: String,
        port: UInt16,
        sharedSecret: String
    ) {
        self.role = role
        self.mode = mode
        self.host = host
        self.port = NWEndpoint.Port(rawValue: port)!
        self.sharedSecret = sharedSecret
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        reconnectWorkItem?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStopped = false

            switch self.mode {
            case .automatic:
                self.startListener()
                if self.role == .receiver {
                    self.setOutboundHostAndConnect(self.host)
                }
            case .legacy:
                if self.role == .sender {
                    self.setOutboundHostAndConnect(self.host)
                } else {
                    self.startListener()
                }
            }
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            disposeResources()
        } else {
            queue.sync { self.disposeResources() }
        }
    }

    private func disposeResources() {
        isStopped = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        let activeConnection = connection
        connection = nil
        activeConnection?.stateUpdateHandler = nil
        activeConnection?.cancel()

        let activeListener = listener
        listener = nil
        activeListener?.newConnectionHandler = nil
        activeListener?.stateUpdateHandler = nil
        activeListener?.cancel()

        outboundHost = nil
        pendingInputSource = nil
        onStatus = nil
        onInputSource = nil
    }

    /// In automatic mode the target Mac listens first. If the preferred
    /// controller-to-target path is unavailable, it can still connect to an
    /// older controller or a network that only permits the legacy direction.
    func connectLegacyFallback(to host: String) {
        queue.async { [weak self] in
            guard let self,
                  self.mode == .automatic,
                  self.role == .sender,
                  !host.isEmpty,
                  !self.isStopped else { return }

            self.outboundHost = NWEndpoint.Host(host)
            self.scheduleReconnect(after: 1)
        }
    }

    func send(inputSource: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let connection = self.connection,
                  connection.state == .ready else {
                self.pendingInputSource = inputSource
                return
            }
            self.sendNow(inputSource: inputSource, on: connection)
        }
    }

    private func setOutboundHostAndConnect(_ host: String) {
        guard !host.isEmpty else { return }
        let endpointHost = NWEndpoint.Host(host)
        outboundHost = endpointHost
        startOutboundConnection(to: endpointHost)
    }

    private func startOutboundConnection(to host: NWEndpoint.Host) {
        guard !isStopped, connection == nil else { return }

        let newConnection = NWConnection(host: host, port: port, using: .tcp)
        install(newConnection)
        onStatus?("\(host):\(port.rawValue)에 연결 중…")
    }

    private func startListener() {
        guard listener == nil, !isStopped else { return }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] newConnection in
                guard let self else { return }

                if let current = self.connection, current.state == .ready {
                    newConnection.cancel()
                    return
                }

                self.connection?.cancel()
                self.connection = nil
                self.install(newConnection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready:
                    if self.connection == nil {
                        self.onStatus?("포트 \(self.port.rawValue)에서 연결 대기 중")
                    }
                case .failed(let error):
                    self.listener = nil
                    if self.connection == nil {
                        self.onStatus?("수신 실패: \(error.localizedDescription)")
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        } catch {
            onStatus?("수신 시작 실패: \(error.localizedDescription)")
        }
    }

    private func install(_ newConnection: NWConnection) {
        connection = newConnection
        lastReceivedSequence = 0
        observe(newConnection)
        newConnection.start(queue: queue)
    }

    private func observe(_ observedConnection: NWConnection) {
        observedConnection.stateUpdateHandler = { [weak self, weak observedConnection] state in
            guard let self,
                  let observedConnection,
                  self.connection === observedConnection else { return }

            switch state {
            case .ready:
                self.reconnectWorkItem?.cancel()
                self.reconnectWorkItem = nil
                self.onStatus?("연결됨")

                if self.role == .sender,
                   let pending = self.pendingInputSource {
                    self.pendingInputSource = nil
                    self.sendNow(inputSource: pending, on: observedConnection)
                } else if self.role == .receiver {
                    self.receive(on: observedConnection, buffer: Data())
                }
            case .failed(let error):
                self.connection = nil
                self.onStatus?("연결 실패: \(error.localizedDescription)")
                self.scheduleReconnect()
            case .waiting(let error):
                self.onStatus?("연결 대기: \(error.localizedDescription)")
            case .cancelled:
                self.connection = nil
                if !self.isStopped {
                    self.onStatus?("연결 종료")
                    self.scheduleReconnect()
                }
            default:
                break
            }
        }
    }

    private func sendNow(inputSource: String, on connection: NWConnection) {
        sequence += 1
        let message = SyncMessage.make(
            sequence: sequence,
            inputSourceID: inputSource,
            secret: sharedSecret
        )
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onStatus?("전송 실패: \(error.localizedDescription)")
            } else {
                self?.onStatus?("전송 완료: \(inputSource)")
            }
        })
    }

    private func scheduleReconnect(after delay: TimeInterval = 1) {
        guard !isStopped,
              connection == nil,
              let outboundHost,
              reconnectWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.reconnectWorkItem = nil
            self.startOutboundConnection(to: outboundHost)
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self, weak connection] data, _, complete, error in
            guard let self,
                  let connection,
                  self.connection === connection else { return }

            var pending = buffer
            if let data { pending.append(data) }

            while let newline = pending.firstIndex(of: 0x0A) {
                let frame = pending[..<newline]
                pending.removeSubrange(...newline)
                self.handle(Data(frame))
            }

            if let error {
                self.onStatus?("수신 오류: \(error.localizedDescription)")
            } else if !complete {
                self.receive(on: connection, buffer: pending)
            } else {
                connection.cancel()
            }
        }
    }

    private func handle(_ data: Data) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data),
              message.isAuthentic(secret: sharedSecret),
              message.sequence > lastReceivedSequence else {
            onStatus?("인증되지 않았거나 오래된 메시지 무시")
            return
        }
        lastReceivedSequence = message.sequence
        onInputSource?(message.inputSourceID)
    }
}
