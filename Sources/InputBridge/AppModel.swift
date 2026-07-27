import Foundation
import AppKit

enum SyncRole: String, CaseIterable, Identifiable {
    case sender
    case receiver

    var id: Self { self }
    var title: String { self == .sender ? "대상 Mac" : "조작 Mac" }
    var explanation: String {
        self == .sender
            ? "Screen Sharing 대상: 입력 소스 변경을 조작 Mac으로 보냅니다."
            : "키보드를 사용하는 Mac: 대상 Mac의 입력 소스 변경을 받습니다."
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var role: SyncRole = .sender
    @Published var host = "127.0.0.1"
    @Published var port: UInt16 = 45831
    @Published var sharedSecret = ""
    @Published var useKoreanMapping = true
    @Published private(set) var isRunning = false
    @Published private(set) var status = "중지됨"

    private let inputSources = InputSourceController()
    private var transport: SyncTransport?

    func toggle() {
        isRunning ? stop() : start()
    }

    func quit() {
        if isRunning {
            stop()
        }
        NSApplication.shared.terminate(nil)
    }

    private func start() {
        guard !sharedSecret.isEmpty else {
            status = "공유 키를 입력하세요."
            return
        }

        let mapper = InputSourceMapper(useKoreanDefaults: useKoreanMapping)
        let transport = SyncTransport(
            role: role,
            host: host,
            port: port,
            sharedSecret: sharedSecret
        )

        transport.onStatus = { [weak self] message in
            Task { @MainActor in self?.status = message }
        }
        transport.onInputSource = { [weak self] source in
            guard let self else { return }
            Task { @MainActor in
                let mapped = mapper.destinationID(for: source)
                do {
                    try self.inputSources.selectInputSource(matching: mapped)
                    self.status = "적용: \(mapped)"
                } catch {
                    self.status = error.localizedDescription
                }
            }
        }

        if role == .sender {
            inputSources.onChange = { [weak transport] source in
                Task { @MainActor [weak self] in
                    self?.status = "감지 및 전송: \(source)"
                }
                transport?.send(inputSource: mapper.portableID(for: source))
            }
            inputSources.startMonitoring()
            if let current = inputSources.currentInputSourceID() {
                transport.send(inputSource: mapper.portableID(for: current))
            }
        }

        self.transport = transport
        transport.start()
        isRunning = true
        status = role == .sender ? "원격 Mac에 연결 중…" : "연결 대기 중…"
    }

    private func stop() {
        inputSources.stopMonitoring()
        transport?.stop()
        transport = nil
        isRunning = false
        status = "중지됨"
    }
}
