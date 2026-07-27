import Foundation
import Network

final class SyncTransport {
    var onStatus: ((String) -> Void)?
    var onInputSource: ((String) -> Void)?

    private let role: SyncRole
    private let host: String
    private let port: NWEndpoint.Port
    private let sharedSecret: String
    private let queue = DispatchQueue(label: "net.inputbridge.transport")
    private var connection: NWConnection?
    private var listener: NWListener?
    private var sequence: UInt64 = 0
    private var lastReceivedSequence: UInt64 = 0
    private var pendingInputSource: String?
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStopped = false

    init(role: SyncRole, host: String, port: UInt16, sharedSecret: String) {
        self.role = role
        self.host = host
        self.port = NWEndpoint.Port(rawValue: port)!
        self.sharedSecret = sharedSecret
    }

    func start() {
        isStopped = false
        role == .sender ? startSender() : startReceiver()
    }

    func stop() {
        isStopped = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
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

    private func startSender() {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        observe(connection)
        connection.start(queue: queue)
    }

    private func startReceiver() {
        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connection?.cancel()
                self.connection = connection
                self.lastReceivedSequence = 0
                self.observe(connection)
                connection.start(queue: self.queue)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.onStatus?("포트 \(self?.port.rawValue ?? 0)에서 대기 중")
                } else if case .failed(let error) = state {
                    self?.onStatus?("수신 실패: \(error.localizedDescription)")
                }
            }
            listener.start(queue: queue)
        } catch {
            onStatus?("수신 시작 실패: \(error.localizedDescription)")
        }
    }

    private func observe(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.reconnectWorkItem?.cancel()
                self.reconnectWorkItem = nil
                self.onStatus?("연결됨")
                if self.role == .sender,
                   let connection,
                   let pending = self.pendingInputSource {
                    self.pendingInputSource = nil
                    self.sendNow(inputSource: pending, on: connection)
                } else if self.role == .receiver, let connection {
                    self.receive(on: connection, buffer: Data())
                }
            case .failed(let error):
                self.onStatus?("연결 실패: \(error.localizedDescription)")
                self.scheduleReconnect()
            case .cancelled:
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

    private func scheduleReconnect() {
        guard role == .sender, !isStopped, reconnectWorkItem == nil else { return }
        onStatus?("1초 후 다시 연결합니다…")
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.reconnectWorkItem = nil
            self.startSender()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }

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
