import AppKit
import SwiftUI

@main
struct InputBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .frame(width: 340)
                .padding()
        } label: {
            Image(systemName: model.isRunning ? "keyboard.badge.ellipsis" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Settings {
            MenuContent(model: model)
                .frame(width: 420)
                .padding(24)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("InputBridge")
                .font(.title2.bold())

            Picker("역할", selection: $model.role) {
                ForEach(SyncRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)

            Text(model.role.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.role == .sender {
                TextField("조작 Mac 주소 또는 이름", text: $model.host)
            }

            TextField("포트", value: $model.port, format: .number)
            SecureField("공유 키", text: $model.sharedSecret)

            Toggle("ABC ↔ 한글(2벌식) 기본 매핑", isOn: $model.useKoreanMapping)
                .disabled(model.isRunning)

            HStack {
                Circle()
                    .fill(model.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }

            Button(model.isRunning ? "중지" : "시작") {
                model.toggle()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)

            Divider()

            Button("InputBridge 종료", role: .destructive) {
                model.quit()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .textFieldStyle(.roundedBorder)
    }
}
