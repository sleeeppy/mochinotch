import AppKit
import SwiftUI

struct MenuContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("もちノッチ")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 8)

        if let serverError = model.serverError {
            Text("이벤트 수신 실패 · \(serverError)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
        } else {
            Text("127.0.0.1:\(MochinotchConfig.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }

        Text(model.notificationAccess.label)
            .font(.caption)
            .foregroundStyle(model.notificationAccess == .watching ? Color.secondary : Color.orange)
            .padding(.horizontal, 12)
        if model.notificationAccess == .denied {
            Button("전체 디스크 접근 권한 열기…") { model.openFullDiskAccessSettings() }
        }

        Divider()

        ForEach(IntroStudy.allCases, id: \.self) { study in
            Button(study.title) { model.previewIntro(study) }
        }
        Button("충전 연결 테스트") { model.simulateCharge() }
        Button("충전 해제 테스트") { model.simulateUnplug() }
        Button("Claude Code 완료 테스트") { model.simulateAgent(tool: .claude, outcome: .completed) }
        Button("Cursor 완료 테스트") { model.simulateAgent(tool: .cursor, outcome: .completed) }
        Button("Codex 완료 테스트") { model.simulateAgent(tool: .codex, outcome: .completed) }
        Button("알림 미리보기") { model.simulateNotice() }
        if let duoMessage = model.duoMessage {
            Text(duoMessage)
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
            Button("화면 기록 설정 열기…") { model.openScreenRecordingSettings() }
        }

        Divider()

        Button("알림 데이터베이스 실험…") { model.runNotificationProbe() }
        Button("기록 지우기") { model.clearHistory() }
        Button("설정…") { openSettings() }

        Divider()

        Button("종료") { NSApp.terminate(nil) }
    }

    private func openSettings() {
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("버전", value: "0.1.0")
                LabeledContent("이벤트", value: "http://127.0.0.1:\(MochinotchConfig.port)/event")
                Toggle("로그인할 때 열기", isOn: launchBinding)
                if let launchAtLoginError = model.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("もちノッチ")
            } footer: {
                Text("노치에 마우스를 올리면 쌓인 항목이 펼쳐져요. 항목을 누르면 그 앱으로 이동해요. 시스템 알림을 받으려면 전체 디스크 접근 권한에 Mochinotch를 넣어 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}

private extension NotificationAccess {
    var label: String {
        switch self {
        case .starting: return "시스템 알림 · 확인 중"
        case .watching: return "시스템 알림 · 받는 중"
        case .missingDatabase: return "시스템 알림 · 데이터베이스 없음"
        case .denied: return "시스템 알림 · 전체 디스크 접근 권한 필요"
        case .failed(let message): return "시스템 알림 · 읽기 실패 (\(message))"
        }
    }
}
