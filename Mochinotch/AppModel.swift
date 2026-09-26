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
    private(set) var serverError: String?
    private(set) var shakeToken = 0
    private(set) var chargePulse = 0
    var launchAtLoginError: String?

    private var featuredID: UUID?
    private var isHovering = false
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private let power = PowerMonitor()
    private let server = EventServer()
    private var panel: IslandPanelController?
    private var screenObserver: NSObjectProtocol?

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
            rowCount: activities.count,
            badge: badgeActivity != nil
        )
    }

    /// 노치 본체와 오른쪽 뱃지를 함께 호버 영역으로 잡는다.
    var hoverScreenRect: CGRect {
        let visible = metrics.screenRect(notch: notch)
        guard metrics.chrome == .badge else { return visible }
        let plate = IslandMetrics
            .resolve(notch: notch, presentation: .idle, rowCount: 0, badge: false)
            .screenRect(notch: notch)
        return visible.union(plate)
    }

    /// 충전·작업 표시 중이 아닐 때, 가장 최근 알림을 오른쪽 원으로 보여 준다.
    var badgeActivity: IslandActivity? {
        if presentation == .expanded { return nil }
        if presentation == .compact, featured?.isNotice != true { return nil }
        return activities.first(where: \.isNotice)
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

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notch = NotchGeometry.current()
                self?.refreshPanel(animated: false)
            }
        }

        refreshPanel(animated: false)
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

    func clearHistory() {
        let badge = metrics.chrome == .badge
        activities.removeAll()
        featuredID = nil
        if isHovering {
            refreshPanel(animated: true)
        } else {
            setPresentation(.idle, animated: !badge)
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
        if activity.isFailure {
            shakeToken += 1
        }
        if isHovering {
            setPresentation(.expanded)
        } else if activity.isNotice {
            setPresentation(.idle, animated: false)
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

    private func setPresentation(_ next: IslandPresentation, animated: Bool = true) {
        presentation = next
        if next == .idle {
            activities.removeAll { !$0.keepsHistory }
            if !activities.contains(where: { $0.id == featuredID }) {
                featuredID = activities.first?.id
            }
        }
        refreshPanel(animated: animated)
    }

    private func refreshPanel(animated: Bool) {
        panel?.sync(
            frame: metrics.screenRect(notch: notch),
            acceptsMouse: presentation != .idle || metrics.chrome == .badge,
            showsShadow: presentation == .expanded,
            animated: animated
        )
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
