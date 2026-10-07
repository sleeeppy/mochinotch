import SwiftUI

struct SetupStatus: Equatable {
    var notifications = false
    var accessibility = false
    var screenRecording = false
    var agents = AgentLinkStatus()
    /// 다운로드 폴더에서 바로 연 앱은 hook을 넣을 수 없다.
    var movedFromDownloads = true

    /// AI 도구가 하나도 없으면 연결은 할 일에서 뺀다.
    var agentsDone: Bool {
        agents.ready || agents.present.isEmpty
    }

    var remaining: Int {
        [notifications, accessibility, screenRecording, agentsDone].filter { !$0 }.count
    }
}

/// 연결이 어디쯤인지. 문구는 그릴 때 지금 언어로 만든다.
enum AgentLinkProgress: Equatable {
    case idle
    case connecting
    case restarting(String)
    case failed(tool: String, problem: HookProblem)
    case done(AgentLinkResult)

    var isWorking: Bool {
        switch self {
        case .connecting, .restarting: return true
        default: return false
        }
    }
}

struct AgentLinkResult: Equatable {
    var restarted: [String] = []
    var stuck: [String] = []
    var already = false
    var connected = false
    var terminal = false

    func summary(in language: AppLanguage) -> String {
        var notes: [String] = []
        if already {
            notes.append(L10n.text(.alreadyLinked, language))
        } else if !restarted.isEmpty {
            notes.append(L10n.text(.restartedApps, language, restarted.joined(separator: ", ")))
        } else if stuck.isEmpty {
            notes.append(L10n.text(.linked, language))
        }
        if !stuck.isEmpty {
            notes.append(L10n.text(.restartManually, language, stuck.joined(separator: ", ")))
        }
        if terminal {
            notes.append(L10n.text(.terminalNext, language))
        }
        return notes.joined(separator: " · ")
    }
}

/// 처음 켰을 때 인트로 뒤에 펼쳐지는 안내. 권한 창을 오가는 동안 접히지 않는다.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.setupStatus
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.text(.setupTitle))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandColor.primary)
                Text(model.text(.setupBody))
                    .font(.system(size: 11))
                    .foregroundStyle(IslandColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsCard {
                SettingsRow(
                    title: model.text(.permNotifications),
                    subtitle: status.notifications
                        ? model.text(.permNotificationsOn)
                        : model.text(.permNotificationsOff)
                ) {
                    SetupAction(done: status.notifications, title: model.text(.allow)) {
                        model.openFullDiskAccessSettings()
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: model.text(.permAccessibility),
                    subtitle: status.accessibility
                        ? model.text(.permAccessibilityOn)
                        : model.text(.permAccessibilityOff)
                ) {
                    SetupAction(done: status.accessibility, title: model.text(.allow)) {
                        model.requestAccessibility()
                    }
                }
                SettingsDivider()
                SettingsRow(title: model.text(.permScreen), subtitle: screenSubtitle(status)) {
                    SetupAction(done: status.screenRecording, title: model.text(.allow)) {
                        model.requestScreenRecording()
                    }
                }
                SettingsDivider()
                SettingsRow(title: model.text(.agentsTitle), subtitle: agentSubtitle(status)) {
                    agentAction(status)
                }
            }

            HStack(spacing: 8) {
                if model.requestedScreenRecording, !status.screenRecording {
                    SetupPill(title: model.text(.relaunch), tint: IslandColor.warning, filled: false) {
                        model.relaunch()
                    }
                    .transition(.opacity)
                } else if status.remaining > 0 {
                    Text(model.text(.remaining, status.remaining))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .contentTransition(.numericText())
                }
                Spacer()
                if status.remaining == 0 {
                    SetupPill(title: model.text(.start), tint: IslandColor.charge, filled: true) {
                        model.finishSetup()
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .animation(.easeInOut(duration: 0.22), value: status.remaining)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SettingsHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(SettingsHeightKey.self) { height in
            model.setSettingsHeight(height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func screenSubtitle(_ status: SetupStatus) -> String {
        if status.screenRecording { return model.text(.permScreenOn) }
        if model.requestedScreenRecording { return model.text(.permScreenPending) }
        return model.text(.permScreenOff)
    }

    private func agentSubtitle(_ status: SetupStatus) -> String {
        switch model.agentLinkProgress {
        case .connecting: return model.text(.connecting)
        case .restarting(let name): return model.text(.restarting, name)
        case .failed(let tool, let problem): return "\(tool) · \(problem.text(in: model.language))"
        case .done(let result) where status.agents.ready: return result.summary(in: model.language)
        default: break
        }
        if !status.movedFromDownloads { return model.text(.agentsMove) }
        let present = status.agents.present
        if present.isEmpty { return model.text(.agentsMissing) }
        let names = present.map(\.displayName).joined(separator: " · ")
        if status.agents.ready { return model.text(.agentsConnected, names) }
        return model.text(.agentsWillRestart, names)
    }

    @ViewBuilder
    private func agentAction(_ status: SetupStatus) -> some View {
        if model.agentLinkProgress.isWorking {
            SetupSpinner()
                .frame(width: 44, height: 22)
        } else if status.agents.present.isEmpty || !status.movedFromDownloads {
            Image(systemName: "minus.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 44, height: 22)
        } else {
            SetupAction(done: status.agents.ready, title: model.text(.connect)) {
                model.connectAgents()
            }
        }
    }
}

/// 켜진 항목은 초록 체크, 아니면 누르는 버튼.
private struct SetupAction: View {
    var done: Bool
    var title: String
    var action: () -> Void

    var body: some View {
        ZStack {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IslandColor.charge)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                SetupPill(title: title, tint: IslandColor.warning, filled: false, action: action)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: done)
    }
}

private struct SetupPill: View {
    var title: String
    var tint: Color
    var filled: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(filled ? Color.black : tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(filled ? tint.opacity(hovered ? 0.85 : 1) : tint.opacity(hovered ? 0.24 : 0.15))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct SetupSpinner: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 1)
            .stroke(IslandColor.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}
