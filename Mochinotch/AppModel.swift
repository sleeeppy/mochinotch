import AppKit
import ApplicationServices
import Observation
import QuartzCore
import QuickLookThumbnailing
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
    /// 화면 효과와 함께 노치 테두리를 지나가는 글로우.
    private(set) var edgeGlow: Double = 0
    private(set) var edgeGlowTravel: Double = 0
    private(set) var edgeGlowColor = Color.white
    var launchAtLoginError: String?
    /// 켤 때 인사와 메뉴에서 고른 인트로.
    private(set) var introStudy = IntroStudy.stored
    /// 작업이 끝날 때 화면 가장자리 연출. 꺼도 노치 연출은 그대로다.
    private(set) var playsScreenEffect = UserDefaults.standard.object(forKey: AppModel.screenEffectKey) as? Bool ?? true
    /// 끄면 AirDrop이 왼쪽, 맡기기가 오른쪽. 켜면 둘이 자리를 바꾼다.
    private(set) var shelfOnLeft = UserDefaults.standard.bool(forKey: AppModel.shelfSideKey)
    /// 노치에 보이는 말. 맥 언어와 따로다.
    private(set) var language = AppLanguage.stored
    /// GitHub 최신 릴리즈가 이 앱보다 새로울 때.
    private(set) var updateAvailable = false
    /// 새 버전을 받는 중이면 0에서 1, 다 받고 바꿔 넣을 준비를 하면 1. 끝나면 앱이 꺼졌다 새 버전으로 켜진다.
    private(set) var updateProgress: Double?
    var installingUpdate: Bool { updateProgress != nil }
    var updateStatus: String? {
        guard let updateProgress else { return nil }
        return updateProgress < 1
            ? L10n.text(.receiving, language, Int(updateProgress * 100))
            : L10n.text(.preparing, language)
    }
    /// 설정에서 직접 누른 업데이트 확인의 결과. 잠깐 보여 주고 지운다.
    private(set) var updateCheckStatus: UpdateCheckStatus?
    private var updateCheckStatusReset: Task<Void, Never>?
    private var latestRelease: AppUpdater.Release?
    private var lastUpdateCheck: Date?
    private var updateCheck: Task<Void, Never>?
    /// 켜질 때 인사가 끝나기 전에는 업데이트 알림을 띄우지 않는다.
    private var awaitingLaunchIntro = true
    private var pendingUpdateVersion: String?

    private var featuredID: UUID?
    private var noticesSeenAt = Date.distantPast
    private var isHovering = false
    /// 끄는 중에는 노치를 다시 펼치지 않는다.
    private var isQuitting = false
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
    /// 파일을 끌고 노치 근처에 와 있을 때.
    private(set) var fileDrag: FileDragPhase?
    private var fileDragEndTask: Task<Void, Never>?
    /// 노치에 맡겨 둔 파일. 노치 아래로 사진 끝이 삐져나와 보인다.
    private(set) var shelf: [ShelfItem] = []
    /// 맡긴 파일 위에 마우스가 있어 부채꼴로 벌어진 상태.
    private(set) var shelfOpen = false
    /// 노치 아래로 다가온 정도. 0이면 평소, 1이면 바로 아래. 사진이 조금 내려오고 커진다.
    private(set) var shelfApproach: CGFloat = 0
    /// 보이는 사진 중 커서에 가장 가까운 장. 그 장만 더 앞으로 나온다.
    private(set) var shelfFocus: Int?
    /// 벌어진 채로 ⌘를 누르고 있으면 어느 사진을 끌어도 전부 꺼낸다.
    private(set) var shelfGrabsAll = false
    private var shelfModifierTimer: Timer?
    var shelfFull: Bool { shelf.count >= ShelfLayout.maxCards }
    /// 끌고 온 파일 중 맡기기에 새로 들어갈 개수. 끌기가 시작될 때 센다.
    private(set) var incomingFileCount = 0
    var shelfOverflowing: Bool { incomingFileCount > ShelfLayout.maxCards - shelf.count }
    /// 세 개를 넘겨 다 받지 못했을 때. 맡긴 사진이 고개를 젓고 아래에 안내가 잠깐 뜬다.
    private(set) var shelfRefusalToken = 0
    private(set) var shelfRefusalShowing = false
    private var shelfRefusalTask: Task<Void, Never>?
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
    /// 펼친 목록 내용의 실제 높이. 줄마다 어림하면 한 줄짜리 알림이 많을 때 아래가 빈다.
    private(set) var listHeight: CGFloat?
    /// 지우는 동안 붙잡아 두는 목록 높이.
    private var frozenListHeight: CGFloat?
    /// 펼친 채로 인트로를 고르면, 마우스를 치운 뒤에 한 번 보여 준다.
    private(set) var pendingIntroPreview: IntroStudy?
    /// 권한과 AI 연결 안내. 처음 켰을 때 인트로 뒤에 열리고, 닫기 전까지 펼친 채로 둔다.
    private(set) var showsSetup = false
    /// 인앱 업데이트가 끝나고 다시 켜진 직후, 방금 받은 버전의 패치 노트.
    private(set) var showsReleaseNotes = false
    private(set) var releaseNotes: ReleaseNotes?
    private(set) var setupStatus = SetupStatus()
    private(set) var agentLinkProgress = AgentLinkProgress.idle
    /// 화면 기록은 켠 뒤 앱을 다시 켜야 적용된다.
    private(set) var requestedScreenRecording = false
    private var setupPending = false
    private var setupTimer: Timer?
    /// 지우기로 치운 설정 알림은 이번에 켜 있는 동안 다시 넣지 않는다.
    private var setupReminderDismissed = false
    private var recentEventKeys: [String: Date] = [:]
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
        if let fileDrag { return IslandMetrics.dropZone(notch: notch, targeted: fileDrag.target != nil) }
        return IslandMetrics.resolve(
            notch: notch,
            presentation: presentation,
            rowCount: frozenRows ?? activities.count,
            peekSlots: noticeGroups.count,
            agentSlots: agentEarSuppressed ? 0 : agentGroups.count,
            settingsHeight: showsSettings || showsSetup || showsReleaseNotes ? settingsHeight : nil,
            listHeight: frozenRows != nil ? frozenListHeight : (activities.isEmpty ? nil : listHeight)
        )
    }

    var hoverScreenRect: CGRect {
        metrics.screenRect(notch: notch)
    }

    /// 접혀 있을 때는 노치 뒤라 클릭을 받지 않는다. 호버는 전역 모니터가 따로 본다.
    private var interactiveScreenRect: CGRect? {
        // 놓을 자리 위에서만 끌어 온 파일을 받는다. 나머지 창은 아래 앱이 받아야 한다.
        if fileDrag != nil { return hoverScreenRect }
        let shelfRect = shelfScreenRect
        guard presentation != .idle || metrics.chrome == .peek else { return shelfRect }
        return shelfRect.map { $0.union(hoverScreenRect) } ?? hoverScreenRect
    }

    /// 펼친 판이나 놓을 자리가 덮을 때는 맡긴 파일을 숨긴다.
    var shelfVisible: Bool {
        !shelf.isEmpty && fileDrag == nil && presentation != .expanded && introShape == nil && !isQuitting
    }

    /// 노치 아래로 삐져나온 사진 자리. 이 위에서는 목록을 펼치지 않고 사진만 벌린다.
    var shelfScreenRect: CGRect? {
        guard shelfVisible else { return nil }
        let reach = shelfOpen
            ? ShelfLayout.openPeek + 8
            : ShelfLayout.peek + shelfApproach * 16 + (shelfFocus == nil ? 0 : 12)
        let width = shelfOpen ? ShelfLayout.openWidth : ShelfLayout.restWidth + shelfApproach * 56
        let bottom = notch.screenFrame.maxY - metrics.height
        return CGRect(x: notch.centerX - width / 2, y: bottom - reach - 6, width: width, height: reach + 6)
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
            // 인트로는 노치 밖으로 내밀었다가 도로 들어온다. 그 모양으로 호버를 보면,
            // 커서가 그 자리에 있기만 해도 끝난 뒤 목록이 펼쳐진다.
            guard let self, !self.introDirect else { return .zero }
            return self.hoverScreenRect
        }
        controller.interactiveRectProvider = { [weak self] in
            self?.interactiveScreenRect
        }
        controller.onHoverChange = { [weak self] inside in
            self?.setHover(inside)
        }
        controller.onFileDrag = { [weak self] point in
            self?.updateFileDrag(at: point)
        }
        controller.canDropFiles = { [weak self] in
            guard let self, let fileDrag = self.fileDrag else { return false }
            return fileDrag.target != .shelf || !self.shelfFull
        }
        controller.onDropFiles = { [weak self] urls in
            self?.dropFiles(urls) ?? false
        }
        controller.shelfRectProvider = { [weak self] in
            self?.shelfScreenRect
        }
        controller.onShelfHover = { [weak self] inside in
            self?.setShelfOpen(inside)
        }
        controller.onShelfPointer = { [weak self] point in
            self?.updateShelfPointer(point)
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
            if let tool = Self.terminalPermission(SystemNotice(bundleID: bundleID, title: title, subtitle: "", body: body)) {
                self?.resolveWaiting(tool)
            }
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
            self?.refreshSetup()
        }
        notifications.start()
        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdate(scheduled: true)
            }
        }
        // 잠자는 동안은 한 시간 시계도 멈춘다. 뚜껑을 덮었다 여는 노트북은 깨어날 때 본다. 망이 붙을 틈을 둔다.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.checkForUpdate()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOpenConversation()
                self?.syncDockBadges()
            }
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
        Task.detached(priority: .utility) {
            HookInstaller.refreshRelayIfNeeded()
            HookInstaller.upgradeInstalledHooks()
        }
        if !UserDefaults.standard.bool(forKey: Self.setupDoneKey) {
            setupPending = true
            // 인트로가 알림에 밀려 끝나지 못해도 안내는 연다.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.presentSetupIfPending()
            }
        }
        loadPendingReleaseNotes()
        showWelcome()
    }

    private static let introStudyKey = "introStudy"
    private static let screenEffectKey = "playsScreenEffect"
    private static let shelfSideKey = "shelfOnLeft"
    private static let setupDoneKey = "setupDone"
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

    func setShelfOnLeft(_ enabled: Bool) {
        shelfOnLeft = enabled
        UserDefaults.standard.set(enabled, forKey: Self.shelfSideKey)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    func text(_ key: L10n.Key, _ args: CVarArg...) -> String {
        L10n.render(key, language, args)
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
        if event.kind?.lowercased() == "resolved" {
            resolveWaiting(tool)
            return
        }
        if event.kind?.lowercased() == "update" {
            let version = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "9.9.9"
            present(
                IslandActivity(
                    id: UUID(),
                    payload: .update(version: version),
                    createdAt: Date(),
                    keepsHistory: true
                ),
                seconds: 6
            )
            return
        }
        let outcome = outcome(for: event)
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(tool.displayName) \(outcome.shortLabel(in: language))"
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Date()
        recentEventKeys = recentEventKeys.filter { $0.value > now }
        let key = event.id ?? "\(tool.rawValue)|\(event.kind ?? "")|\(title)|\(detail)"
        if recentEventKeys[key] != nil { return }
        // 내용이 같은 건 거의 같이 온 것만 겹친 걸로 본다. 같은 curl을 다시 보내 보는 건 막지 않는다.
        recentEventKeys[key] = now.addingTimeInterval(event.id == nil ? 2 : 60)
        // 앱이 보내는 배너는 hook과 같은 완료다. hook이 오면 방금 뜬 배너는 뺀다.
        activities.removeAll { activity in
            guard activity.createdAt.timeIntervalSince(now) > -15,
                  case .notice(_, _, _, let bundleID) = activity.payload,
                  let bundleID,
                  let noticeTool = AgentTool.agents.first(where: { $0.iconBundleIDs.contains(bundleID) })
            else { return false }
            return noticeTool == tool
        }
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
        if outcome != .needsInput {
            resolveWaiting(tool)
        }
        present(activity, seconds: seconds)
    }

    func ingest(_ notice: SystemNotice) {
        if let ask = Self.terminalPermission(notice) {
            ingest(IncomingEvent(
                tool: ask.rawValue,
                title: L10n.text(.confirmTitle, language, ask.appTitle),
                detail: L10n.text(.permissionAsk, language),
                kind: "needsInput",
                bundleID: notice.bundleID
            ))
            return
        }
        if let question = Self.cursorQuestion(notice) {
            ingest(IncomingEvent(
                tool: AgentTool.cursor.rawValue,
                title: L10n.text(.confirmTitle, language, AgentTool.cursor.appTitle),
                detail: question,
                kind: "needsInput",
                bundleID: notice.bundleID
            ))
            return
        }
        // hook이 방금 같은 도구의 완료를 보냈으면 앱 배너는 겹치니 버린다.
        if let tool = AgentTool.agents.first(where: { $0.iconBundleIDs.contains(notice.bundleID) }),
           activities.contains(where: { activity in
               guard activity.createdAt.timeIntervalSinceNow > -15,
                     case .agent(let existing, _, _, _, _) = activity.payload else { return false }
               return existing == tool
           }) {
            return
        }
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
        refreshSetup()
        checkForUpdate()
        withAnimation(IslandMotion.morph) {
            showsSettings = true
        }
        expandNow()
    }

    /// 받아서 바꿔 넣을 수 있으면 바로 하고, 아니면 릴리즈 페이지를 연다.
    func openUpdate() {
        guard !installingUpdate else { return }
        guard let release = latestRelease, release.dmg != nil, AppUpdater.canReplace() else {
            openReleasePage()
            return
        }
        updateProgress = 0
        featureUpdate(release.version)
        Task { @MainActor [weak self] in
            do {
                try await AppUpdater.prepare(release) { value in
                    Task { @MainActor in
                        guard let self, let current = self.updateProgress, value > current else { return }
                        self.updateProgress = value
                    }
                }
                self?.updateProgress = 1
                self?.rememberReleaseNotes(release)
                self?.quit()
            } catch {
                self?.updateProgress = nil
                self?.openReleasePage()
            }
        }
    }

    /// 받는 동안 진행을 보여 줄 업데이트 줄. 목록에서 지웠으면 다시 넣는다.
    private func featureUpdate(_ tag: String) {
        if let existing = activities.first(where: \.isUpdateNotice) {
            featuredID = existing.id
            return
        }
        let version = Self.versionParts(tag).map(String.init).joined(separator: ".")
        let activity = IslandActivity(
            id: UUID(),
            payload: .update(version: version),
            createdAt: Date(),
            keepsHistory: true
        )
        activities.insert(activity, at: 0)
        featuredID = activity.id
    }

    /// 바꿔 넣기가 성공하면 새 앱이 이 버전으로 켜진다. 그때 한 번 패치 노트를 펼친다.
    private func rememberReleaseNotes(_ release: AppUpdater.Release) {
        let version = Self.versionParts(release.version).map(String.init).joined(separator: ".")
        guard !version.isEmpty else { return }
        UserDefaults.standard.set(
            [
                "version": version,
                "body": release.notes,
                "page": release.page.absoluteString,
            ],
            forKey: Self.pendingNotesKey
        )
    }

    /// 켜질 때, 방금 인앱으로 받은 버전이면 노트를 들고 있는다. 인사가 끝난 뒤에 펼친다.
    private func loadPendingReleaseNotes() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.pendingNotesKey) as? [String: String],
              let version = stored["version"],
              version == (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        else { return }
        releaseNotes = ReleaseNotes(
            version: version,
            body: Self.plainNotes(stored["body"] ?? ""),
            page: stored["page"].flatMap(URL.init(string:))
        )
    }

    func dismissReleaseNotes() {
        withAnimation(IslandMotion.morph) {
            showsReleaseNotes = false
        }
        if !isHovering {
            setPresentation(.idle)
        }
    }

    func openReleaseNotesPage() {
        guard let page = releaseNotes?.page else { return }
        NSWorkspace.shared.open(page)
    }

    private func presentInstalledNotes() {
        guard releaseNotes != nil, !showsReleaseNotes else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingNotesKey)
        settingsHeight = 300
        withAnimation(IslandMotion.morph) {
            showsReleaseNotes = true
        }
        expandNow()
    }

    /// 마크다운과 HTML을 노치에서 읽을 글로 바꾼다.
    private static func plainNotes(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_]{1,3}", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^[ \\t]+|[ \\t]+$", with: "", options: .regularExpression)
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let pendingNotesKey = "pendingReleaseNotes"

struct ReleaseNotes: Equatable {
    var version: String
    var body: String
    var page: URL?
}

    private func openReleasePage() {
        NSApp.activate(ignoringOtherApps: true)
        let page = latestRelease?.page ?? URL(string: "https://github.com/sleeeppy/mochinotch/releases/latest")!
        NSWorkspace.shared.open(page)
    }

    func openGuide() {
        NSWorkspace.shared.open(language.guideURL)
    }

    /// 최신 릴리즈 태그만 본다. 켜질 때, 한 시간마다, 깨어날 때. 설정을 열 때는 10분이 지났으면 다시 본다.
    /// 실패하면 다음 설정 열기 때 다시 본다. 같은 버전 알림은 한 번만 뜬다.
    func checkForUpdate(scheduled: Bool = false) {
        if !scheduled, let lastUpdateCheck, Date().timeIntervalSince(lastUpdateCheck) < 10 * 60 { return }
        guard updateCheck == nil else { return }
        lastUpdateCheck = Date()
        let local = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        updateCheck = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.updateCheck = nil }
            let started = Date()
            let result = await Self.githubUpdateAvailable(local: local)
            switch result {
            case .newer(let release):
                self.latestRelease = release
                self.updateAvailable = true
                self.announceUpdate(release.version)
            case .current:
                self.updateAvailable = false
            case .failed:
                self.lastUpdateCheck = nil
            }
            guard self.updateCheckStatus == .checking else { return }
            // 바로 답이 오면 "확인 중"이 깜빡이고 지나가서 눌린 줄 모른다.
            let shown = Date().timeIntervalSince(started)
            if shown < 0.6 {
                try? await Task.sleep(for: .seconds(0.6 - shown))
            }
            switch result {
            case .newer: self.showUpdateCheckStatus(nil)
            case .current: self.showUpdateCheckStatus(.current)
            case .failed: self.showUpdateCheckStatus(.failed)
            }
        }
    }

    /// 설정의 "업데이트 확인". 시간 간격과 상관없이 바로 본다.
    func checkForUpdateNow() {
        guard !installingUpdate, updateCheckStatus != .checking else { return }
        updateCheckStatusReset?.cancel()
        updateCheckStatus = .checking
        checkForUpdate(scheduled: true)
    }

    private func showUpdateCheckStatus(_ status: UpdateCheckStatus?) {
        updateCheckStatus = status
        guard status != nil else { return }
        updateCheckStatusReset?.cancel()
        updateCheckStatusReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.updateCheckStatus = nil
        }
    }

    enum UpdateCheckStatus: Equatable {
        case checking
        case current
        case failed
    }

    private static let announcedUpdateKey = "announcedUpdateVersion"

    private enum UpdateCheck {
        case newer(AppUpdater.Release)
        case current
        case failed
    }

    private static func githubUpdateAvailable(local: String) async -> UpdateCheck {
        guard let url = URL(string: "https://api.github.com/repos/sleeeppy/mochinotch/releases/latest") else { return .failed }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("Mochinotch", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return .failed }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/sleeeppy/mochinotch/releases/latest")!
        guard isNewerRelease(tag, than: local) else { return .current }
        return .newer(AppUpdater.release(from: json, tag: tag, page: page))
    }

    /// 이 버전은 한 번만 알린다. 다음 버전이 나오면 다시 한 번. 켜질 때 인사가 끝나기 전에는 기다린다.
    private func announceUpdate(_ tag: String) {
        let version = Self.versionParts(tag).map(String.init).joined(separator: ".")
        guard !version.isEmpty else { return }
        if UserDefaults.standard.string(forKey: Self.announcedUpdateKey) == version { return }
        if awaitingLaunchIntro || introDirect || introTask != nil {
            pendingUpdateVersion = version
            return
        }
        presentUpdateNotice(version)
    }

    private func presentUpdateNotice(_ version: String) {
        if UserDefaults.standard.string(forKey: Self.announcedUpdateKey) == version { return }
        UserDefaults.standard.set(version, forKey: Self.announcedUpdateKey)
        present(
            IslandActivity(
                id: UUID(),
                payload: .update(version: version),
                createdAt: Date(),
                keepsHistory: true
            ),
            seconds: 6
        )
    }

    /// 켜질 때 인사가 끝났거나 건너뛴 뒤에 미뤄 둔 업데이트를 띄운다.
    private func finishLaunchIntro() {
        awaitingLaunchIntro = false
        if releaseNotes != nil {
            presentInstalledNotes()
        }
        guard let version = pendingUpdateVersion else { return }
        pendingUpdateVersion = nil
        presentUpdateNotice(version)
    }

    private static func isNewerRelease(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        guard !remoteParts.isEmpty, !localParts.isEmpty else { return false }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    private static func versionParts(_ text: String) -> [Int] {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    // MARK: 권한과 AI 연결

    func openSetup() {
        refreshSetup()
        startSetupPolling()
        hoverTask?.cancel()
        leaveTask?.cancel()
        dismissTask?.cancel()
        withAnimation(IslandMotion.morph) {
            showsSettings = false
            showsSetup = true
        }
        setPresentation(.expanded)
        promptMissingPermissions()
    }

    /// 다 켜지 않았어도 닫으면 다음부터는 저절로 열지 않는다. 설정에서 다시 연다.
    func finishSetup() {
        UserDefaults.standard.set(true, forKey: Self.setupDoneKey)
        setupPending = false
        stopSetupPolling()
        withAnimation(IslandMotion.morph) {
            showsSetup = false
        }
        if !isHovering {
            setPresentation(.idle)
        }
    }

    private func presentSetupIfPending() {
        guard setupPending, !introDirect else { return }
        setupPending = false
        // 알림 권한은 켠 직후에야 확인된다. 인트로가 끝날 즈음 보면 이미 다 켠 사람은 건너뛴다.
        refreshSetup()
        if setupStatus.remaining == 0 {
            UserDefaults.standard.set(true, forKey: Self.setupDoneKey)
            if presentation != .idle, !isHovering {
                setPresentation(.idle)
            }
            return
        }
        openSetup()
    }

    func refreshSetup() {
        let next = SetupStatus(
            notifications: notificationAccess == .watching,
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess(),
            agents: HookInstaller.status(),
            movedFromDownloads: !HookInstaller.isTranslocated
        )
        if next != setupStatus {
            withAnimation(.easeInOut(duration: 0.22)) {
                setupStatus = next
            }
        }
        syncSetupReminder()
    }

    /// 꺼진 게 있으면 펼친 목록에 Mochinotch가 보낸 알림을 하나 둔다. 다 켜면 저절로 빠진다.
    private func syncSetupReminder() {
        var missing: [String] = []
        // 알림 권한은 켤 때 잠깐 확인 중이다. 그 사이에 넣으면 다 켠 사람에게도 한 번 번쩍 뜬다.
        if !setupStatus.notifications, notificationAccess != .starting { missing.append("notifications") }
        if !setupStatus.accessibility { missing.append("accessibility") }
        if !setupStatus.screenRecording { missing.append("screen") }
        if !setupStatus.agentsDone { missing.append("agents") }
        let index = activities.firstIndex(where: \.isSetupReminder)
        if missing.isEmpty || setupReminderDismissed {
            if let index {
                withAnimation(IslandMotion.morph) {
                    _ = activities.remove(at: index)
                }
            }
            return
        }
        let payload = ActivityPayload.setup(missing: missing)
        if let index {
            if activities[index].payload != payload {
                activities[index].payload = payload
            }
            return
        }
        activities.insert(
            IslandActivity(id: UUID(), payload: payload, createdAt: Date(), keepsHistory: true),
            at: 0
        )
    }

    private func startSetupPolling() {
        setupTimer?.invalidate()
        setupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSetup()
            }
        }
    }

    private func stopSetupPolling() {
        setupTimer?.invalidate()
        setupTimer = nil
    }

    /// 손쉬운 사용과 화면 기록은 시스템 요청 창을 띄운다. 앱과 터미널 hook은 같은 실행 파일이라 한 번이면 둘 다 적용된다.
    /// 전체 디스크 접근 권한은 요청 창이 없어서 설정 목록만 연다.
    func promptMissingPermissions() {
        NSApp.activate(ignoringOtherApps: true)
        if !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        if !CGPreflightScreenCaptureAccess() {
            requestedScreenRecording = true
            if CGRequestScreenCaptureAccess() { refreshSetup() }
        }
    }

    func requestAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            openPrivacyPane("Privacy_Accessibility")
        }
        refreshSetup()
    }

    func requestScreenRecording() {
        NSApp.activate(ignoringOtherApps: true)
        requestedScreenRecording = true
        if !CGRequestScreenCaptureAccess() {
            openPrivacyPane("Privacy_ScreenCapture")
        }
        refreshSetup()
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 권한 몇 가지는 켠 뒤 다시 켜야 적용된다. 이 앱이 다 꺼진 뒤에 새로 띄운다.
    func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
            String(getpid()),
        ]
        try? process.run()
        quit()
    }

    /// 펼친 노치를 먼저 접고, 다 접힌 뒤에 끈다.
    func quit() {
        guard !isQuitting else { return }
        isQuitting = true
        hoverTask?.cancel()
        leaveTask?.cancel()
        dismissTask?.cancel()
        isHovering = false
        let wasOpen = presentation != .idle
        if wasOpen {
            setPresentation(.idle)
        }
        Task { @MainActor in
            if wasOpen {
                try? await Task.sleep(for: .milliseconds(620))
            }
            NSApp.terminate(nil)
        }
    }

    /// hook을 넣고, 설정이 바뀐 도구의 앱이 켜져 있으면 다시 켠다.
    func connectAgents() {
        if agentLinkProgress.isWorking { return }
        let tools = setupStatus.agents.present
        guard !tools.isEmpty else { return }
        agentLinkProgress = .connecting
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                HookInstaller.install(tools: tools)
            }.value
            guard let self else { return }
            if let failure = result.failures.first {
                self.agentLinkProgress = .failed(tool: failure.tool.displayName, problem: failure.problem)
                self.refreshSetup()
                return
            }
            var report = AgentLinkResult()
            for tool in result.changed where tool.needsRestart {
                for app in tool.appBundleIDs.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:)) {
                    // Codex 앱은 프로세스 이름이 ChatGPT다. 사람들이 아는 건 앱 파일 이름이다.
                    let name = app.bundleURL?.deletingPathExtension().lastPathComponent ?? tool.displayName
                    self.agentLinkProgress = .restarting(name)
                    if await Self.restart(app) {
                        report.restarted.append(name)
                    } else {
                        report.stuck.append(name)
                    }
                }
            }
            report.already = result.changed.isEmpty
            report.connected = !report.already && report.restarted.isEmpty && report.stuck.isEmpty
            report.terminal = result.changed.contains(where: { $0 == .claude || $0 == .codex })
            self.agentLinkProgress = .done(report)
            self.refreshSetup()
        }
    }

    /// 저장하지 않은 문서가 있으면 앱이 종료를 물어본다. 그때는 억지로 끄지 않는다.
    /// Cursor는 창과 에이전트를 정리하느라 20초 넘게 걸리기도 한다.
    private static func restart(_ app: NSRunningApplication) async -> Bool {
        guard let url = app.bundleURL, let bundleID = app.bundleIdentifier else { return false }
        app.terminate()
        for _ in 0..<360 where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard app.isTerminated else { return false }
        try? await Task.sleep(for: .milliseconds(400))
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) {
            return true
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }

    func closeSettings() {
        withAnimation(IslandMotion.morph) {
            showsSettings = false
        }
    }

    func setListHeight(_ height: CGFloat) {
        guard frozenRows == nil, height > 1 else { return }
        if let listHeight, abs(height - listHeight) <= 0.5 { return }
        withAnimation(IslandMotion.morph) {
            listHeight = height
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

    /// 터미널이 CLI 승인 대기를 배너로 띄운 경우. Ghostty의 `kiro: ~` / `Permission required` 같은 알림이다.
    private static func terminalPermission(_ notice: SystemNotice) -> AgentTool? {
        let terminals: Set<String> = [
            "com.mitchellh.ghostty",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
        ]
        guard terminals.contains(notice.bundleID.lowercased()) else { return nil }
        let text = "\(notice.title)\n\(notice.subtitle)\n\(notice.body)".lowercased()
        guard text.contains("permission required") else { return nil }
        if text.contains("kiro") { return .kiro }
        if text.contains("claude") { return .claude }
        if text.contains("codex") { return .codex }
        if text.contains("cursor") { return .cursor }
        return nil
    }

    /// Cursor는 질문 카드를 띄울 때 preToolUse hook을 부르지 않는다. 대신 `Input needed • 질문` 배너를 보낸다.
    private static func cursorQuestion(_ notice: SystemNotice) -> String? {
        guard AgentTool.cursor.iconBundleIDs.contains(notice.bundleID) else { return nil }
        let headline = notice.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard headline.lowercased().hasPrefix("input needed") else { return nil }
        let question = headline.split(separator: "•", maxSplits: 1).dropFirst().first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return question.isEmpty ? "답변을 기다리고 있어요" : question
    }

    /// 왼쪽 AI 작업만. 그 앱이나, CLI로 돌렸다면 그 터미널을 앞으로 가져오면 접힌다. 오른쪽 알림은 그대로 둔다.
    private func acknowledgeAgent(bundleID: String) {
        let indexes = activities.indices.filter { activities[$0].clearsWhenFocused(bundleID) && !activities[$0].hidesPeek }
        let foldCompact: Bool = {
            guard presentation == .compact, !isHovering, let featured else { return false }
            if case .agent(let tool, _, _, _, let openIDs) = featured.payload {
                return tool.iconBundleIDs.contains(bundleID) || openIDs.contains(bundleID)
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
        setupReminderDismissed = true
        let rows = activities.count
        if isHovering, rows > 0 {
            frozenRows = rows
            frozenListHeight = listHeight
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
        if activity.isSetupReminder {
            openSetup()
            return
        }
        if activity.isUpdateNotice {
            openUpdate()
            return
        }
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
        case .cursor, .claude, .codex, .kiro:
            let rgb = tool.edgeTintRGB
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        case .custom:
            return IconTint.color(for: tool)
        }
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
            let hasHistory = self.activities.contains { !$0.isSetupReminder }
            if quietOnly, hasHistory || self.presentation != .idle || self.isHovering {
                self.introTask = nil
                self.presentSetupIfPending()
                self.finishLaunchIntro()
                return
            }
            if self.isHovering {
                self.introTask = nil
                if quietOnly { self.finishLaunchIntro() }
                return
            }
            self.startIntro(IntroScript.make(study), afterLaunch: quietOnly)
        }
    }

    /// 안무는 시각만으로 모양을 정한다. 프레임이 늦게 와도 그 시각의 모양을 그려서 밀리지 않는다.
    private func startIntro(_ script: IntroScript, afterLaunch: Bool = false) {
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
                self.presentSetupIfPending()
                if afterLaunch { self.finishLaunchIntro() }
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
                // 안내를 열 거면 접지 않고 인사한 모양에서 바로 펼친다.
                self.finishIntro(fold: !self.setupPending)
                self.presentSetupIfPending()
                // 인트로 중에는 호버를 보지 않아서, 시작 전에 노치 위에 있던 커서가 그대로면
                // 끝난 뒤 목록이 펼쳐진다. 노치 위에 없을 때만 접는다.
                self.panel?.trackPointer()
                if !self.setupPending, !self.isHovering, self.presentation != .idle {
                    self.setPresentation(.idle)
                }
                if afterLaunch { self.finishLaunchIntro() }
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
        // 설정에서 인트로를 미리 보는 사이에 찾은 업데이트도 끝나면 띄운다.
        if !awaitingLaunchIntro, pendingUpdateVersion != nil {
            Task { @MainActor [weak self] in
                guard let self, self.introTask == nil, !self.introDirect,
                      let version = self.pendingUpdateVersion else { return }
                self.pendingUpdateVersion = nil
                self.presentUpdateNotice(version)
            }
        }
    }

    private func cancelIntro() {
        // 켜고 인사가 시작되기 전 잠깐 사이에 알림이 와도 끊긴 것이다. 놓치면 업데이트 알림이 계속 미뤄진다.
        let interruptedLaunch = awaitingLaunchIntro && (introDirect || introTask != nil)
        introTask?.cancel()
        finishIntro(fold: false)
        stopIslandGlow()
        if interruptedLaunch {
            Task { @MainActor [weak self] in
                self?.finishLaunchIntro()
            }
        }
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
        if case .agent(let tool, let outcome, _, _, _) = activity.payload,
           tool.playsDuo, outcome != .cancelled, outcome != .needsInput {
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
        } else if activity.bouncesIsland, !isHovering, !showsSetup, !showsReleaseNotes {
            boingToken += 1
        }
        let waiting = if case .agent(_, .needsInput, _, _, _) = activity.payload { true } else { false }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !waiting,
           activity.clearsWhenFocused(front),
           let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index].hidesPeek = true
        }
        if isHovering || showsSetup || showsReleaseNotes {
            setPresentation(.expanded)
        } else if activity.isNotice {
            setPresentation(.idle)
        } else if case .agent(_, .needsInput, _, _, _) = activity.payload {
            // 답을 고를 때까지 확인을 펼쳐 둔다. 왼쪽 아이콘만 남기지 않는다.
            setPresentation(.compact)
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

    /// 질문이나 승인 창이 닫히면 그 확인 요청을 접는다.
    private func resolveWaiting(_ tool: AgentTool) {
        let ids = Set(activities.compactMap { activity -> UUID? in
            guard case .agent(let existing, .needsInput, _, _, _) = activity.payload, existing == tool else { return nil }
            return activity.id
        })
        guard !ids.isEmpty else { return }
        let wasShowing = featuredID.map { ids.contains($0) } == true
        activities.removeAll { ids.contains($0.id) }
        if wasShowing, !isHovering, !showsSetup, !showsReleaseNotes {
            setPresentation(.idle)
        }
    }

    /// `point`가 `nil`이면 끌기가 끝났다.
    private func updateFileDrag(at point: CGPoint?) {
        guard let point else {
            guard fileDrag != nil else { return }
            // 꽉 찬 맡기기에는 놓기 자체가 오지 않는다. 그 위에서 손을 뗐으면 못 받은 것이다.
            if fileDrag?.target == .shelf, shelfFull {
                refuseShelf()
            }
            // 손을 떼는 순간 접으면, 놓기가 노치에 닿기 전에 창이 클릭을 흘려보낸다.
            let settle = fileDrag?.target != nil
            fileDragEndTask?.cancel()
            fileDragEndTask = Task { [weak self] in
                if settle { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                self?.setFileDrag(nil)
            }
            return
        }
        guard !isQuitting, introShape == nil, !showsSetup, !showsReleaseNotes else {
            setFileDrag(nil)
            return
        }
        fileDragEndTask?.cancel()
        let zone = IslandMetrics.dropZone(notch: notch, targeted: true).screenRect(notch: notch)
        if zone.insetBy(dx: -4, dy: -4).contains(point) {
            let onLeft = point.x < notch.centerX
            setFileDrag(.over(onLeft == shelfOnLeft ? .shelf : .airDrop))
        } else if zone.insetBy(dx: -180, dy: -220).contains(point) {
            setFileDrag(.near)
        } else {
            setFileDrag(nil)
        }
    }

    private func setFileDrag(_ phase: FileDragPhase?) {
        guard fileDrag != phase else { return }
        if fileDrag == nil {
            hoverTask?.cancel()
            let urls = NSPasteboard(name: .drag).readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
            incomingFileCount = urls.filter { url in !shelf.contains { $0.url == url } }.count
        }
        fileDrag = phase
        panel?.updateMouse()
    }

    private func dropFiles(_ urls: [URL]) -> Bool {
        let target = fileDrag?.target
        fileDragEndTask?.cancel()
        setFileDrag(nil)
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        switch target {
        case .airDrop: return sendViaAirDrop(files)
        case .shelf: return addToShelf(files)
        case nil: return false
        }
    }

    /// 세 개까지만 맡는다. 넘치게 놓으면 앞에서부터 들어갈 만큼만 받고, 꽉 차 있으면 받지 않아 제자리로 돌아간다.
    private func addToShelf(_ files: [URL]) -> Bool {
        let fresh = files.filter { url in !shelf.contains { $0.url == url } }
        guard !fresh.isEmpty else { return true }
        let room = ShelfLayout.maxCards - shelf.count
        if fresh.count > room {
            refuseShelf()
        }
        guard room > 0 else { return false }
        let items = fresh.prefix(room).map { ShelfItem(url: $0) }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
            shelf.append(contentsOf: items)
        }
        items.forEach(loadThumbnail)
        panel?.updateMouse()
        return true
    }

    /// 놓을 자리가 접히고 맡긴 사진이 다시 나온 뒤에 고개를 젓는다.
    private func refuseShelf() {
        shelfRefusalTask?.cancel()
        shelfRefusalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            self.shelfRefusalToken += 1
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                self.shelfRefusalShowing = true
            }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.shelfRefusalShowing = false
            }
        }
    }

    private func loadThumbnail(for item: ShelfItem) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in
                guard let self, let index = self.shelf.firstIndex(where: { $0.id == item.id }) else { return }
                self.shelf[index].thumbnail = image
            }
        }
    }

    /// 맡긴 파일을 노치 밖으로 끌어낸다. 다른 앱이 받으면 노치에서 뺀다. ⌘를 누르고 끌면 전부 꺼낸다.
    func dragFromShelf(_ ids: [ShelfItem.ID]) {
        let ids = NSEvent.modifierFlags.contains(.command) ? shelf.map(\.id) : ids
        let items = shelf.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }
        panel?.dragOut(items.map(\.url), images: items.map(\.thumbnail)) { [weak self] delivered in
            guard let self, delivered else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                self.shelf.removeAll { ids.contains($0.id) }
                if self.shelf.isEmpty { self.shelfOpen = false }
            }
            self.panel?.updateMouse()
        }
    }

    func clearShelf() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            shelf.removeAll()
            shelfOpen = false
            shelfApproach = 0
            shelfFocus = nil
        }
        panel?.updateMouse()
    }

    /// 노치 아래에 있으면 사진을 조금씩 내리고, 가로로 가장 가까운 장을 고른다.
    private func updateShelfPointer(_ point: CGPoint) {
        guard shelfVisible else {
            guard shelfApproach != 0 || shelfFocus != nil else { return }
            shelfApproach = 0
            shelfFocus = nil
            panel?.updateMouse()
            return
        }
        let center = notch.centerX
        let bottom = notch.screenFrame.maxY - metrics.height
        let below = bottom - point.y
        let dx = abs(point.x - center)
        let inZone = below > -6 && below < 110 && dx < 130
        let raw: CGFloat = inZone
            ? min(1, max(0, 1 - max(dx / 130, max(0, below - 4) / 100)))
            : 0
        let stepped = (raw * 16).rounded() / 16
        let shown = Array(shelf.suffix(ShelfLayout.maxCards))
        let spread = shelfOpen ? 2.6 : 1 + stepped * 0.85
        let fanX: [CGFloat] = [0, -9, 9]
        var focus: Int?
        if stepped > 0.12, !shown.isEmpty {
            var best = CGFloat.greatestFiniteMagnitude
            for index in shown.indices {
                let slot = min(shown.count - 1 - index, fanX.count - 1)
                let dist = abs(point.x - (center + fanX[slot] * spread))
                if dist < best {
                    best = dist
                    focus = index
                }
            }
        }
        guard abs(stepped - shelfApproach) > 0.01 || focus != shelfFocus else { return }
        shelfApproach = stepped
        shelfFocus = focus
        panel?.updateMouse()
    }

    private func setShelfOpen(_ open: Bool) {
        guard shelfOpen != open, !open || shelfVisible else { return }
        if open {
            hoverTask?.cancel()
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.66)) {
            shelfOpen = open
        }
        // ⌘만 누르고 떼는 건 마우스 이벤트로 오지 않는다. 벌어져 있는 동안만 들여다본다.
        shelfModifierTimer?.invalidate()
        shelfModifierTimer = nil
        if open {
            let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.syncShelfGrabsAll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            shelfModifierTimer = timer
        }
        syncShelfGrabsAll()
    }

    private func syncShelfGrabsAll() {
        if !shelfOpen {
            shelfModifierTimer?.invalidate()
            shelfModifierTimer = nil
        }
        let grabsAll = shelfOpen && shelf.count > 1 && NSEvent.modifierFlags.contains(.command)
        guard shelfGrabsAll != grabsAll else { return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
            shelfGrabsAll = grabsAll
        }
    }

    private func sendViaAirDrop(_ files: [URL]) -> Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
            return false
        }
        // AirDrop 창을 띄우는 동안 화면이 멈춘다. 그 사이에 접히면 접힘이 건너뛰어지니, 다 접은 뒤에 연다.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: files)
        }
        return true
    }

    private func setHover(_ hovering: Bool) {
        guard !isQuitting else { return }
        if hovering {
            leaveTask?.cancel()
            // 파일을 끌고 지나가다 목록이 펼쳐지면 놓을 자리를 가린다.
            guard !isHovering, fileDrag == nil else { return }
            isHovering = true
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: MochinotchConfig.hoverIn)
                guard !Task.isCancelled, let self, self.isHovering else { return }
                self.dismissTask?.cancel()
                // 시스템 설정에서 따로 켠 권한도 펼칠 때 알림에 반영한다.
                self.refreshSetup()
                self.setPresentation(.expanded)
            }
        } else {
            hoverTask?.cancel()
            guard isHovering else { return }
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: MochinotchConfig.hoverOut)
                guard !Task.isCancelled, let self else { return }
                self.isHovering = false
                // 바탕화면 보기가 노치를 그 순간 그림으로 얼린다. 그 사이에 접으면
                // 보기가 끝나는 순간 이미 접힌 모양으로 튄다. 모서리에서 나온 뒤에 접는다.
                while ExposeCorners.isHeld {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                }
                guard !self.isHovering else { return }
                if self.presentation == .expanded, !self.showsSetup, !self.showsReleaseNotes {
                    // 받는 중이면 접힌 노치 귀에 진행을 남긴다.
                    if self.installingUpdate, let update = self.activities.first(where: \.isUpdateNotice) {
                        self.featuredID = update.id
                        self.setPresentation(.compact)
                    } else {
                        self.setPresentation(.idle)
                    }
                }
                // 접히는 스프링이 끝나기 전에 인트로가 모양을 가로채면 접힘이 끊긴다.
                if self.pendingIntroPreview != nil {
                    try? await Task.sleep(for: .milliseconds(540))
                    guard !Task.isCancelled, !self.isHovering else { return }
                }
                self.flushIntroPreview()
            }
        }
    }

    private func setPresentation(_ next: IslandPresentation) {
        if isQuitting, next != .idle { return }
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
            showsReleaseNotes = false
            if showsSetup {
                showsSetup = false
                stopSetupPolling()
            }
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
