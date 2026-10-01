import AppKit
import Darwin
import SwiftUI

/// 노치 위에 붙는 비활성 패널. 창은 모든 상태를 담는 크기로 고정하고, 모양은 SwiftUI가 그 안에서 모핑한다.
/// 창이 움직이거나 크기를 바꾸면 모양이 한쪽으로 쏠려 보이므로, 화면이 바뀔 때만 다시 놓는다.
@MainActor
final class IslandPanelController {
    private let panel: NSPanel
    private let hosting: IslandHostingView
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastInside: Bool?
    var hoverRectProvider: () -> CGRect = { .zero }
    /// 클릭을 받을 화면 영역. `nil`이면 모든 클릭을 아래 창으로 흘려보낸다.
    var interactiveRectProvider: () -> CGRect? = { nil }
    var onHoverChange: (Bool) -> Void = { _ in }

    init<Content: View>(rootView: Content) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 32),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        // transient는 Exposé에 창을 숨기게 해서, 모서리로 바탕화면을 열면 노치가 같이 밀린다.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true

        let hosting = IslandHostingView(rootView: AnyView(rootView))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        self.hosting = hosting
    }

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.trackPointer()
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            handler(event)
            return event
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.panel.orderFrontRegardless()
            ExposeShield.attach(to: self.panel)
        }
        panel.orderFrontRegardless()
        ExposeShield.attach(to: panel)
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    func place(frame: CGRect) {
        guard frame.width > 2, frame.height > 2 else { return }
        if !panel.frame.standardized.equalTo(frame.standardized) {
            panel.setFrame(frame, display: true)
        }
        updateMouse()
        panel.orderFrontRegardless()
        ExposeShield.attach(to: panel)
    }

    /// 창이 커도 보이는 모양 위에서만 클릭을 막는다.
    func updateMouse() {
        let point = NSEvent.mouseLocation
        let accepts = interactiveRectProvider()?.contains(point) ?? false
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
        }
    }

    func trackPointer() {
        updateMouse()
        let point = NSEvent.mouseLocation
        let inside = hoverRectProvider().insetBy(dx: -8, dy: -6).contains(point)
        guard lastInside != inside else { return }
        lastInside = inside
        onHoverChange(inside)
    }
}

/// 창 크기를 SwiftUI 콘텐츠가 끌어내리지 않게 하고, 첫 클릭도 받는다.
final class IslandHostingView: NSHostingView<AnyView> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// 바탕화면 보기(모서리)가 일반 창을 밀어낼 때 노치 창은 그 자리에 둔다.
private enum ExposeShield {
    private static let ignoreForExpose: Int32 = 1 << 7

    static func attach(to window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        typealias Connection = @convention(c) () -> Int32
        typealias SetTags = @convention(c) (Int32, UInt32, UnsafePointer<Int32>, Int) -> Int32
        let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        guard let connectionSymbol = dlsym(coreGraphics, "CGSMainConnectionID"),
              let setTagsSymbol = dlsym(coreGraphics, "CGSSetWindowTags") else { return }
        let connection = unsafeBitCast(connectionSymbol, to: Connection.self)
        let setTags = unsafeBitCast(setTagsSymbol, to: SetTags.self)
        var tags = [ignoreForExpose, Int32(0)]
        _ = setTags(connection(), UInt32(window.windowNumber), &tags, 64)
    }
}
