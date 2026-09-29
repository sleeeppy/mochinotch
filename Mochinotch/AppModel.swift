import AppKit
import ApplicationServices
import Observation
import QuartzCore
import ServiceManagement
import SwiftUI

/// 화면 주사율에 맞춰 인사 시계를 돌린다. `Task.sleep`으로 찍으면 프레임이 밀리거나 겹친다.
@MainActor
private final class IntroClock: NSObject {
    private var link: CADisplayLink?
    private var onFrame: ((CFTimeInterval) -> Void)?

    func start(_ onFrame: @escaping (CFTimeInterval) -> Void) {
        stop()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        self.onFrame = onFrame
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var notch: NotchInfo = .placeholder
    private(set) var activities: [IslandActivity] = []
    private(set) var presentation: IslandPresentation = .idle
    /// 배너만 있고 알림 기록이 없는 앱. 그 대화창이 앞에 있을 때만 거둔다.
    private var unstoredBundles: Set<String> = []
    /// Dock에 숫자 뱃지가 있던 앱. 뱃지가 없어지면 그 앱의 오른쪽 알림은 읽힌 것이다.
    private var dockBadgeCounts: [String: Int] = [:]
    /// 펼치기 전과 접힌 직후에는 왼쪽 귀를 숨긴다. 다 접힌 뒤에 다시 내민다.
    private var agentEarSuppressed = false
    /// 펼치기 직전, 모양은 둔 채 왼쪽 아이콘만 먼저 거둔다.
    private(set) var leftIconsHidden = false
    private var agentEarTask: Task<Void, Never>?
    /// 왼쪽 아이콘을 거두고 곧 보여 줄 모양.
    private var pendingPresentation: IslandPresentation?
    private(set) var serverError: String?
    private(set) var shakeToken = 0
    /// 작업이 끝나 펼쳐질 때 노치가 아래로 한 번 말랑하게 늘어난다.
    private(set) var boingToken = 0
    private(set) var chargePulse = 0
    private(set) var notificationAccess: NotificationAccess = .starting
    private(set) var duoMessage: String?
    /// 화면 효과와 함께 노치 테두리를 지나가는 글로우.
    private(set) var edgeGlow: Double = 0
    private(set) var edgeGlowTravel: Double = 0
    private(set) var edgeGlowColor = Color.white
    var launchAtLoginError: String?
    /// 켤 때 인사와 메뉴에서 고른 인트로.
    private(set) var introStudy = IntroStudy.stored
    /// 작업이 끝날 때 화면 가장자리 연출. 꺼도 노치 연출은 그대로다.
    private(set) var playsScreenEffect = UserDefaults.standard.object(forKey: AppModel.screenEffectKey) as? Bool ?? true

    private var featuredID: UUID?
    private var noticesSeenAt = Date.distantPast
    private var isHovering = false
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var introTask: Task<Void, Never>?
    private let introClock = IntroClock()
    /// 화면 연출을 끈 때도 노치 테두리 빛은 이 시계로 돈다.
    private let glowClock = IntroClock()
    /// 켤 때 인사. 노치보다 통통한 모양을 직접 잡는다.
    private var introShape: IslandMetrics?
    /// 인사 도중에는 노치 스프링을 쓰지 않고, 안무가 그린 모양을 그대로 보여 준다.
    private(set) var introDirect = false
    /// 노치에서 떨어져 나온 모찌 방울들.
    private(set) var introBeads: [IntroBead] = []
    private var introGlowing = false
    private var clearTask: Task<Void, Never>?
    /// 지우기 직후 높이를 잠깐 유지한다. 글자가 사라진 뒤에 모양이 따라 줄어든다.
    private var frozenRows: Int?
    private let power = PowerMonitor()
    private let server = EventServer()
    private let notifications = NotificationWatcher()
    private var panel: IslandPanelController?
    /// 펼친 노치 안에 설정 화면을 연다. 별 창은 쓰지 않는다.
    private(set) var showsSettings = false
    /// 설정 화면 내용의 실제 높이. 판이 딱 맞게 열린다.
    private(set) var settingsHeight: CGFloat = 206
    /// 펼친 채로 인트로를 고르면, 마우스를 치운 뒤에 한 번 보여 준다.
    private(set) var pendingIntroPreview: IntroStudy?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    var featured: IslandActivity? {
        if let featuredID, let match = activities.first(where: { $0.id == featuredID }) {
            return match
        }
        return activities.first
    }

    var metrics: IslandMetrics {
        if let introShape { return introShape }
        return IslandMetrics.resolve(
            notch: notch,
            presentation: presentation,
            rowCount: frozenRows ?? activities.count,
            peekSlots: noticeGroups.count,
            agentSlots: agentEarSuppressed ? 0 : agentGroups.count,
            settingsHeight: showsSettings ? settingsHeight : nil
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

    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

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
        notifications.onDismiss = { [weak self] bundleID, title, body in
            self?.acknowledgeStoredNotice(bundleID: bundleID, title: title, body: body)
        }
        notifications.onUnstored = { [weak self] bundleID in
            Task { @MainActor in
                self?.unstoredBundles.insert(bundleID.lowercased())
            }
        }
        notifications.onStored = { [weak self] bundleID in
            Task { @MainActor in
                self?.unstoredBundles.remove(bundleID.lowercased())
            }
        }
        notifications.onAccessChange = { [weak self] access in
            self?.notificationAccess = access
        }
        notifications.start()
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOpenConversation()
                self?.syncDockBadges()
            }
        }

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
                self?.syncOpenConversation()
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

    private static let introStudyKey = "introStudy"
    private static let screenEffectKey = "playsScreenEffect"

    func setIntro(_ study: IntroStudy) {
        introStudy = study
        UserDefaults.standard.set(study.rawValue, forKey: Self.introStudyKey)
        if isHovering {
            pendingIntroPreview = study
            return
        }
        playIntro(study, quietOnly: false)
    }

    func setPlaysScreenEffect(_ enabled: Bool) {
        playsScreenEffect = enabled
        UserDefaults.standard.set(enabled, forKey: Self.screenEffectKey)
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
        launchAtLogin = SMAppService.mainApp.status == .enabled
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

    func openSettings() {
        withAnimation(IslandMotion.morph) {
            showsSettings = true
        }
        expandNow()
    }

    func closeSettings() {
        withAnimation(IslandMotion.morph) {
            showsSettings = false
        }
    }

    func setSettingsHeight(_ height: CGFloat) {
        guard abs(height - settingsHeight) > 0.5 else { return }
        withAnimation(IslandMotion.morph) {
            settingsHeight = height
        }
    }

    func toggleSettings() {
        if showsSettings {
            closeSettings()
        } else {
            openSettings()
        }
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

    /// Dock 뱃지가 있다가 사라지면, 그 앱의 오른쪽 알림은 전부 읽힌 것이다.
    /// 뱃지를 한 번도 안 다는 앱은 건드리지 않는다. 디스코드는 지금 뱃지가 없다.
    private func syncDockBadges() {
        guard let current = Self.currentDockBadges() else { return }
        let bundles = Set(dockBadgeCounts.keys).union(current.keys)
        for bundle in bundles {
            let now = current[bundle] ?? 0
            if now > 0 {
                dockBadgeCounts[bundle] = now
                continue
            }
            guard let before = dockBadgeCounts[bundle], before > 0 else { continue }
            dockBadgeCounts[bundle] = nil
            clearRightNotices(bundleID: bundle)
        }
    }

    private func clearRightNotices(bundleID: String) {
        let indexes = activities.indices.filter { index in
            let activity = activities[index]
            guard !activity.hidesPeek, !activity.staysOnLeft,
                  case .notice(_, _, _, let stored) = activity.payload else { return false }
            return stored?.caseInsensitiveCompare(bundleID) == .orderedSame
        }
        guard !indexes.isEmpty else { return }
        withAnimation(IslandMotion.morph) {
            for index in indexes {
                activities[index].hidesPeek = true
            }
        }
    }

    /// Dock 항목의 `AXStatusLabel`. 읽기에 실패하면 nil이라, 빈 목록과 구분한다.
    private static func currentDockBadges() -> [String: Int]? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return nil }
        var counts: [String: Int] = [:]
        var sawList = false
        for child in list {
            collectDockBadges(in: child, into: &counts, sawList: &sawList, depth: 0)
        }
        return sawList ? counts : nil
    }

    private static func collectDockBadges(
        in element: AXUIElement,
        into counts: inout [String: Int],
        sawList: inout Bool,
        depth: Int
    ) {
        if depth > 3 { return }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleName = (role as? String) ?? ""
        if roleName == "AXList" { sawList = true }
        if roleName == "AXDockItem" {
            sawList = true
            guard let title = axString(element, kAXTitleAttribute as CFString),
                  let bundleID = bundleID(matchingDockTitle: title),
                  let count = dockBadgeCount(element), count > 0 else { return }
            counts[bundleID.lowercased()] = count
            return
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for child in list {
            collectDockBadges(in: child, into: &counts, sawList: &sawList, depth: depth + 1)
        }
    }

    private static func dockBadgeCount(_ element: AXUIElement) -> Int? {
        guard let label = axString(element, "AXStatusLabel" as CFString) else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Int(trimmed) ?? 1
    }

    private static func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func bundleID(matchingDockTitle title: String) -> String? {
        let wanted = title.precomposedStringWithCanonicalMapping
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName?.precomposedStringWithCanonicalMapping,
                  let bundleID = app.bundleIdentifier else { continue }
            if name.caseInsensitiveCompare(wanted) == .orderedSame { return bundleID }
        }
        return nil
    }

    /// 기록이 없는 알림은, 그 대화창을 실제로 열고 있을 때만 거둔다.
    /// 한 번 지웠다고 앱을 잊으면, 같은 대화의 다음 알림은 영영 남는다.
    private func syncOpenConversation() {
        guard !unstoredBundles.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              unstoredBundles.contains(bundleID.lowercased()),
              let windowTitle = Self.frontWindowTitle(pid: app.processIdentifier),
              let conversation = Self.openConversation(bundleID: bundleID, windowTitle: windowTitle)
        else { return }
        let indexes = activities.indices.filter { index in
            let activity = activities[index]
            guard !activity.hidesPeek, !activity.staysOnLeft,
                  case .notice(_, let title, let body, let stored) = activity.payload,
                  stored?.caseInsensitiveCompare(bundleID) == .orderedSame
            else { return false }
            return Self.noticeMentions(title: title, body: body, conversation: conversation)
        }
        guard !indexes.isEmpty else { return }
        withAnimation(IslandMotion.morph) {
            for index in indexes {
                activities[index].hidesPeek = true
            }
        }
    }

    /// 디스코드는 `@이름 - Discord`, `#채널 - 서버`. 카톡은 채팅창 제목이 대화 이름이고, 목록 창은 `카카오톡`이다.
    private static func openConversation(bundleID: String, windowTitle: String) -> String? {
        if bundleID.caseInsensitiveCompare("com.hnc.Discord") == .orderedSame {
            guard let separator = windowTitle.range(of: " - ") else { return nil }
            var head = windowTitle[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.hasPrefix("@") { head.removeFirst() }
            if head.isEmpty || head.caseInsensitiveCompare("Discord") == .orderedSame { return nil }
            return head
        }
        if bundleID.caseInsensitiveCompare("com.kakao.KakaoTalkMac") == .orderedSame {
            let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || title == "카카오톡" || title.caseInsensitiveCompare("KakaoTalk") == .orderedSame {
                return nil
            }
            return title
        }
        return nil
    }

    private static func noticeMentions(title: String, body: String, conversation: String) -> Bool {
        let needle = normalizeNoticeText(conversation)
        guard needle.count >= 2 else { return false }
        let hay = normalizeNoticeText(title + " " + body)
        if hay.localizedStandardContains(needle) { return true }
        let sender = normalizeNoticeText(title)
        return sender.count >= 2 && needle.localizedStandardContains(sender)
    }

    private static func normalizeNoticeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2066}", with: "")
            .replacingOccurrences(of: "\u{2067}", with: "")
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private static func frontWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let element = window else { return nil }
        let ax = element as! AXUIElement
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &title)
        return title as? String
    }

    /// 알림센터에서 지워진 오른쪽 알림. 같은 앱의 배너만 있던 것도 함께 거둔다.
    /// 왼쪽 작업 완료는 포커스로만 접힌다.
    private func acknowledgeStoredNotice(bundleID: String, title: String, body: String) {
        let indexes = activities.indices.filter { index in
            let activity = activities[index]
            guard !activity.hidesPeek, !activity.staysOnLeft,
                  case .notice(_, let storedTitle, let storedBody, _) = activity.payload else {
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

    private static func duoTint(for tool: AgentTool, outcome: AgentOutcome) -> NSColor {
        if outcome == .failed {
            return NSColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 1)
        }
        switch tool {
        case .cursor, .claude, .codex:
            let rgb = tool.edgeTintRGB
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        case .custom:
            return IconTint.color(for: tool)
        }
    }

    func openScreenRecordingSettings() {
        DuoPulse.shared.openSettings()
    }

    private func showWelcome() {
        playIntro(introStudy, quietOnly: true)
    }

    private func flushIntroPreview() {
        guard let study = pendingIntroPreview else { return }
        pendingIntroPreview = nil
        playIntro(study, quietOnly: false)
    }

    private func playIntro(_ study: IntroStudy, quietOnly: Bool) {
        cancelIntro()
        introTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(quietOnly ? 240 : 40))
            guard let self, !Task.isCancelled else { return }
            if quietOnly, !self.activities.isEmpty || self.presentation != .idle || self.isHovering { return }
            if self.isHovering { return }
            self.startIntro(IntroScript.make(study))
        }
    }

    /// 안무는 시각만으로 모양을 정한다. 프레임이 늦게 와도 그 시각의 모양을 그려서 밀리지 않는다.
    private func startIntro(_ script: IntroScript) {
        activities.removeAll { $0.isIntro }
        presentation = .idle
        let idle = IslandMetrics.resolve(notch: notch, presentation: .idle, rowCount: 0)
        introDirect = true
        var began: CFTimeInterval?
        var revealed = false
        introClock.start { [weak self] now in
            guard let self else { return }
            let start = began ?? now
            began = start
            let t = now - start
            if self.isHovering {
                self.finishIntro(fold: false)
                return
            }
            let pose = script.pose(t)
            self.introShape = self.introBlob(from: idle, left: pose.left, right: pose.right, extraHeight: pose.drop)
            if self.introBeads != pose.beads {
                self.introBeads = pose.beads
            }
            if !revealed, t >= script.reveal {
                revealed = true
                self.revealIntro()
            }
            if let glow = script.glow {
                self.introGlow(t - glow)
            }
            if t >= script.length {
                self.finishIntro(fold: true)
            }
        }
    }

    /// 벌어진 윤곽을 따라 빛이 한 바퀴 돈다. 에이전트 완료 때와 같은 선이다.
    private func introGlow(_ elapsed: Double) {
        guard elapsed >= 0 else { return }
        let travel = min(1, elapsed / 1.9)
        introGlowing = true
        edgeGlowColor = Color(red: 1, green: 0.9, blue: 0.95)
        edgeGlowTravel = travel
        edgeGlow = travel < 0.47 ? 1 : max(0, 1 - (travel - 0.47) / 0.16)
    }

    private func revealIntro() {
        let activity = IslandActivity(
            id: UUID(),
            payload: .hint(title: "もちノッチ", detail: "노치에 마우스를 올려보세요"),
            createdAt: Date(),
            keepsHistory: false
        )
        activities.removeAll { $0.isIntro }
        activities.insert(activity, at: 0)
        featuredID = activity.id
        presentation = .compact
    }

    private func finishIntro(fold: Bool) {
        introTask = nil
        introClock.stop()
        introDirect = false
        introShape = nil
        introBeads = []
        if introGlowing {
            introGlowing = false
            edgeGlow = 0
            edgeGlowTravel = 0
        }
        activities.removeAll { $0.isIntro }
        if fold {
            setPresentation(.idle)
        }
    }

    private func cancelIntro() {
        introTask?.cancel()
        finishIntro(fold: false)
        stopIslandGlow()
    }

    /// 화면 가장자리 효과 없이, 노치 윤곽만 한 바퀴 돈다. 화면 연출이 켜져 있을 때와 같은 속도로.
    private func startIslandGlow(color: Color) {
        stopIslandGlow()
        edgeGlowColor = color
        var began: CFTimeInterval?
        glowClock.start { [weak self] now in
            guard let self else { return }
            let start = began ?? now
            began = start
            let seconds = now - start
            if seconds >= 5.25 {
                self.stopIslandGlow()
                return
            }
            self.edgeGlowTravel = min(1, seconds / 6.2)
            self.edgeGlow = Self.glowEnvelope(seconds)
        }
    }

    private func stopIslandGlow() {
        glowClock.stop()
        edgeGlow = 0
        edgeGlowTravel = 0
    }

    private static func glowEnvelope(_ seconds: Double) -> Double {
        func smootherstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
            guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
            let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
            return t * t * t * (t * (t * 6 - 15) + 10)
        }
        return smootherstep(0, 1.74, seconds) * (1 - smootherstep(2.25, 5.25, seconds))
    }

    /// `left`·`right`는 노치 밖으로 한쪽만 더 내미는 길이.
    private func introBlob(from idle: IslandMetrics, left: CGFloat, right: CGFloat, extraHeight: CGFloat) -> IslandMetrics {
        var shape = idle
        // 노치 아래로 내려온 만큼 옆벽을 노치 밖에 둔다. 세로 변은 어깨만큼 안쪽에 서서, 안 밀면 노치 모서리가 비친다.
        let hang = max(0, extraHeight)
        let clearance = (idle.shoulder + 1) * min(1, hang / 1.5)
        let leftEdge = -(idle.width / 2) - max(left, clearance)
        let rightEdge = idle.width / 2 + max(right, clearance)
        shape.width = max(1, rightEdge - leftEdge)
        shape.shift = (leftEdge + rightEdge) / 2
        // 튕겨 올라오며 노치 위로 넘친 만큼 줄이면 노치 바닥이 아래로 삐져나온다.
        shape.height = idle.height + hang
        // 늘어난 만큼만 둥글게 한다. 늘어나기 시작하는 순간 반경을 바꾸면 모서리가 튄다.
        shape.radius = min(28, idle.radius + max(0, extraHeight) * 0.46)
        shape.ear = max(0, (shape.width - idle.camera) / 2)
        return shape
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
        cancelIntro()
        hoverTask?.cancel()
        leaveTask?.cancel()
        clearTask?.cancel()
        frozenRows = nil
        // Cursor는 끝날 때 완료 이벤트와 알림 배너를 거의 같이 보낸다. 왼쪽 아이콘을 거두는 짧은 사이에
        // 배너가 오면 펼치려던 완료가 취소되고 화면 효과만 남는다. 그 사이의 알림도 완료를 덮지 않는다.
        let showingCompact = presentation == .compact || pendingPresentation == .compact
        let keepCurrentCompact = activity.isNotice && showingCompact && featured?.isNotice != true
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
            let tint = Self.duoTint(for: tool, outcome: outcome)
            if playsScreenEffect {
                DuoPulse.shared.play(tint: tint, rim: outcome == .failed ? 1 : tool.edgeRim)
            } else {
                let rgb = tint.usingColorSpace(.sRGB) ?? tint
                let lift = 0.42
                startIslandGlow(color: Color(
                    red: rgb.redComponent + (1 - rgb.redComponent) * lift,
                    green: rgb.greenComponent + (1 - rgb.greenComponent) * lift,
                    blue: rgb.blueComponent + (1 - rgb.blueComponent) * lift
                ))
            }
        }
        if activity.isFailure {
            shakeToken += 1
        } else if activity.bouncesIsland, !isHovering {
            boingToken += 1
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
                self.flushIntroPreview()
            }
        }
    }

    private func setPresentation(_ next: IslandPresentation) {
        agentEarTask?.cancel()
        pendingPresentation = nil
        let hasLeft = !agentGroups.isEmpty
        if presentation == .idle, hasLeft, next != .idle {
            leftIconsHidden = true
            pendingPresentation = next
            agentEarTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, let self else { return }
                self.pendingPresentation = nil
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
            showsSettings = false
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
