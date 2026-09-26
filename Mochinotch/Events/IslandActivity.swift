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
            return ["com.todesktop.230313mzl4w4tx"]
        case .claude:
            return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .codex:
            return ["com.openai.codex"]
        case .custom:
            return []
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

    var isFailure: Bool {
        if case .agent(_, .failed, _, _, _) = payload { return true }
        return false
    }

    var isNotice: Bool {
        if case .notice = payload { return true }
        return false
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
        case .agent(let tool, let outcome, let title, _, _):
            let name = title.isEmpty ? tool.displayName : title
            return name
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
        case .agent(let tool, let outcome, _, let detail, _):
            if detail.isEmpty {
                return "\(tool.displayName) · \(outcome.shortLabel)"
            }
            return detail
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
            return tool.tint
        case .notice:
            return Color.white
        }
    }

    var iconBundleIDs: [String] {
        switch payload {
        case .agent(let tool, _, _, _, _):
            return tool.iconBundleIDs
        case .notice(_, _, _, let bundleID):
            return bundleID.map { [$0] } ?? []
        default:
            return []
        }
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
        case .agent, .notice:
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
