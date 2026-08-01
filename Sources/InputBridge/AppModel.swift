import Foundation
import AppKit

enum SyncRole: String, CaseIterable, Identifiable {
    case sender
    case receiver

    var id: Self { self }
    var title: String { self == .sender ? "대상 Mac" : "조작 Mac" }
}

enum SyncConnectionMode: String, CaseIterable, Identifiable {
    case automatic
    case legacy

    var id: Self { self }
    var title: String { self == .automatic ? "자동 (권장)" : "기존 방식" }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var role: SyncRole = .sender
    @Published var connectionMode: SyncConnectionMode = .automatic
    @Published var host = ""
    @Published var port: UInt16 = 45831
    @Published var sharedSecret = ""
    @Published var useKoreanMapping = true
    @Published private(set) var isRunning = false
    @Published private(set) var status = "중지됨"
    @Published private(set) var detectedScreenSharingHost: String?
    @Published private(set) var isSearchingScreenSharingHost = false
    @Published private(set) var screenSharingSearchMessage: String?
    @Published private(set) var isSearchingInputBridgePort = false
    @Published private(set) var portSearchMessage: String?

    private let inputSources = InputSourceController()
    private let peerDetector = ScreenSharingPeerDetector()
    private let portScanner = InputBridgePortScanner()
    private var transport: SyncTransport?

    var showsHostField: Bool {
        switch (connectionMode, role) {
        case (.automatic, .receiver), (.legacy, .sender):
            return true
        case (.automatic, .sender), (.legacy, .receiver):
            return false
        }
    }

    var hostFieldPrompt: String {
        role == .receiver ? "대상 Mac 주소 또는 이름" : "조작 Mac 주소 또는 이름"
    }

    var peerSearchTitle: String {
        role == .receiver ? "Screen Sharing 대상 찾기" : "Screen Sharing 접속자 찾기"
    }

    var roleExplanation: String {
        switch (connectionMode, role) {
        case (.automatic, .sender):
            return "Screen Sharing 대상: 조작 Mac의 연결을 받아 입력 소스 변경을 보냅니다."
        case (.automatic, .receiver):
            return "키보드를 사용하는 Mac: Screen Sharing 대상에 연결해 변경을 받습니다."
        case (.legacy, .sender):
            return "Screen Sharing 대상: 조작 Mac에 연결해 입력 소스 변경을 보냅니다."
        case (.legacy, .receiver):
            return "키보드를 사용하는 Mac: 대상 Mac의 연결을 받아 변경을 받습니다."
        }
    }

    var waitingTitle: String {
        role == .sender ? "조작 Mac의 연결을 기다립니다." : "대상 Mac의 연결을 기다립니다."
    }

    var canSearchInputBridgePort: Bool {
        role == .receiver
            && connectionMode == .automatic
            && !isRunning
            && !isSearchingInputBridgePort
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func quit() {
        if isRunning {
            stop()
        }
        NSApplication.shared.terminate(nil)
    }

    func searchScreenSharingPeer() {
        guard showsHostField, !isRunning, !isSearchingScreenSharingHost else { return }

        isSearchingScreenSharingHost = true
        detectedScreenSharingHost = nil
        screenSharingSearchMessage = nil

        let detector = peerDetector
        let direction: ScreenSharingConnectionDirection = role == .receiver
            ? .outgoing
            : .incoming
        Task.detached(priority: .utility) {
            let detectedHost = detector.detect(direction: direction)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSearchingScreenSharingHost = false
                self.detectedScreenSharingHost = detectedHost
                self.screenSharingSearchMessage = detectedHost == nil
                    ? "현재 역할에 맞는 Screen Sharing 연결을 찾지 못했습니다."
                    : nil
            }
        }
    }

    func confirmDetectedScreenSharingHost() {
        guard !isRunning, let detectedHost = detectedScreenSharingHost else { return }
        host = detectedHost
        self.detectedScreenSharingHost = nil
        screenSharingSearchMessage = "주소를 적용했습니다."
    }

    func dismissDetectedScreenSharingHost() {
        guard !isRunning else { return }
        detectedScreenSharingHost = nil
        screenSharingSearchMessage = nil
    }

    func searchInputBridgePort() {
        guard canSearchInputBridgePort else { return }

        let targetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchingInputBridgePort = true
        portSearchMessage = nil

        let scanner = portScanner
        Task.detached(priority: .utility) {
            let result = scanner.scan(host: targetHost)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSearchingInputBridgePort = false
                switch result {
                case .found(let detectedPort):
                    self.port = detectedPort
                    self.portSearchMessage = "InputBridge 포트 \(detectedPort)을(를) 적용했습니다."
                case .notFound:
                    self.portSearchMessage = "실행 중인 InputBridge 포트를 찾지 못했습니다."
                case .multiple(let ports):
                    let values = ports.map(String.init).joined(separator: ", ")
                    self.portSearchMessage = "열린 후보가 여러 개입니다: \(values)"
                }
            }
        }
    }

    private func start() {
        guard !sharedSecret.isEmpty else {
            status = "공유 키를 입력하세요."
            return
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !showsHostField || !trimmedHost.isEmpty else {
            status = "\(hostFieldPrompt)을 입력하거나 검색하세요."
            return
        }

        let mapper = InputSourceMapper(useKoreanDefaults: useKoreanMapping)
        let transport = SyncTransport(
            role: role,
            mode: connectionMode,
            host: trimmedHost,
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

        self.transport = transport
        transport.start()

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

            if connectionMode == .automatic {
                discoverLegacyFallback(for: transport)
            }
        }

        isRunning = true
        if connectionMode == .automatic {
            status = role == .sender ? "조작 Mac 연결 대기 중…" : "대상 Mac에 연결 중…"
        } else {
            status = role == .sender ? "조작 Mac에 연결 중…" : "연결 대기 중…"
        }
    }

    private func discoverLegacyFallback(for transport: SyncTransport) {
        let detector = peerDetector
        Task.detached(priority: .utility) {
            guard let host = detector.detect(direction: .incoming) else { return }
            transport.connectLegacyFallback(to: host)
        }
    }

    private func stop() {
        inputSources.stopMonitoring()
        transport?.stop()
        transport = nil
        isRunning = false
        status = "중지됨"
    }
}
