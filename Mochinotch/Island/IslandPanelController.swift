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
    /// 다른 앱에서 파일을 끄는 동안 커서 위치. 끝나면 `nil`.
    var onFileDrag: (CGPoint?) -> Void = { _ in }
    var canDropFiles: () -> Bool = { false }
    var onDropFiles: ([URL]) -> Bool = { _ in false }
    /// 노치 아래 맡긴 파일 자리. 이 위에서는 목록 대신 사진을 벌린다.
    var shelfRectProvider: () -> CGRect? = { nil }
    var onShelfHover: (Bool) -> Void = { _ in }
    private var lastShelfInside = false
    /// 누른 순간의 끌기 보드. 이 값이 바뀌어야 새 끌기가 시작된 것이다.
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var fileDragTimer: Timer?
    /// 노치에서 파일을 끌어내는 중. 내 끌기를 놓을 자리로 받으면 안 된다.
    private var draggingOut = false

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
        hosting.canDrop = { [weak self] in self?.canDropFiles() ?? false }
        hosting.onDrop = { [weak self] urls in self?.onDropFiles(urls) ?? false }
    }

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            let type = event.type
            Task { @MainActor in
                self?.handlePointer(type)
            }
        }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
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
        endFileDrag()
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
        let onShelf = !draggingOut && (shelfRectProvider()?.contains(point) ?? false)
        if onShelf != lastShelfInside {
            lastShelfInside = onShelf
            onShelfHover(onShelf)
            updateMouse()
        }
        let inside = !onShelf && hoverRectProvider().insetBy(dx: -8, dy: -6).contains(point)
        guard lastInside != inside else { return }
        lastInside = inside
        onHoverChange(inside)
    }

    /// 지금 누르고 끄는 이벤트로 파일 끌기를 시작한다. 다른 앱이 받으면 `delivered`가 참이다.
    func dragOut(_ urls: [URL], images: [NSImage?], ended: @escaping (_ delivered: Bool) -> Void) {
        guard !draggingOut, let event = NSApp.currentEvent,
              event.type == .leftMouseDragged || event.type == .leftMouseDown
        else { return }
        draggingOut = true
        hosting.beginFileDrag(urls, images: images, event: event) { [weak self] delivered in
            guard let self else { return }
            self.draggingOut = false
            self.dragBaseline = NSPasteboard(name: .drag).changeCount
            ended(delivered)
            self.trackPointer()
        }
    }

    private func handlePointer(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            endFileDrag()
            dragBaseline = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged where fileDragTimer == nil && !draggingOut:
            if isFileDrag() { beginFileDrag() }
        default:
            break
        }
        trackPointer()
    }

    private func isFileDrag() -> Bool {
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != dragBaseline else { return false }
        return board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// 끄는 동안의 이벤트는 끄는 앱 몫이라, 놓는 순간을 놓치지 않게 커서와 버튼을 직접 본다.
    private func beginFileDrag() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.followFileDrag()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fileDragTimer = timer
        followFileDrag()
    }

    private func followFileDrag() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endFileDrag()
            return
        }
        onFileDrag(NSEvent.mouseLocation)
        updateMouse()
    }

    private func endFileDrag() {
        guard let fileDragTimer else { return }
        fileDragTimer.invalidate()
        self.fileDragTimer = nil
        // 같은 끌기 보드로 다시 시작하지 않게 한다.
        dragBaseline = NSPasteboard(name: .drag).changeCount
        onFileDrag(nil)
        updateMouse()
    }
}

/// 창 크기를 SwiftUI 콘텐츠가 끌어내리지 않게 하고, 첫 클릭도 받는다.
final class IslandHostingView: NSHostingView<AnyView> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var canDrop: () -> Bool = { false }
    var onDrop: ([URL]) -> Bool = { _ in false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canDrop() && !fileURLs(sender).isEmpty ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canDrop() && !fileURLs(sender).isEmpty ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canDrop()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        return onDrop(urls)
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return objects as? [URL] ?? []
    }

    private let dragSource = FileDragSource()

    func beginFileDrag(_ urls: [URL], images: [NSImage?], event: NSEvent, ended: @escaping (Bool) -> Void) {
        let point = convert(event.locationInWindow, from: nil)
        let size: CGFloat = 56
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = images[index] ?? NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(index) * 5
            item.setDraggingFrame(
                NSRect(x: point.x - size / 2 + offset, y: point.y - size / 2 + offset, width: size, height: size),
                contents: image
            )
            return item
        }
        dragSource.ended = ended
        let session = beginDraggingSession(with: items, event: event, source: dragSource)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }
}

/// 노치에서 끌어낸 파일의 출발점. 호스팅 뷰가 SwiftUI 끌기용으로 이미 맡고 있어 따로 둔다.
private final class FileDragSource: NSObject, NSDraggingSource {
    var ended: ((Bool) -> Void)?

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // 원본은 제자리에 두고 받는 쪽이 복사해 가게 한다.
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ended?(operation != [])
        ended = nil
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
