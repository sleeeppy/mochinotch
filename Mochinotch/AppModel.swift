import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var notch: NotchInfo = .placeholder
    private(set) var activities: [IslandActivity] = []
    private(set) var presentation: IslandPresentation = .idle
    /// 펼치기 전과 접힌 직후에는 왼쪽 귀를 숨긴다. 다 접힌 뒤에 다시 내민다.
    private var agentEarSuppressed = false
    /// 펼치기 직전, 모양은 둔 채 왼쪽 아이콘만 먼저 거둔다.
    private(set) var leftIconsHidden = false
    private var agentEarTask: Task<Void, Never>?
    private(set) var serverError: String?
    private(set) var shakeToken = 0
    private(set) var chargePulse = 0
    private(set) var notificationAccess: NotificationAccess = .starting
    private(set) var duoMessage: String?
    /// 화면 효과와 함께 노치 테두리를 지나가는 글로우.
    private(set) var edgeGlow: Double = 0
    private(set) var edgeGlowTravel: Double = 0
    private(set) var edgeGlowColor = Color.white
    var launchAtLoginError: String?

    private var featuredID: UUID?
    private var noticesSeenAt = Date.distantPast
    private var isHovering = false
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?
    /// 지우기 직후 높이를 잠깐 유지한다. 글자가 사라진 뒤에 모양이 따라 줄어든다.
    private var frozenRows: Int?
    private let power = PowerMonitor()
    private let server = EventServer()
    private let notifications = NotificationWatcher()
    private var panel: IslandPanelController?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    var featured: IslandActivity? {
        if let featuredID, let match = activities.first(where: { $0.id == featuredID }) {
            return match
        }
        return activities.first
    }

    var metrics: IslandMetrics {
        IslandMetrics.resolve(
            notch: notch,
            presentation: presentation,
            rowCount: frozenRows ?? activities.count,
            peekSlots: noticeGroups.count,
            agentSlots: agentEarSuppressed ? 0 : agentGroups.count
        )
    }

    var hoverScreenRect: CGRect {
        metrics.screenRect(notch: notch)
    }

    /// 접혀 있을 때는 노치 뒤라 클릭을 받지 않는다. 호버는 전역 모니터가 따로 본다.
    private var interactiveScreenRect: CGRect? {
        guard presentation != .idle || metrics.chrome == .peek else { return nil }
        return hoverScreenRect
    }

    /// 일반 알림. 노치 오른쪽에 개수 배지와 함께 붙는다.
    var noticeGroups: [NoticeGroup] {
        groupedNotices(agent: false)
    }

    /// 에이전트 작업 알림. 노치 왼쪽에 배지 없이 붙는다.
    var agentGroups: [NoticeGroup] {
        groupedNotices(agent: true)
    }

    /// 먼저 온 앱이 노치에 가깝다. 일반 알림은 오른쪽으로, 에이전트는 왼쪽으로 뻗는다.
    private func groupedNotices(agent: Bool) -> [NoticeGroup] {
        var groups: [NoticeGroup] = []
        let unseen = activities.filter { activity in
            guard !activity.hidesPeek else { return false }
            if agent { return activity.staysOnLeft }
            return activity.isNotice && !activity.staysOnLeft && activity.createdAt > noticesSeenAt
        }
        for activity in unseen.reversed() {
            let key = activity.iconBundleIDs.first ?? activity.leadingText
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].latest = activity
                groups[index].count += 1
            } else {
                groups.append(NoticeGroup(id: key, latest: activity, count: 1))
            }
        }
        return Array(groups.suffix(IslandMetrics.maxPeekSlots))
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func start() {
        notch = NotchGeometry.current()
        let controller = IslandPanelController(
            rootView: IslandRootView().environment(self)
        )
        controller.hoverRectProvider = { [weak self] in
            self?.hoverScreenRect ?? .zero
        }
        controller.interactiveRectProvider = { [weak self] in
            self?.interactiveScreenRect
        }
        controller.onHoverChange = { [weak self] inside in
            self?.setHover(inside)
        }
        controller.start()
        panel = controller

        power.onEvent = { [weak self] event in
            self?.handlePower(event)
        }
        power.start()

        server.onEvent = { [weak self] event in
            self?.ingest(event)
        }
        server.onFailure = { [weak self] message in
            self?.serverError = message
        }
        server.start(port: MochinotchConfig.port)

        notifications.onNotice = { [weak self] notice in
            self?.ingest(notice)
        }
        notifications.onDismiss = { [weak self] title, body in
            self?.acknowledgeStoredNotice(title: title, body: body)
        }
        notifications.onAccessChange = { [weak self] access in
            self?.notificationAccess = access
        }
        notifications.start()

        DuoPulse.shared.onStatus = { [weak self] message in
            self?.duoMessage = message
        }
        DuoPulse.shared.onGlow = { [weak self] envelope, travel, color in
            guard let self else { return }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let lift = 0.42
            self.edgeGlow = envelope
            self.edgeGlowTravel = travel
            self.edgeGlowColor = Color(
                red: rgb.redComponent + (1 - rgb.redComponent) * lift,
                green: rgb.greenComponent + (1 - rgb.greenComponent) * lift,
                blue: rgb.blueComponent + (1 - rgb.blueComponent) * lift
            )
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            Task { @MainActor in
                self?.acknowledgeAgent(bundleID: bundleID)
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notch = NotchGeometry.current()
                self?.refreshPanel()
            }
        }

        refreshPanel()
        showWelcome()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "mochinotch" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        let success = query("success").map { value in
            value != "0" && value.lowercased() != "false"
        }
        ingest(IncomingEvent(
            tool: query("tool"),
            title: query("title"),
            detail: query("detail"),
            success: success,
            kind: query("kind"),
            bundleID: query("bundleID")
        ))
    }

    func ingest(_ event: IncomingEvent) {
        let tool = AgentTool(rawValue: (event.tool ?? "custom").lowercased()) ?? .custom
        let outcome = outcome(for: event)
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(tool.displayName) \(outcome.shortLabel)"
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundles = event.bundleID.map { [$0] } ?? []
        let activity = IslandActivity(
            id: UUID(),
            payload: .agent(tool: tool, outcome: outcome, title: title, detail: detail, openBundleIDs: bundles),
            createdAt: Date(),
            keepsHistory: true
        )
        let seconds: Double
        switch outcome {
        case .needsInput: seconds = 8
        case .failed: seconds = 6.2
        case .cancelled: seconds = 3.2
        case .completed: seconds = 5.4
        }
        present(activity, seconds: seconds)
    }

    func ingest(_ notice: SystemNotice) {
        let title = [notice.title, notice.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        let activity = IslandActivity(
            id: UUID(),
            payload: .notice(
                appName: Self.appName(notice.bundleID),
                title: title.isEmpty ? Self.appName(notice.bundleID) : title,
                body: notice.body,
                bundleID: notice.bundleID
            ),
            createdAt: Date(),
            keepsHistory: true
        )
        present(activity, seconds: 0)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// 왼쪽 AI 작업만. 그 앱을 앞으로 가져오면 접힌다. 오른쪽 알림은 그대로 둔다.
    private func acknowledgeAgent(bundleID: String) {
        let indexes = activities.indices.filter { activities[$0].clearsWhenFocused(bundleID) && !activities[$0].hidesPeek }
        let foldCompact: Bool = {
            guard presentation == .compact, !isHovering, let featured else { return false }
            if case .agent(let tool, _, _, _, _) = featured.payload {
                return tool.iconBundleIDs.contains(bundleID)
            }
            return false
        }()
        guard !indexes.isEmpty || foldCompact else { return }
        withAnimation(IslandMotion.morph) {
            for index in indexes {
                activities[index].hidesPeek = true
            }
            if foldCompact {
                setPresentation(.idle)
            }
        }
    }

    /// 알림센터에서 지워진 오른쪽 알림. 왼쪽 작업 완료는 포커스로만 접힌다.
    private func acknowledgeStoredNotice(title: String, body: String) {
        let indexes = activities.indices.filter { index in
            guard !activities[index].hidesPeek, !activities[index].isAgentNotice,
                  case .notice(_, let storedTitle, let storedBody, _) = activities[index].payload else {
                return false
            }
            return storedTitle == title && storedBody == body
        }
        guard !indexes.isEmpty else { return }
        withAnimation(IslandMotion.morph) {
            for index in indexes {
                activities[index].hidesPeek = true
            }
        }
    }

    func clearHistory() {
        clearTask?.cancel()
        let rows = activities.count
        if isHovering, rows > 0 {
            frozenRows = rows
        }
        withAnimation(.easeInOut(duration: 0.32)) {
            activities.removeAll()
            featuredID = nil
        }
        if isHovering {
            refreshPanel()
            clearTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, let self else { return }
                self.frozenRows = nil
            }
        } else {
            frozenRows = nil
            setPresentation(.idle)
        }
    }

    func open(_ activity: IslandActivity) {
        for id in activity.openBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            isHovering = false
            setPresentation(.idle)
            return
        }
    }

    func expandNow() {
        hoverTask?.cancel()
        leaveTask?.cancel()
        dismissTask?.cancel()
        isHovering = true
        setPresentation(.expanded)
    }

    func simulateCharge() {
        presentPower(phase: .plugged, percent: 76, seconds: 3.6)
    }

    func simulateUnplug() {
        presentPower(phase: .unplugged, percent: 76, seconds: 2.6)
    }

    func simulateAgent(tool: AgentTool, outcome: AgentOutcome) {
        let detail: String
        switch (tool, outcome) {
        case (.claude, .completed): detail = "mochinotch · 테스트 42개 통과"
        case (.claude, .needsInput): detail = "명령 실행을 허용할까요?"
        case (.cursor, .completed): detail = "아일랜드 뷰 수정"
        case (.codex, .failed): detail = "빌드가 실패했어요"
        default: detail = tool.displayName
        }
        ingest(IncomingEvent(
            tool: tool.rawValue,
            title: "\(tool.displayName) \(outcome.shortLabel)",
            detail: detail,
            success: outcome != .failed,
            kind: kindString(outcome),
            bundleID: tool.iconBundleIDs.first
        ))
    }

    private static func duoTint(for tool: AgentTool, outcome: AgentOutcome) -> NSColor {
        if outcome == .failed {
            return NSColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 1)
        }
        switch tool {
        case .cursor, .claude, .codex:
            let rgb = tool.screenTintRGB
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        case .custom:
            return IconTint.color(for: tool)
        }
    }

    func previewDuo(_ study: DuoStudy = .focus) {
        DuoPulse.shared.play(tint: Self.duoTint(for: .cursor, outcome: .completed), study: study)
    }

    func openScreenRecordingSettings() {
        DuoPulse.shared.openSettings()
    }

    func simulateNotice() {
        let samples: [(String, String, String, String)] = [
            ("메시지", "민수", "지금 어디야?", "com.apple.MobileSMS"),
            ("캘린더", "스탠드업", "10분 뒤에 시작해요", "com.apple.iCal"),
            ("메일", "배포 리뷰", "Mochinotch 0.1 확인해 주세요", "com.apple.mail")
        ]
        let sample = samples[activities.filter {
            if case .notice = $0.payload { return true }
            return false
        }.count % samples.count]
        let activity = IslandActivity(
            id: UUID(),
            payload: .notice(appName: sample.0, title: sample.1, body: sample.2, bundleID: sample.3),
            createdAt: Date(),
            keepsHistory: true
        )
        present(activity, seconds: 0)
    }

    func runNotificationProbe() {
        let message = NotificationProbe.run()
        let alert = NSAlert()
        alert.messageText = "알림 데이터베이스 실험"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "확인")
        NSApp.activate()
        alert.runModal()
    }

    private func showWelcome() {
        let activity = IslandActivity(
            id: UUID(),
            payload: .hint(title: "もちノッチ", detail: "노치에 마우스를 올려보세요"),
            createdAt: Date(),
            keepsHistory: false
        )
        present(activity, seconds: 2.8)
    }

    private func handlePower(_ event: PowerEvent) {
        switch event {
        case .plugged(let percent):
            presentPower(phase: .plugged, percent: percent, seconds: 3.6)
        case .unplugged(let percent):
            presentPower(phase: .unplugged, percent: percent, seconds: 2.6)
        case .charged(let percent):
            presentPower(phase: .full, percent: percent, seconds: 3.4)
        case .percent(let percent):
            updatePowerPercent(percent)
        }
    }

    private func presentPower(phase: PowerPhase, percent: Int, seconds: Double) {
        if phase == .plugged || phase == .full {
            chargePulse += 1
        }
        let activity = IslandActivity(
            id: UUID(),
            payload: .power(phase: phase, percent: percent),
            createdAt: Date(),
            keepsHistory: true
        )
        present(activity, seconds: seconds)
    }

    private func updatePowerPercent(_ percent: Int) {
        guard let index = activities.firstIndex(where: { activity in
            if case .power(.plugged, _) = activity.payload { return true }
            if case .power(.full, _) = activity.payload { return true }
            return false
        }) else { return }
        let existing = activities[index]
        let phase: PowerPhase
        if case .power(let current, _) = existing.payload {
            phase = current
        } else {
            phase = .plugged
        }
        activities[index].payload = .power(phase: phase, percent: percent)
    }

    private func present(_ activity: IslandActivity, seconds: Double) {
        hoverTask?.cancel()
        leaveTask?.cancel()
        clearTask?.cancel()
        frozenRows = nil
        let keepCurrentCompact = activity.isNotice && presentation == .compact && featured?.isNotice != true
        if !keepCurrentCompact {
            dismissTask?.cancel()
        }
        activities.insert(activity, at: 0)
        activities = Array(activities.prefix(MochinotchConfig.historyLimit))
        if keepCurrentCompact {
            return
        }
        featuredID = activity.id
        if case .agent(let tool, let outcome, _, _, _) = activity.payload, tool.playsDuo, outcome != .cancelled {
            DuoPulse.shared.play(tint: Self.duoTint(for: tool, outcome: outcome))
        }
        if activity.isFailure {
            shakeToken += 1
        }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           activity.clearsWhenFocused(front),
           let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index].hidesPeek = true
        }
        if isHovering {
            setPresentation(.expanded)
        } else if activity.isNotice {
            setPresentation(.idle)
        } else {
            setPresentation(.compact)
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                if !self.isHovering, self.presentation == .compact, self.featuredID == activity.id {
                    self.setPresentation(.idle)
                }
            }
        }
    }

    private func setHover(_ hovering: Bool) {
        if hovering {
            leaveTask?.cancel()
            guard !isHovering else { return }
            isHovering = true
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: MochinotchConfig.hoverIn)
                guard !Task.isCancelled, let self, self.isHovering else { return }
                self.dismissTask?.cancel()
                self.setPresentation(.expanded)
            }
        } else {
            hoverTask?.cancel()
            guard isHovering else { return }
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: MochinotchConfig.hoverOut)
                guard !Task.isCancelled, let self else { return }
                self.isHovering = false
                if self.presentation == .expanded {
                    self.setPresentation(.idle)
                }
            }
        }
    }

    private func setPresentation(_ next: IslandPresentation) {
        agentEarTask?.cancel()
        let hasLeft = !agentGroups.isEmpty
        if presentation == .idle, hasLeft, next != .idle {
            leftIconsHidden = true
            agentEarTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, let self else { return }
                self.commitPresentation(next)
            }
            return
        }
        if next == .idle, presentation == .idle, leftIconsHidden, hasLeft {
            leftIconsHidden = false
            agentEarSuppressed = false
            commitPresentation(.idle)
            return
        }
        if next == .idle, hasLeft, presentation != .idle {
            agentEarSuppressed = true
            leftIconsHidden = true
            commitPresentation(.idle)
            agentEarTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled, let self, self.presentation == .idle, !self.agentGroups.isEmpty else { return }
                self.agentEarSuppressed = false
                self.leftIconsHidden = false
            }
            return
        }
        if !hasLeft {
            agentEarSuppressed = false
            leftIconsHidden = false
        }
        commitPresentation(next)
    }

    private func commitPresentation(_ next: IslandPresentation) {
        if presentation == .expanded, next != .expanded {
            noticesSeenAt = Date()
            clearTask?.cancel()
            frozenRows = nil
        }
        presentation = next
        if next == .idle {
            activities.removeAll { !$0.keepsHistory }
            if !activities.contains(where: { $0.id == featuredID }) {
                featuredID = activities.first?.id
            }
        }
        refreshPanel()
    }

    private func refreshPanel() {
        panel?.place(frame: IslandMetrics.canvas(notch: notch))
    }

    private func outcome(for event: IncomingEvent) -> AgentOutcome {
        switch event.kind?.lowercased() {
        case "failed", "failure", "error":
            return .failed
        case "needsinput", "needs_input", "permission":
            return .needsInput
        case "cancelled", "canceled", "aborted":
            return .cancelled
        default:
            return event.success == false ? .failed : .completed
        }
    }

    private func kindString(_ outcome: AgentOutcome) -> String {
        switch outcome {
        case .completed: return "completed"
        case .failed: return "failed"
        case .needsInput: return "needsInput"
        case .cancelled: return "cancelled"
        }
    }
}

struct NoticeGroup: Identifiable, Equatable {
    /// 앱 번들 ID.
    let id: String
    var latest: IslandActivity
    var count: Int
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
