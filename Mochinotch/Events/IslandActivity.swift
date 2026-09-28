import SwiftUI

enum IslandPresentation: Equatable {
    case idle
    case compact
    case expanded
}

enum AgentTool: String, Equatable {
    case claude
    case cursor
    case codex
    case custom

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .custom: return "작업"
        }
    }

    var iconBundleIDs: [String] {
        switch self {
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .claude:
            return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .codex:
            return ["com.openai.codex"]
        case .custom:
            return []
        }
    }

    /// 펼친 목록 제목. 좁은 귀에는 `displayName`을 쓴다.
    var appTitle: String {
        self == .claude ? "Claude Code" : displayName
    }

    /// 번들 ID가 바뀌었을 때 `/Applications`에서 찾을 이름.
    var appNames: [String] {
        switch self {
        case .cursor: return ["Cursor"]
        case .claude: return ["Claude"]
        case .codex: return ["Codex"]
        case .custom: return []
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .claude: return "sparkle"
        case .cursor: return "cursorarrow.rays"
        case .codex: return "terminal.fill"
        case .custom: return "app.fill"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return IslandColor.claude
        case .cursor: return IslandColor.cursor
        case .codex: return IslandColor.codex
        case .custom: return Color.white.opacity(0.85)
        }
    }

    /// 화면 가장자리와 왼쪽 오라에 쓰는 색.
    var screenTintRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .cursor: return (0.34, 0.35, 0.37)
        case .claude: return (0.95, 0.45, 0.27)
        case .codex: return (1, 1, 1)
        case .custom: return (1, 1, 1)
        }
    }

    /// 이 앱에서 온 시스템 알림은 일반 알림이 아니라 작업 완료로 본다.
    static let noticeBundleIDs: Set<String> = Set(
        [AgentTool.cursor, .claude, .codex].flatMap(\.iconBundleIDs)
    )

    /// 화면 가장자리 왜곡은 이 세 도구에만 쓴다.
    var playsDuo: Bool {
        switch self {
        case .claude, .cursor, .codex: return true
        case .custom: return false
        }
    }
}

enum AgentOutcome: Equatable {
    case completed
    case failed
    case needsInput
    case cancelled

    var shortLabel: String {
        switch self {
        case .completed: return "완료"
        case .failed: return "실패"
        case .needsInput: return "확인"
        case .cancelled: return "중단"
        }
    }

    var detailLabel: String {
        switch self {
        case .completed: return "작업 완료"
        case .failed: return "작업 실패"
        case .needsInput: return "확인 필요"
        case .cancelled: return "작업 중단"
        }
    }

    var tint: Color {
        switch self {
        case .completed: return IslandColor.charge
        case .failed: return IslandColor.danger
        case .needsInput: return IslandColor.warning
        case .cancelled: return IslandColor.secondary
        }
    }
}

enum ActivityPayload: Equatable {
    case hint(title: String, detail: String)
    case power(phase: PowerPhase, percent: Int)
    case agent(tool: AgentTool, outcome: AgentOutcome, title: String, detail: String, openBundleIDs: [String])
    /// 노치 오른쪽의 작은 원. 자세한 내용은 펼친 목록에서 본다.
    case notice(appName: String, title: String, body: String, bundleID: String?)
}

enum PowerPhase: Equatable {
    case plugged
    case unplugged
    case full
}

struct IslandActivity: Identifiable, Equatable {
    let id: UUID
    var payload: ActivityPayload
    var createdAt: Date
    var keepsHistory: Bool
    /// 접힌 노치에는 더 보여 주지 않는다. 오른쪽은 알림센터에서 지웠을 때, 왼쪽은 그 앱을 포커스했을 때.
    var hidesPeek = false

    /// 왼쪽 작업 완료. 시스템 알림이거나, Cursor·Claude·Codex 작업이 끝난 경우.
    var staysOnLeft: Bool {
        if isAgentNotice { return true }
        if case .agent(let tool, let outcome, _, _, _) = payload {
            return tool.playsDuo && outcome != .cancelled
        }
        return false
    }

    /// 왼쪽 작업 완료. 이 앱을 앞으로 가져오면 접힌다.
    func clearsWhenFocused(_ bundleID: String) -> Bool {
        guard staysOnLeft else { return false }
        if case .agent(let tool, _, _, _, _) = payload, tool.iconBundleIDs.contains(bundleID) { return true }
        if iconBundleIDs.contains(bundleID) { return true }
        let tools: [AgentTool] = [.cursor, .claude, .codex]
        guard let tool = tools.first(where: { $0.iconBundleIDs.contains(bundleID) }) else { return false }
        if tool.iconBundleIDs.contains(where: iconBundleIDs.contains) { return true }
        return tool.appNames.contains { $0.caseInsensitiveCompare(leadingText) == .orderedSame }
    }

    var isFailure: Bool {
        if case .agent(_, .failed, _, _, _) = payload { return true }
        return false
    }

    var isNotice: Bool {
        if case .notice = payload { return true }
        return false
    }

    /// Cursor, Claude, Codex 알림. 오른쪽 개수 배지 대신 노치 왼쪽에 아이콘만 둔다.
    var isAgentNotice: Bool {
        guard case .notice(let appName, _, _, let bundleID) = payload else { return false }
        if let bundleID, AgentTool.noticeBundleIDs.contains(bundleID) { return true }
        switch appName.lowercased() {
        case "cursor", "claude", "claude code", "codex": return true
        default: return false
        }
    }

    /// 완료 연출의 왼쪽 아이콘. 접힌 왼쪽 대기 아이콘과는 따로다.
    var compactIconSize: CGFloat {
        if case .agent = payload { return 22 }
        return 18
    }

    var leadingText: String {
        switch payload {
        case .hint(let title, _):
            return title
        case .power(let phase, _):
            switch phase {
            case .plugged: return "충전"
            case .unplugged: return "분리"
            case .full: return "완충"
            }
        case .agent(let tool, _, _, _, _):
            return tool.displayName
        case .notice(let appName, _, _, _):
            return appName
        }
    }

    var trailingText: String {
        switch payload {
        case .hint:
            return ""
        case .power(_, let percent):
            return "\(percent)%"
        case .agent(_, let outcome, _, _, _):
            return outcome.shortLabel
        case .notice:
            return "알림"
        }
    }

    var expandedTitle: String {
        switch payload {
        case .hint(let title, _):
            return title
        case .power(let phase, let percent):
            switch phase {
            case .plugged: return "충전 중 · \(percent)%"
            case .unplugged: return "충전기 분리 · \(percent)%"
            case .full: return "완충 · \(percent)%"
            }
        case .agent(let tool, _, let title, _, _):
            // 알려진 도구는 앱 이름만. 결과는 아래 줄과 색으로 보인다.
            if tool != .custom || title.isEmpty { return tool.appTitle }
            return title
        case .notice(_, let title, _, _):
            return title
        }
    }

    var expandedDetail: String {
        switch payload {
        case .hint(_, let detail):
            return detail
        case .power(let phase, _):
            switch phase {
            case .plugged: return "전원이 연결됐어요"
            case .unplugged: return "배터리로 전환됐어요"
            case .full: return "배터리가 가득 찼어요"
            }
        case .agent(_, let outcome, _, let detail, _):
            if detail.isEmpty {
                return outcome.detailLabel
            }
            if outcome == .completed {
                return detail
            }
            return "\(outcome.detailLabel) · \(detail)"
        case .notice(let appName, _, let body, _):
            return body.isEmpty ? appName : body
        }
    }

    var symbol: String {
        switch payload {
        case .hint:
            return "sparkles"
        case .power(let phase, _):
            switch phase {
            case .plugged: return "bolt.fill"
            case .unplugged: return "bolt.slash.fill"
            case .full: return "battery.100percent"
            }
        case .agent(let tool, _, _, _, _):
            return tool.fallbackSymbol
        case .notice:
            return "bell.fill"
        }
    }

    var tint: Color {
        switch payload {
        case .hint:
            return Color.white
        case .power(let phase, _):
            switch phase {
            case .plugged, .full: return IslandColor.charge
            case .unplugged: return IslandColor.secondary
            }
        case .agent(let tool, let outcome, _, _, _):
            if outcome == .failed { return IslandColor.danger }
            if outcome == .needsInput { return IslandColor.warning }
            if tool == .cursor, outcome == .completed {
                return Color(red: 0.73, green: 0.74, blue: 0.76)
            }
            return tool.tint
        case .notice:
            return Color.white
        }
    }

    var iconBundleIDs: [String] {
        switch payload {
        case .hint:
            return [Bundle.main.bundleIdentifier].compactMap { $0 }
        case .agent(let tool, _, _, _, _):
            return tool.iconBundleIDs
        case .notice(_, _, _, let bundleID):
            return bundleID.map { [$0] } ?? []
        default:
            return []
        }
    }

    /// 왼쪽 오라. 그 앱의 화면 틴트와 같은 색이다.
    var peekAura: Color {
        let tool: AgentTool? = {
            if case .agent(let tool, _, _, _, _) = payload { return tool }
            if case .notice(let appName, _, _, let bundleID) = payload {
                if let bundleID, let match = Self.agentTool(bundleID: bundleID) { return match }
                return Self.agentTool(name: appName)
            }
            return nil
        }()
        guard let tool else { return Color.white.opacity(0.7) }
        let rgb = tool.screenTintRGB
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private static func agentTool(bundleID: String) -> AgentTool? {
        [AgentTool.cursor, .claude, .codex].first { $0.iconBundleIDs.contains(bundleID) }
    }

    private static func agentTool(name: String) -> AgentTool? {
        switch name.lowercased() {
        case "cursor": return .cursor
        case "claude", "claude code": return .claude
        case "codex": return .codex
        default: return nil
        }
    }

    var iconAppNames: [String] {
        if case .agent(let tool, _, _, _, _) = payload { return tool.appNames }
        return []
    }

    var openBundleIDs: [String] {
        switch payload {
        case .agent(let tool, _, _, _, let openIDs):
            var ids = openIDs
            ids.append(contentsOf: tool.iconBundleIDs)
            return unique(ids)
        case .notice(_, _, _, let bundleID):
            return bundleID.map { [$0] } ?? []
        default:
            return []
        }
    }

    var showsAppIcon: Bool {
        switch payload {
        case .hint, .agent, .notice:
            return true
        default:
            return false
        }
    }

    var percent: Int? {
        if case .power(_, let percent) = payload { return percent }
        return nil
    }
}

private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0).inserted }
}
