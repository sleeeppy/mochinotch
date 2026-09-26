import AppKit
import SwiftUI

/// 노치 위에 붙는 비활성 패널. 창 크기가 곧 아일랜드 크기다.
@MainActor
final class IslandPanelController {
    private let panel: NSPanel
    private let hosting: IslandHostingView
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastInside: Bool?
    var hoverRectProvider: () -> CGRect = { .zero }
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
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
                self?.trackHover()
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            handler(event)
            return event
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        }
        panel.orderFrontRegardless()
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

    func sync(frame: CGRect, acceptsMouse: Bool, showsShadow: Bool, animated: Bool) {
        guard frame.width > 2, frame.height > 2 else { return }
        let same = panel.frame.standardized.equalTo(frame.standardized)
        panel.ignoresMouseEvents = !acceptsMouse
        panel.hasShadow = showsShadow
        if !same {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = IslandMotion.windowDuration
                    context.timingFunction = IslandMotion.windowTiming
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
        panel.orderFrontRegardless()
    }

    private func trackHover() {
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
