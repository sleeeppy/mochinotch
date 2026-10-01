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

enum AgentLinkProgress: Equatable {
    case idle
    case working(String)
    case done(String)
    case failed(String)
}

/// 처음 켰을 때 인트로 뒤에 펼쳐지는 안내. 권한 창을 오가는 동안 접히지 않는다.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.setupStatus
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("초기 권한 설정")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandColor.primary)
                Text("켜 두면 알림과 작업 완료를 노치가 바로 보여 줘요. 켠 항목은 저절로 체크돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsCard {
                SettingsRow(
                    title: "알림 읽기",
                    subtitle: status.notifications
                        ? "다른 앱 알림이 노치에 떠요"
                        : "전체 디스크 접근 권한 · 목록에 없으면 +로 추가"
                ) {
                    SetupAction(done: status.notifications, title: "허용") {
                        model.openFullDiskAccessSettings()
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "손쉬운 사용",
                    subtitle: status.accessibility
                        ? "알림을 바로 읽고, 읽은 알림은 거둬요"
                        : "앱과 터미널 hook이 같이 써요. 요청 창이 떠요"
                ) {
                    SetupAction(done: status.accessibility, title: "허용") {
                        model.requestAccessibility()
                    }
                }
                SettingsDivider()
                SettingsRow(title: "화면 기록", subtitle: screenSubtitle(status)) {
                    SetupAction(done: status.screenRecording, title: "허용") {
                        model.requestScreenRecording()
                    }
                }
                SettingsDivider()
                SettingsRow(title: "AI 에이전트 연결", subtitle: agentSubtitle(status)) {
                    agentAction(status)
                }
            }

            HStack(spacing: 8) {
                if model.requestedScreenRecording, !status.screenRecording {
                    SetupPill(title: "다시 켜기", tint: IslandColor.warning, filled: false) {
                        model.relaunch()
                    }
                    .transition(.opacity)
                } else if status.remaining > 0 {
                    Text("\(status.remaining)개 남았어요")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .contentTransition(.numericText())
                }
                Spacer()
                if status.remaining == 0 {
                    SetupPill(title: "시작하기", tint: IslandColor.charge, filled: true) {
                        model.finishSetup()
                    }
                } else {
                    SetupPill(title: "나중에", tint: IslandColor.secondary, filled: false) {
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
        if status.screenRecording { return "작업이 끝나면 화면 가장자리까지 빛나요" }
        if model.requestedScreenRecording { return "켰다면 아래 다시 켜기를 눌러야 적용돼요" }
        return "작업이 끝날 때 화면 가장자리 연출에만 써요"
    }

    private func agentSubtitle(_ status: SetupStatus) -> String {
        switch model.agentLinkProgress {
        case .working(let message): return message
        case .failed(let message): return message
        case .done(let message) where status.agents.ready: return message
        default: break
        }
        if !status.movedFromDownloads { return "앱을 응용 프로그램 폴더로 옮긴 뒤 연결할 수 있어요" }
        let present = status.agents.present
        if present.isEmpty { return "Claude Code · Cursor · Codex · Kiro를 찾지 못했어요" }
        let names = present.map(\.displayName).joined(separator: " · ")
        if status.agents.ready { return "\(names) 연결됨" }
        return "\(names)\n켜 둔 앱은 연결한 뒤 다시 켜져요"
    }

    @ViewBuilder
    private func agentAction(_ status: SetupStatus) -> some View {
        if case .working = model.agentLinkProgress {
            SetupSpinner()
                .frame(width: 44, height: 22)
        } else if status.agents.present.isEmpty || !status.movedFromDownloads {
            Image(systemName: "minus.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 44, height: 22)
        } else {
            SetupAction(done: status.agents.ready, title: "연결") {
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
