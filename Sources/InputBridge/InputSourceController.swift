import Carbon
import Foundation

enum InputSourceError: LocalizedError {
    case sourceNotFound(String)
    case selectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let id):
            return "입력 소스를 찾을 수 없습니다: \(id)"
        case .selectionFailed(let status):
            return "입력 소스 변경 실패 (OSStatus \(status))"
        }
    }
}

final class InputSourceController {
    var onChange: ((String) -> Void)?
    private var isMonitoring = false
    private var pollingTimer: Timer?
    private var lastObservedInputSourceID: String?

    func currentInputSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return property(kTISPropertyInputSourceID, of: source) as? String
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastObservedInputSourceID = currentInputSourceID()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: Notification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) {
            [weak self] _ in
            self?.emitChangeIfNeeded()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        DistributedNotificationCenter.default().removeObserver(self)
        pollingTimer?.invalidate()
        pollingTimer = nil
        lastObservedInputSourceID = nil
        isMonitoring = false
    }

    func selectInputSource(matching id: String) throws {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
        guard let source = sources.firstObject else {
            throw InputSourceError.sourceNotFound(id)
        }
        let status = TISSelectInputSource((source as! TISInputSource))
        guard status == noErr else {
            throw InputSourceError.selectionFailed(status)
        }
    }

    @objc private func inputSourceChanged() {
        emitChangeIfNeeded()
    }

    private func emitChangeIfNeeded() {
        guard let id = currentInputSourceID() else { return }
        guard id != lastObservedInputSourceID else { return }
        lastObservedInputSourceID = id
        onChange?(id)
    }

    private func property(_ key: CFString, of source: TISInputSource) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
