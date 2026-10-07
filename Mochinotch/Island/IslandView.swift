import AppKit
import Observation
import QuartzCore
import SwiftUI

struct IslandRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 맡긴 파일은 판 뒤에 깔아서 사진 위쪽이 노치에 물린 것처럼 보이게 한다.
        ZStack(alignment: .top) {
            ShelfTuck()
            plate(metrics: model.metrics, reduceMotion: reduceMotion)
        }
    }

    /// 창은 고정이고, 모양은 그 안 위 가운데에 붙어 자란다. 글자는 최종 크기로 먼저 놓이고 모양이 그걸 드러낸다.
    private func plate(metrics: IslandMetrics, reduceMotion: Bool) -> some View {
        MorphingNotch(target: metrics, reduceMotion: reduceMotion, instant: model.introDirect) { shown in
            let shape = NotchShape(shoulder: shown.shoulder, radius: shown.radius)
            let depth = min(1, max(0, (shown.height - 70) / 140))

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    shape
                        .fill(IslandColor.plate)
                        .frame(width: shown.width, height: shown.height)
                        .background(alignment: .top) {
                            if !model.introBeads.isEmpty {
                                IntroBeads(shown: shown, beads: model.introBeads)
                            }
                        }
                        .shadow(color: .black.opacity(0.45 * depth), radius: 18, y: 8)

                    NotchGlow(
                        shoulder: shown.shoulder,
                        radius: shown.radius,
                        width: shown.width,
                        height: shown.height,
                        envelope: model.edgeGlow,
                        travel: model.edgeGlowTravel,
                        color: model.edgeGlowColor
                    )

                    if model.featured?.isFailure == true && model.presentation != .idle && model.fileDrag == nil {
                        NotchShape(shoulder: shown.shoulder, radius: shown.radius, closesTop: false)
                            .stroke(IslandColor.danger.opacity(0.85), lineWidth: 1.5)
                            .blur(radius: 0.4)
                            .frame(width: shown.width, height: shown.height)
                    }
                }
                // 판만 늘어나고 글자는 그대로 둔다. 1보다 작아지면 하드웨어 노치 바닥이 드러난다.
                .keyframeAnimator(initialValue: 1.0, trigger: model.boingToken) { plate, stretch in
                    plate.scaleEffect(x: 1, y: max(1, stretch), anchor: .top)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 0.08)
                    CubicKeyframe(1.2, duration: 0.17)
                    CubicKeyframe(1.0, duration: 0.2)
                    CubicKeyframe(1.065, duration: 0.15)
                    CubicKeyframe(1.0, duration: 0.22)
                }

                IslandFace(shape: shown)
                    .mask(alignment: .top) {
                        shape.frame(width: shown.width, height: shown.height)
                    }
            }
            .offset(x: shown.shift)
        }
        .keyframeAnimator(initialValue: Shake(), trigger: model.shakeToken) { content, value in
            content.offset(x: value.x)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(7.0, duration: 0.08)
                CubicKeyframe(-6.0, duration: 0.08)
                CubicKeyframe(4.0, duration: 0.07)
                CubicKeyframe(0.0, duration: 0.12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 노치 아래로 삐져나온 맡긴 파일. 마우스를 올리면 더 내려와 부채꼴로 벌어지고, 사진마다 끌어낼 수 있다.
private struct ShelfTuck: View {
    @Environment(AppModel.self) private var model

    /// 맨 앞 사진부터. 뒤로 갈수록 좌우로 어긋나 겹친다.
    private static let fan: [(x: CGFloat, angle: Double)] = [(0, -3), (-9, -10), (9, 8)]

    var body: some View {
        let visible = model.shelfVisible
        let open = visible && model.shelfOpen
        let items = Array(model.shelf.suffix(ShelfLayout.maxCards))
        // 숨을 때는 노치 안으로 쏙 들어가고, 나타날 때 아래로 빠져나온다.
        let reach = visible ? (open ? ShelfLayout.openPeek : ShelfLayout.peek) : -4
        let spread: CGFloat = open ? 2.6 : 1
        let card = ShelfLayout.card
        let tilt = open ? 1.6 : 1
        // 배지는 보이는 아랫단에 걸치고, 벌리면 사진 옆 가운데로 내려온다.
        let badgeY = open ? card / 2 - ShelfBadge.size / 2 : card - reach / 2 - 6
        // 기울어진 사진은 각도만큼 옆으로 넓어진다. 양쪽 배지가 같은 틈을 두도록 바깥 사진의 실제 끝에서 잰다.
        let leftEdge = items.count > 1
            ? -Self.fan[1].x * spread + Self.halfWidth(card, degrees: Self.fan[1].angle * tilt)
            : Self.halfWidth(card, degrees: Self.fan[0].angle * tilt)
        let rightEdge = items.count > 2
            ? Self.fan[2].x * spread + Self.halfWidth(card, degrees: Self.fan[2].angle * tilt)
            : Self.halfWidth(card, degrees: Self.fan[0].angle * tilt)
        let gap: CGFloat = open ? 5 : 0

        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let slot = min(items.count - 1 - index, Self.fan.count - 1)
                ShelfCard(item: item, grabbed: model.shelfGrabsAll)
                    .rotationEffect(.degrees(Self.fan[slot].angle * tilt))
                    .offset(x: Self.fan[slot].x * spread)
                    .gesture(drag([item.id]))
            }
            if model.shelf.count > 1 {
                ShelfBadge(text: "\(model.shelf.count)")
                    // 접혀 있을 때는 사진 끝에 반쯤 걸친다.
                    .offset(x: open ? rightEdge + gap + ShelfBadge.size / 2 : rightEdge, y: badgeY)
                    .gesture(drag(model.shelf.map(\.id)))
            }
            ShelfClearButton()
                .offset(x: -(leftEdge + gap + ShelfBadge.size / 2), y: badgeY)
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
        }
        .keyframeAnimator(initialValue: Shake(), trigger: model.shelfRefusalToken) { content, value in
            content.offset(x: value.x)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(6.0, duration: 0.07)
                CubicKeyframe(-5.0, duration: 0.08)
                CubicKeyframe(3.5, duration: 0.07)
                CubicKeyframe(-2.0, duration: 0.07)
                CubicKeyframe(0.0, duration: 0.1)
            }
        }
        .frame(width: ShelfLayout.card, height: ShelfLayout.card)
        .overlay(alignment: .bottom) {
            if visible && model.shelfRefusalShowing {
                ShelfLimitToast()
                    .fixedSize()
                    .offset(y: 30)
                    .transition(.offset(y: -6).combined(with: .opacity))
            }
        }
        .padding(.top, model.metrics.height - ShelfLayout.card + reach)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.66), value: open)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: visible)
    }

    private static func halfWidth(_ side: CGFloat, degrees: Double) -> CGFloat {
        let radians = abs(degrees) * .pi / 180
        return side * (cos(radians) + sin(radians)) / 2
    }

    private func drag(_ ids: [ShelfItem.ID]) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { _ in
            model.dragFromShelf(ids)
        }
    }
}

/// 맡긴 파일을 한 번에 비운다. 올리면 빨갛게 바뀌어 지운다는 걸 먼저 알린다.
private struct ShelfClearButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovered = false

    var body: some View {
        Button {
            model.clearShelf()
        } label: {
            ShelfBadge(systemImage: "xmark", fill: hovered ? IslandColor.danger : IslandColor.plate)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct ShelfLimitToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandColor.warning)
            Text(model.text(.shelfLimit, ShelfLayout.maxCards))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(IslandColor.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(IslandColor.plate))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    /// ⌘를 눌러 같이 끌려 나갈 사진은 테두리가 맡기기 색으로 바뀐다.
    var grabbed = false

    var body: some View {
        let inner = ShelfLayout.card - 4
        Group {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .padding(3)
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(grabbed ? IslandColor.shelf : .white))
        .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1)
        .scaleEffect(grabbed ? 1.06 : 1)
        .contentShape(Rectangle())
    }
}

private struct ShelfBadge: View {
    static let size: CGFloat = 16
    var text: String?
    var systemImage: String?
    var fill: Color = IslandColor.plate

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 7.5, weight: .heavy))
            } else if let text {
                // 글자 상자 가운데에 놓으면 숫자는 위·왼쪽으로 치우친다. 잰 만큼 되돌린다.
                Text(text)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .offset(x: 0.35, y: 0.45)
            }
        }
        .foregroundStyle(.white)
        .frame(minWidth: Self.size, minHeight: Self.size)
        .padding(.horizontal, text.map { $0.count > 1 ? 3 : 0 } ?? 0)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        // 픽셀 사이에 걸리면 글자만 픽셀에 붙고 원은 그대로라 어긋난다. 한 장으로 그려서 같이 움직인다.
        .drawingGroup()
        .contentShape(Capsule())
    }
}

/// 화면 효과와 함께 노치 윤곽을 그대로 따라가는 빛.
private struct NotchGlow: View {
    var shoulder: CGFloat
    var radius: CGFloat
    var width: CGFloat
    var height: CGFloat
    var envelope: Double
    var travel: Double
    var color: Color

    /// 선 위쪽 글로우가 노치 바닥에 가려지지 않는 거리.
    private let bottomBleed: CGFloat = 2.7

    var body: some View {
        let shape = NotchShape(shoulder: shoulder, radius: radius, closesTop: false, bottomBleed: bottomBleed)
        let run = roll(length: 0.16, finish: 0.5)
        streak(shape, from: run.tail, to: run.head, width: 1.35, blur: 2.6)
            .opacity(lineOpacity)
            .frame(width: width, height: height, alignment: .top)
            .padding(.bottom, bottomBleed + 8)
            .allowsHitTesting(false)
    }

    /// 화면이 천천히 밝아지는 동안에도 선은 바로 보인다. 사라질 때만 같이 꺼진다.
    /// 효과가 다 찬(1) 뒤, 사라지기 전에 따라가기 시작해야 이어받는 순간 튀지 않는다.
    private var lineOpacity: Double {
        guard envelope > 0.001 else { return 0 }
        if travel < 0.3 { return 1 }
        return envelope
    }

    /// 왼쪽 위에서 길이가 0부터 늘어나고, 오른쪽 끝에 붙는 동안 0으로 말린다.
    private func roll(length: CGFloat, finish: Double) -> (tail: CGFloat, head: CGFloat) {
        let lead = 0.055
        let phase = min(1, max(0, (travel - lead) / finish))
        let head = chew(easedEnd(phase, moveEnd: 0.74))
        let settle = 0.9
        let t = min(1, max(0, (head - settle) / (1 - settle)))
        let close = t * t * (3 - 2 * t)
        let tail = max(0, head - Double(length) * (1 - close))
        return (CGFloat(min(tail, head)), CGFloat(head))
    }

    /// 끝만 아주 조금 늘린다. 그 앞의 속도는 그대로다.
    private func easedEnd(_ phase: Double, moveEnd: Double) -> Double {
        let endStart = 0.82
        let stretch = 1.15
        let phaseAtEnd = endStart * moveEnd
        if phase <= phaseAtEnd { return phase / moveEnd }
        let endDuration = (1 - endStart) * moveEnd * stretch
        let t = min(1, (phase - phaseAtEnd) / endDuration)
        return endStart + (1 - endStart) * t
    }

    /// 양끝에 붙었다가 가운데를 빨리 지난다.
    private func chew(_ linear: Double) -> Double {
        let smooth = linear * linear * (3 - 2 * linear)
        return smooth * smooth * (3 - 2 * smooth)
    }

    @ViewBuilder
    private func streak(_ shape: NotchShape, from: CGFloat, to: CGFloat, width: CGFloat, blur: CGFloat) -> some View {
        let start = min(max(0, from), 1)
        let end = min(max(start, to), 1)
        if end > start + 0.0008 {
            ZStack {
                shape
                    .trim(from: start, to: end)
                    .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: width * 3.2, lineCap: .round))
                    .blur(radius: blur)
                shape
                    .trim(from: start, to: end)
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

}

/// 모양을 목표까지 직접 보간한다. 진행 중에 목표가 바뀌면 지금 보이는 모양에서 다시 출발한다.
/// 스프링은 시각으로 계산한다. 바탕화면 보기처럼 창이 스냅샷으로 얼면, 그 사이 진행한 만큼은
/// 보기가 끝나는 순간 한 프레임에 튀어서 보인다. 그래서 그 핫코너를 누르는 동안은 스프링을 멈춘다.
private struct MorphingNotch<Content: View>: View {
    let target: IslandMetrics
    var reduceMotion: Bool
    /// 켤 때 인사처럼 모양을 밖에서 매 프레임 그릴 때. 스프링을 다시 걸지 않는다.
    var instant = false
    @ViewBuilder var content: (IslandMetrics) -> Content

    @State private var playback = MorphPlayback()

    var body: some View {
        content(playback.shown ?? target)
            .transaction { $0.animation = nil }
            .onChange(of: target, initial: true) { _, new in
                playback.retarget(new, reduceMotion: reduceMotion, instant: instant)
            }
            .onDisappear { playback.stop() }
    }
}

/// 스프링은 진행 값만 움직인다. 폭·높이·어깨를 따로 튀기면 보정된 세로보다 더 작아진다.
@MainActor
@Observable
private final class MorphPlayback {
    private(set) var shown: IslandMetrics?
    private var from: IslandMetrics?
    private var goal: IslandMetrics?
    private var began: CFTimeInterval?
    /// 핫코너로 창이 얼어 있는 동안 유지하는 스프링 진행. 벽시계로는 더 가지 않는다.
    private var heldElapsed: CFTimeInterval?
    private var curve = MorphCurve.morph
    private let ticker = MorphTicker()

    init() {
        ticker.onFrame = { [weak self] in
            self?.step()
        }
    }

    func retarget(_ target: IslandMetrics, reduceMotion: Bool, instant: Bool) {
        let origin = visible() ?? target
        if shown == nil || instant || origin == target {
            commit(target)
            return
        }
        from = origin
        goal = target
        let shrinking = target.height + 4 < origin.height || target.width + 8 < origin.width
        if shrinking {
            curve = .settle
        } else if reduceMotion {
            curve = .ease(0.18)
        } else {
            curve = .morph
        }
        heldElapsed = nil
        began = CACurrentMediaTime()
        shown = origin
        ticker.start()
        if !ticker.isRunning {
            commit(target)
        }
    }

    func stop() {
        commit(goal ?? shown ?? from)
    }

    private func step() {
        guard let from, let goal, began != nil else {
            ticker.stop()
            return
        }
        let now = CACurrentMediaTime()
        if ExposeCorners.isHeld {
            if heldElapsed == nil {
                heldElapsed = now - (began ?? now)
            }
            return
        }
        if let heldElapsed {
            began = now - heldElapsed
            self.heldElapsed = nil
        }
        guard let began else { return }
        let elapsed = now - began
        if curve.settled(elapsed) {
            commit(goal)
            return
        }
        shown = from.morphed(to: goal, progress: CGFloat(curve.value(elapsed)))
    }

    /// 지금 화면에 있는 모양. 목표가 바뀌면 여기서부터 다시 잇는다.
    private func visible() -> IslandMetrics? {
        guard let from, let goal else { return shown }
        let elapsed = heldElapsed ?? {
            guard let began else { return 0 }
            return CACurrentMediaTime() - began
        }()
        return from.morphed(to: goal, progress: CGFloat(curve.value(elapsed)))
    }

    private func commit(_ target: IslandMetrics?) {
        ticker.stop()
        began = nil
        heldElapsed = nil
        guard let target else { return }
        from = target
        goal = target
        shown = target
    }
}

/// 미션 컨트롤, 응용 프로그램 윈도우, 바탕화면 보기는 노치 창을 그 순간 그림으로 얼린다.
/// 커서가 그 모서리에 있는 동안 스프링을 멈추면, 모서리에서 나온 뒤 이어서 움직인다.
enum ExposeCorners {
    private enum Corner: String, CaseIterable {
        case tl, tr, bl, br

        func point(in frame: CGRect) -> CGPoint {
            switch self {
            case .bl: return CGPoint(x: frame.minX, y: frame.minY)
            case .br: return CGPoint(x: frame.maxX, y: frame.minY)
            case .tl: return CGPoint(x: frame.minX, y: frame.maxY)
            case .tr: return CGPoint(x: frame.maxX, y: frame.maxY)
            }
        }
    }

    /// Dock의 `wvous-*-corner`. 2는 미션 컨트롤, 3은 응용 프로그램 윈도우, 4는 바탕화면.
    private static let exposeActions: Set<Int> = [2, 3, 4]
    private static var actions: [Corner: Int] = [:]
    private static var modifiers: [Corner: NSEvent.ModifierFlags] = [:]
    private static var readAt: CFTimeInterval = 0

    static var isHeld: Bool {
        refreshIfNeeded()
        guard !actions.isEmpty else { return false }
        let flags = NSEvent.modifierFlags.intersection([.shift, .control, .option, .command])
        let mouse = NSEvent.mouseLocation
        let reach: CGFloat = 30
        for screen in NSScreen.screens {
            let frame = screen.frame
            for (corner, action) in actions where exposeActions.contains(action) {
                let required = modifiers[corner, default: []]
                if !required.isEmpty, !flags.contains(required) { continue }
                let point = corner.point(in: frame)
                if abs(mouse.x - point.x) <= reach, abs(mouse.y - point.y) <= reach {
                    return true
                }
            }
        }
        return false
    }

    private static func refreshIfNeeded() {
        let now = CACurrentMediaTime()
        if now - readAt < 2 { return }
        readAt = now
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        var actions: [Corner: Int] = [:]
        var modifiers: [Corner: NSEvent.ModifierFlags] = [:]
        for corner in Corner.allCases {
            let action = (domain["wvous-\(corner.rawValue)-corner"] as? NSNumber)?.intValue ?? 0
            guard action != 0 else { continue }
            actions[corner] = action
            let raw = (domain["wvous-\(corner.rawValue)-modifier"] as? NSNumber)?.intValue ?? 0
            modifiers[corner] = modifierFlags(raw)
        }
        self.actions = actions
        self.modifiers = modifiers
    }

    /// Dock이 저장하는 수정자 키. `CGEventFlags`의 시프트·컨트롤·옵션·커맨드 비트다.
    private static func modifierFlags(_ raw: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if raw & (1 << 17) != 0 { flags.insert(.shift) }
        if raw & (1 << 18) != 0 { flags.insert(.control) }
        if raw & (1 << 19) != 0 { flags.insert(.option) }
        if raw & (1 << 20) != 0 { flags.insert(.command) }
        return flags
    }
}

/// 접힐 때는 끝에 다시 부풀지 않고, 펼칠 때는 한 번 넘친 뒤 앉는다. 값은 SwiftUI 스프링과 같다.
private enum MorphCurve {
    case spring(IntroSpring)
    case ease(Double)

    static let morph = MorphCurve.spring(IntroSpring(response: 0.46, damping: 0.74))
    static let settle = MorphCurve.spring(IntroSpring(response: 0.46, damping: 1))

    func value(_ time: Double) -> Double {
        switch self {
        case .spring(let spring):
            return spring.step(time)
        case .ease(let duration):
            let x = min(1, max(0, time / max(duration, 0.01)))
            return x < 0.5 ? 2 * x * x : 1 - (-2 * x + 2) * (-2 * x + 2) / 2
        }
    }

    func settled(_ time: Double) -> Bool {
        if time > 1.2 { return true }
        let now = value(time)
        let ahead = value(time + 1.0 / 120)
        return abs(now - 1) < 0.0015 && abs(ahead - now) < 0.00025
    }
}

/// 화면 주사율에 맞춰 모양 스프링을 민다. SwiftUI 애니메이션과 따로 돈다.
private final class MorphTicker: NSObject {
    var onFrame: (() -> Void)?
    private var link: CADisplayLink?
    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame?()
    }
}

/// 접힌 노치의 양쪽 끝. 에이전트 작업은 왼쪽 아이콘만, 그 외 알림은 오른쪽 아이콘과 개수 배지.
private struct PeekContent: View {
    @Environment(AppModel.self) private var model
    let metrics: IslandMetrics
    let notices: [NoticeGroup]
    let agents: [NoticeGroup]

    var body: some View {
        HStack(spacing: 0) {
            if !agents.isEmpty {
                HStack(spacing: IslandMetrics.peekAgentSpacing) {
                    ForEach(agents.reversed()) { group in
                        ActivityIcon(activity: group.latest, size: IslandMetrics.peekIcon)
                            .background { AgentAura(size: IslandMetrics.peekIcon, color: group.latest.peekAura) }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(.leading, metrics.shoulder + IslandMetrics.peekInset)
            }
            Spacer(minLength: 0)
            if !notices.isEmpty {
                HStack(spacing: IslandMetrics.peekSpacing) {
                    ForEach(notices) { group in
                        PeekNoticeIcon(group: group)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .scale(scale: 0.4).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.trailing, metrics.shoulder + IslandMetrics.peekInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: agents.map(\.id))
        .animation(IslandMotion.morph, value: notices.map(\.id))
        .contentShape(Rectangle())
        .onTapGesture {
            model.expandNow()
        }
    }
}

/// 오른쪽 알림 아이콘. 방금 온 알림이면 노치 밑에서 옆으로 쏙 나와 눌렸다 튀어 서고, 배지가 뒤따라 붙는다.
/// 같은 앱 알림이 더 오면 아이콘이 톡 튀고 숫자가 바뀐다. 펼쳤다 접은 뒤 다시 보일 때는 튀지 않는다.
private struct PeekNoticeIcon: View {
    let group: NoticeGroup
    @State private var waiting: Bool
    @State private var arrivals = 0
    @State private var bumps = 0

    init(group: NoticeGroup) {
        self.group = group
        _waiting = State(initialValue: Date().timeIntervalSince(group.latest.createdAt) < 1.2)
    }

    var body: some View {
        ActivityIcon(activity: group.latest, size: IslandMetrics.peekIcon)
            .keyframeAnimator(initialValue: Squish.rest, trigger: arrivals) { icon, pose in
                icon
                    .scaleEffect(x: pose.x, y: pose.y, anchor: .bottom)
                    .offset(x: pose.lift)
                    .opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    MoveKeyframe(0.5)
                    LinearKeyframe(0.5, duration: 0.06)
                    CubicKeyframe(1.08, duration: 0.18)
                    CubicKeyframe(0.91, duration: 0.1)
                    CubicKeyframe(1.03, duration: 0.13)
                    CubicKeyframe(1, duration: 0.15)
                }
                KeyframeTrack(\.y) {
                    MoveKeyframe(0.5)
                    LinearKeyframe(0.5, duration: 0.06)
                    CubicKeyframe(0.94, duration: 0.18)
                    CubicKeyframe(1.08, duration: 0.1)
                    CubicKeyframe(0.98, duration: 0.13)
                    CubicKeyframe(1, duration: 0.15)
                }
                KeyframeTrack(\.lift) {
                    MoveKeyframe(-16)
                    LinearKeyframe(-16, duration: 0.06)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 0.06)
                    LinearKeyframe(1, duration: 0.1)
                }
            }
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bumps) { icon, scale in
                icon.scaleEffect(scale, anchor: .bottom)
            } keyframes: { _ in
                CubicKeyframe(1.16, duration: 0.1)
                CubicKeyframe(0.95, duration: 0.12)
                CubicKeyframe(1, duration: 0.16)
            }
            .overlay(alignment: .topTrailing) {
                DockBadge(count: group.count)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: arrivals) { badge, scale in
                        badge
                            .scaleEffect(scale)
                            .opacity(min(1, Double(scale) * 3))
                    } keyframes: { _ in
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.3)
                        CubicKeyframe(1.28, duration: 0.12)
                        CubicKeyframe(0.94, duration: 0.1)
                        CubicKeyframe(1, duration: 0.12)
                    }
                    .offset(x: 3, y: -3)
            }
            .opacity(waiting ? 0 : 1)
            .onAppear {
                guard waiting else { return }
                waiting = false
                arrivals += 1
            }
            .onChange(of: group.latest.id) {
                bumps += 1
            }
    }
}

/// 왼쪽 아이콘 뒤의 옅은 빛. 아이콘과 같은 둥근 사각형이고, 아주 조금 숨 쉰다.
private struct AgentAura: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.94 * 0.24, style: .continuous)
            .fill(color.opacity(0.7))
            .frame(width: size * 0.94, height: size * 0.94)
            .blur(radius: 1.4)
            .phaseAnimator([false, true]) { content, inhaling in
                content
                    .scaleEffect(inhaling ? 1.018 : 0.988)
                    .opacity(inhaling ? 1 : 0.78)
            } animation: { _ in
                .easeInOut(duration: 2.6)
            }
    }
}

/// macOS Dock 앱 아이콘의 빨간 개수 배지. 한 자리는 원, 두 자리부터는 옆으로 늘어난다.
private struct DockBadge: View {
    let count: Int

    var body: some View {
        let side = IslandMetrics.peekBadge
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: side * 0.66, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, side * 0.24)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .background {
                Capsule()
                    .fill(IslandColor.dockBadge)
                    .shadow(color: .black.opacity(0.35), radius: 0.8, y: 0.5)
            }
            .fixedSize()
            .animation(.snappy(duration: 0.3), value: count)
    }
}

private struct Shake {
    var x: CGFloat = 0
}

private struct IslandFace: View {
    @Environment(AppModel.self) private var model
    /// 지금 보이는 모양. 알림 아이콘은 이 너비를 따라 오른쪽 끝에 붙는다.
    let shape: IslandMetrics

    /// 각 콘텐츠는 자기 상태의 크기를 값으로 받는다. 사라지는 도중에 모델의 새 크기로 다시 배치되면 글자가 찌그러진다.
    var body: some View {
        let metrics = model.metrics
        let notices = model.noticeGroups
        let agents = model.leftIconsHidden ? [] : model.agentGroups

        ZStack(alignment: .top) {
            if let drag = model.fileDrag {
                // 놓을 자리는 판을 따라 같이 부푼다. 목표 크기로 그리면 점선만 먼저 튀어 나간다.
                DropZoneContent(metrics: shape, target: drag.target)
                    .frame(width: shape.width, height: shape.height, alignment: .top)
                    .transition(IslandMotion.contentTransition)
            } else {
                presentationContent(metrics: metrics, notices: notices, agents: agents)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: model.fileDrag == nil)
    }

    @ViewBuilder
    private func presentationContent(metrics: IslandMetrics, notices: [NoticeGroup], agents: [NoticeGroup]) -> some View {
        switch model.presentation {
        case .idle:
            if metrics.chrome == .peek, !notices.isEmpty || !agents.isEmpty {
                PeekContent(metrics: shape, notices: notices, agents: agents)
                    .frame(width: shape.width, height: shape.height)
                    .transition(IslandMotion.popTransition)
            }
        case .compact:
            CompactIslandContent(metrics: metrics, activity: model.featured)
                .frame(width: metrics.width, height: metrics.height)
                .transition(model.featured?.popsIn == true ? IslandMotion.popTransition : IslandMotion.contentTransition)
        case .expanded:
            ExpandedIslandContent(metrics: metrics)
                .frame(width: metrics.width, height: metrics.height, alignment: .top)
                .transition(IslandMotion.expandedTransition)
        }
    }
}

/// 파일을 끌고 노치에 다가오면 보이는 놓을 자리. 왼쪽은 AirDrop, 오른쪽은 맡기기.
private struct DropZoneContent: View {
    @Environment(AppModel.self) private var model
    let metrics: IslandMetrics
    let target: FileDropTarget?
    @State private var refusals = 0

    private static let airDropIcon = NSSharingService(named: .sendViaAirDrop)?.image

    var body: some View {
        let topInset = model.notch.hasNotch ? model.notch.anchorHeight : 6
        // 판이 부푸는 동안 매 프레임 크기가 바뀐다. 다 자라기 전에는 음수가 될 수 있다.
        let boxWidth = max(0, metrics.width - (metrics.shoulder + 8) * 2)
        let boxHeight = max(0, metrics.height - topInset - 14)
        let half = max(0, (boxWidth - 8) / 2)
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset + 4)
            HStack(spacing: 8) {
                let order: [FileDropTarget] = model.shelfOnLeft ? [.shelf, .airDrop] : [.airDrop, .shelf]
                ForEach(order, id: \.self) { kind in
                    dropSlot(kind)
                        .frame(width: half, height: boxHeight)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: target)
        .onChange(of: target) { _, target in
            // 꽉 찬 칸에 들어서는 순간 고개를 젓고 트랙패드로도 한 번 툭 알린다.
            guard target == .shelf, model.shelfFull else { return }
            refusals += 1
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    @ViewBuilder
    private func dropSlot(_ kind: FileDropTarget) -> some View {
        switch kind {
        case .airDrop:
            slot(kind, title: "AirDrop", idle: model.text(.airdropIdle), armed: model.text(.airdropArmed)) {
                if let icon = Self.airDropIcon {
                    Image(nsImage: icon).resizable()
                }
            }
        case .shelf:
            slot(
                kind,
                title: model.text(.shelfTitle),
                count: model.shelf.isEmpty || model.shelfFull ? nil : "\(model.shelf.count)/\(ShelfLayout.maxCards)",
                idle: shelfIdle,
                armed: shelfArmed,
                blocked: model.shelfFull,
                warns: model.shelfFull || model.shelfOverflowing
            ) {
                ZStack {
                    Circle().fill(model.shelfFull ? IslandColor.warning : IslandColor.shelf)
                    Image(systemName: model.shelfFull ? "tray.full.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .keyframeAnimator(initialValue: Shake(), trigger: refusals) { content, value in
                content.offset(x: value.x)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(7.0, duration: 0.07)
                    CubicKeyframe(-6.0, duration: 0.08)
                    CubicKeyframe(4.0, duration: 0.07)
                    CubicKeyframe(-2.0, duration: 0.07)
                    CubicKeyframe(0.0, duration: 0.1)
                }
            }
        }
    }

    private var shelfIdle: String {
        let room = ShelfLayout.maxCards - model.shelf.count
        if model.shelf.isEmpty { return model.text(.shelfEmpty) }
        return room > 0
            ? model.text(.shelfRoom, room)
            : model.text(.shelfFull, model.shelf.count, ShelfLayout.maxCards)
    }

    private var shelfArmed: String {
        let room = ShelfLayout.maxCards - model.shelf.count
        if room <= 0 { return model.text(.shelfArmedFull, ShelfLayout.maxCards) }
        if model.shelfOverflowing { return model.text(.shelfArmedSome, room, ShelfLayout.maxCards) }
        return model.text(.shelfArmed)
    }

    /// `blocked`면 놓아도 받지 않는다. `warns`면 위에 올렸을 때 다 받지 못한다고 주황으로 알린다.
    private func slot(
        _ slot: FileDropTarget,
        title: String,
        count: String? = nil,
        idle: String,
        armed: String,
        blocked: Bool = false,
        warns: Bool = false,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        let hovered = target == slot
        let warning = hovered && warns
        let active = hovered && !blocked
        let lit = active || warning
        let dimmed = target != nil && !hovered
        let tint = warning ? IslandColor.warning : slot == .airDrop ? IslandColor.airDrop : IslandColor.shelf
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(lit ? 0.16 : 0))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(lit ? tint : Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            VStack(spacing: 6) {
                icon()
                    .frame(width: 36, height: 36)
                    .scaleEffect(active && !warning ? 1.1 : 1)
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .foregroundStyle(IslandColor.primary)
                        if let count {
                            Text(count)
                                .monospacedDigit()
                                .foregroundStyle(warning ? IslandColor.warning : IslandColor.secondary)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    // 같은 자리에서 겹쳐 바래면 두 줄이 포개져 읽히지 않는다. 위로 밀어 올리며 바꾼다.
                    ZStack {
                        Text(hovered ? armed : idle)
                            .id(hovered)
                            .transition(
                                .asymmetric(
                                    insertion: .offset(y: 8).combined(with: .opacity),
                                    removal: .offset(y: -8).combined(with: .opacity)
                                )
                            )
                    }
                    .font(.system(size: 10.5, weight: warning ? .semibold : .medium))
                    .foregroundStyle(warning ? IslandColor.warning : IslandColor.secondary)
                    .frame(height: 14)
                    .clipped()
                }
            }
            .fixedSize()
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// 켤 때 인사의 모찌 방울. 몸통과 같이 흐린 뒤 잘라내서, 가까우면 늘어진 목으로 이어지고 멀어지면 끊긴다.
private struct IntroBeads: View {
    let shown: IslandMetrics
    let beads: [IntroBead]
    private let reach: CGFloat = 200

    var body: some View {
        Canvas { context, size in
            // 위 어깨의 오목한 곡선까지 흐리면 메뉴 막대 쪽이 메워진다. 목이 생기는 아래만 그린다.
            context.clip(to: Path(CGRect(x: 0, y: 9, width: size.width, height: size.height)))
            context.addFilter(.alphaThreshold(min: 0.5, color: IslandColor.plate))
            context.addFilter(.blur(radius: 6))
            context.drawLayer { layer in
                let body = NotchShape(shoulder: shown.shoulder, radius: shown.radius)
                    .path(in: CGRect(x: reach, y: 0, width: shown.width, height: shown.height))
                layer.fill(body, with: .color(.black))
                for bead in beads {
                    let x = size.width / 2 + bead.x - shown.shift
                    let oval = CGRect(x: x - bead.rx, y: bead.y - bead.ry, width: bead.rx * 2, height: bead.ry * 2)
                    layer.fill(Path(ellipseIn: oval), with: .color(.black))
                }
            }
        }
        .frame(width: shown.width + reach * 2, height: shown.height + reach)
        .allowsHitTesting(false)
    }
}

private struct IntroMark: View {
    @Environment(AppModel.self) private var model
    let activity: IslandActivity
    @State private var icon = false
    @State private var name = false

    var body: some View {
        HStack(spacing: 11) {
            // 바닥에 붙어 납작하게 떨어졌다가 튀어 선다.
            ActivityIcon(activity: activity, size: 36)
                .scaleEffect(x: icon ? 1 : 1.5, y: icon ? 1 : 0.5, anchor: .bottom)
                .rotationEffect(.degrees(icon ? 0 : -12), anchor: .bottom)
                .opacity(icon ? 1 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.42), value: icon)
            // 글자마다 한 박자씩 늦게 올라온다.
            HStack(spacing: 0) {
                ForEach(Array(activity.leadingLabel(in: model.language).enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .opacity(name ? 1 : 0)
                        .offset(y: name ? 0 : 10)
                        .scaleEffect(name ? 1 : 0.4, anchor: .bottom)
                        .blur(radius: name ? 0 : 4)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.52).delay(0.1 + Double(index) * 0.05),
                            value: name
                        )
                }
            }
            .font(.system(size: 21, weight: .bold, design: .rounded))
        }
        .onAppear {
            icon = true
            name = true
        }
    }
}

/// 작업 완료 때 왼쪽. 아이콘이 노치 안에서 쏙 내려와 바닥에 눌렸다 튀어 서고, 이름이 한 자씩 따라 나온다.
private struct AgentLead: View {
    @Environment(AppModel.self) private var model
    let activity: IslandActivity
    @State private var shown = false

    var body: some View {
        let letters = Array(activity.leadingLabel(in: model.language))
        HStack(spacing: 6) {
            ActivityIcon(activity: activity, size: activity.compactIconSize)
                .opacity(shown ? 1 : 0)
                .keyframeAnimator(initialValue: Squish.rest, trigger: shown) { icon, pose in
                    icon
                        .scaleEffect(x: pose.x, y: pose.y, anchor: .bottom)
                        .offset(y: pose.lift)
                        .opacity(pose.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        MoveKeyframe(0.4)
                        LinearKeyframe(0.4, duration: 0.1)
                        CubicKeyframe(0.9, duration: 0.15)
                        CubicKeyframe(1.2, duration: 0.1)
                        CubicKeyframe(0.95, duration: 0.14)
                        CubicKeyframe(1, duration: 0.16)
                    }
                    KeyframeTrack(\.y) {
                        MoveKeyframe(0.4)
                        LinearKeyframe(0.4, duration: 0.1)
                        CubicKeyframe(1.16, duration: 0.15)
                        CubicKeyframe(0.8, duration: 0.1)
                        CubicKeyframe(1.05, duration: 0.14)
                        CubicKeyframe(1, duration: 0.16)
                    }
                    KeyframeTrack(\.lift) {
                        MoveKeyframe(-9)
                        LinearKeyframe(-9, duration: 0.1)
                        CubicKeyframe(0, duration: 0.15)
                    }
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.1)
                        LinearKeyframe(1, duration: 0.08)
                    }
                }
            HStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .opacity(shown ? 1 : 0)
                        .offset(x: shown ? 0 : -5, y: shown ? 0 : 5)
                        .blur(radius: shown ? 0 : 3)
                        .animation(
                            .spring(response: 0.36, dampingFraction: 0.62).delay(0.2 + Double(index) * 0.026),
                            value: shown
                        )
                }
            }
            .lineLimit(1)
        }
        .onAppear { shown = true }
    }
}

/// 작업 완료 때 오른쪽 결과. 아이콘이 앉은 뒤 한 자씩 뿅 튀어나온다.
private struct AgentTrail: View {
    @Environment(AppModel.self) private var model
    let activity: IslandActivity
    @State private var shown = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(activity.trailingLabel(in: model.language).enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .scaleEffect(shown ? 1 : 0.3)
                    .rotationEffect(.degrees(shown ? 0 : 14))
                    .offset(y: shown ? 0 : 4)
                    .opacity(shown ? 1 : 0)
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.48).delay(0.34 + Double(index) * 0.06),
                        value: shown
                    )
            }
        }
        .foregroundStyle(activity.tint)
        .onAppear { shown = true }
    }
}

private struct Squish {
    var x: CGFloat
    var y: CGFloat
    var lift: CGFloat
    var opacity: Double

    static let rest = Squish(x: 1, y: 1, lift: 0, opacity: 1)
}

private struct CompactIslandContent: View {
    @Environment(AppModel.self) private var model
    let metrics: IslandMetrics
    let activity: IslandActivity?

    var body: some View {
        // 귀가 비어도 폭을 지키도록 빈 칸 위에 얹는다. 빈 뷰에 건 frame은 폭이 사라져 글자가 노치 밑으로 밀린다.
        ZStack {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: metrics.ear)
                    .overlay(alignment: .leading) { ear(activity, alignment: .leading) }
                Color.clear
                    .frame(width: metrics.camera)
                Color.clear
                    .frame(width: metrics.ear)
                    .overlay(alignment: .trailing) { ear(activity, alignment: .trailing) }
            }
            if let activity, activity.isIntro {
                IntroMark(activity: activity)
                    .id(activity.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, metrics.camera > 0 ? 0 : 4)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(IslandColor.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            model.expandNow()
        }
    }

    @ViewBuilder
    private func ear(_ activity: IslandActivity?, alignment: Alignment) -> some View {
        if let activity, activity.popsIn {
            if alignment == .leading {
                AgentLead(activity: activity)
                    .id(activity.id)
                    .padding(.leading, 14)
            } else {
                AgentTrail(activity: activity)
                    .id(activity.id)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else if let activity, !activity.isIntro {
            if alignment == .leading {
                HStack(spacing: 6) {
                    ActivityIcon(activity: activity, size: activity.compactIconSize)
                    Text(activity.leadingLabel(in: model.language))
                        .lineLimit(1)
                        .foregroundStyle(activity.isUpdateNotice ? activity.tint : IslandColor.primary)
                }
                .padding(.leading, 14)
            } else {
                trailing(activity)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func trailing(_ activity: IslandActivity) -> some View {
        if activity.isUpdateNotice, let progress = model.updateProgress {
            UpdateRing(progress: progress)
                .frame(width: 14, height: 14)
        } else if let percent = activity.percent {
            HStack(spacing: 0) {
                Text("\(percent)")
                    .contentTransition(.numericText(value: Double(percent)))
                Text("%")
            }
            .monospacedDigit()
            .foregroundStyle(activity.tint)
            .animation(.snappy(duration: 0.35), value: percent)
        } else if !activity.trailingLabel(in: model.language).isEmpty {
            Text(activity.trailingLabel(in: model.language))
                .foregroundStyle(activity.tint)
        }
    }
}

private struct ExpandedIslandContent: View {
    @Environment(AppModel.self) private var model
    let metrics: IslandMetrics
    @State private var clearHovered = false
    @State private var closeHovered = false
    @State private var laterHovered = false
    @State private var settingsHovered = false

    var body: some View {
        let topInset = model.notch.hasNotch ? model.notch.anchorHeight : 14
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
            header
                .padding(.horizontal, 18)
                .padding(.bottom, 7)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            ZStack(alignment: .topLeading) {
                if model.showsSetup {
                    SetupView()
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else if model.showsSettings {
                    SettingsView()
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else if model.activities.isEmpty {
                    empty
                        .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
                } else {
                    history
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .offset(y: -8))
                            )
                        )
                }
            }
            .animation(.easeInOut(duration: 0.32), value: model.activities.isEmpty)
            .animation(IslandMotion.morph, value: model.showsSettings)
            .animation(IslandMotion.morph, value: model.showsSetup)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, metrics.shoulder)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("もちノッチ")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
            if !model.showsSetup {
                settingsButton
            }
            Spacer()
            if model.showsSetup {
                if model.setupStatus.remaining > 0 {
                    headerChip(model.text(.later), hovered: laterHovered) {
                        model.finishSetup()
                    }
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { laterHovered = hovering }
                    }
                    .transition(.opacity)
                }
            } else if model.showsSettings {
                headerChip(model.text(.close), hovered: closeHovered) {
                    model.closeSettings()
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { closeHovered = hovering }
                }
                .transition(.opacity)
            } else if !model.activities.isEmpty {
                headerChip(model.text(.clear), hovered: clearHovered, danger: true) {
                    model.clearHistory()
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { clearHovered = hovering }
                }
                .transition(.opacity)
            }
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.22), value: model.activities.isEmpty)
        .animation(.easeInOut(duration: 0.22), value: model.showsSettings)
        .animation(.easeInOut(duration: 0.22), value: model.showsSetup)
        .animation(.easeInOut(duration: 0.22), value: model.setupStatus.remaining)
    }

    private var settingsButton: some View {
        Button {
            model.toggleSettings()
        } label: {
            Image(systemName: model.showsSettings ? "gearshape.fill" : "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    model.showsSettings || settingsHovered ? IslandColor.primary : IslandColor.secondary
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        model.showsSettings || settingsHovered ? IslandColor.rowHighlight : Color.clear
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.showsSettings ? model.text(.helpList) : model.text(.helpSettings))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { settingsHovered = hovering }
        }
    }

    private func headerChip(_ title: String, hovered: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovered ? (danger ? IslandColor.danger : IslandColor.primary) : IslandColor.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        hovered
                            ? (danger ? IslandColor.danger.opacity(0.14) : IslandColor.rowHighlight)
                            : Color.clear
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var history: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(Array(model.activities.enumerated()), id: \.element.id) { index, activity in
                    ActivityRow(activity: activity, order: index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(ListHeightKey.self) { height in
            model.setListHeight(height)
        }
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Text(model.text(.quietTitle))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(model.text(.quietBody))
                .font(.system(size: 12))
                .foregroundStyle(IslandColor.secondary)
        }
        .foregroundStyle(IslandColor.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    var activity: IslandActivity
    /// 위에서 몇 번째 줄인지. 펼칠 때 위에서부터 한 줄씩 내려앉는다.
    var order = 0
    @State private var hovered = false
    @State private var landed = false

    var body: some View {
        Group {
            if !activity.isTappable {
                row
            } else {
                Button {
                    model.open(activity)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
        .opacity(landed ? 1 : 0)
        .offset(y: landed ? 0 : -10)
        .animation(
            .spring(response: 0.42, dampingFraction: 0.74).delay(0.08 + Double(min(order, 6)) * 0.035),
            value: landed
        )
        .onAppear { landed = true }
    }

    private var row: some View {
        HStack(spacing: 11) {
            ActivityIcon(activity: activity, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(activity.expandedTitle(in: model.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandColor.primary)
                        .lineLimit(1)
                    if let badge = activity.expandedBadge(in: model.language) {
                        Text(badge.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(badge.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(badge.color.opacity(0.18)))
                    }
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.relative.localizedString(for: activity.createdAt, relativeTo: context.date))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandColor.secondary)
                            .monospacedDigit()
                    }
                }
                let updating = activity.isUpdateNotice ? model.updateStatus : nil
                let detail = updating ?? activity.expandedDetail(in: model.language)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(IslandColor.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: detail)
                }
                if updating != nil, let progress = model.updateProgress {
                    UpdateProgressBar(progress: progress)
                        .frame(height: 3)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(hovered ? 0.42 : 0.22))
                .opacity(activity.isTappable ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(hovered ? IslandColor.rowHighlight : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// 업데이트를 받는 동안의 얇은 막대. 다 받고 설치를 준비하는 동안은 가득 찬 채로 숨 쉰다.
struct UpdateProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(IslandColor.update)
                    .frame(width: max(proxy.size.height, proxy.size.width * min(progress, 1)))
                    .phaseAnimator([1.0, 0.45]) { content, phase in
                        content.opacity(progress < 1 ? 1 : phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

/// 접힌 노치 귀에 들어가는 작은 원. 다 받고 나면 짧은 호가 돈다.
struct UpdateRing: View {
    var progress: Double

    var body: some View {
        TimelineView(.animation(paused: progress < 1)) { context in
            let spin = progress < 1
                ? 0
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
            ZStack {
                Circle()
                    .stroke(IslandColor.update.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress < 1 ? max(progress, 0.04) : 0.3)
                    .stroke(IslandColor.update, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90 + spin))
                    .animation(.easeOut(duration: 0.2), value: progress)
            }
        }
    }
}

private struct ActivityIcon: View {
    @Environment(AppModel.self) private var model
    var activity: IslandActivity
    var size: CGFloat

    var body: some View {
        if activity.showsAppIcon, let image = Self.appIcon(activity.iconBundleIDs, names: activity.iconAppNames) ?? Self.bundledIcon(activity) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(iconShape)
        } else {
            ZStack {
                iconShape
                    .fill(activity.tint.opacity(activity.usesSoftTile ? 0.18 : 1))
                Image(systemName: activity.symbol)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(activity.usesSoftTile ? activity.tint : Color.white)
                    .symbolEffect(.bounce, value: model.chargePulse)
            }
            .frame(width: size, height: size)
        }
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    }

    private static func appIcon(_ bundleIDs: [String], names: [String]) -> NSImage? {
        // 시스템 아이콘은 뒤에 밝은 판을 깔 수 있다. 우리 아이콘은 넣어 둔 그림만 쓴다.
        if bundleIDs.contains(Bundle.main.bundleIdentifier ?? ""),
           let url = Bundle.main.url(forResource: "MochinotchIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 128, height: 128)
            return image
        }
        let byID = bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        let byName = names.lazy.flatMap { name in folders.lazy.map { URL(fileURLWithPath: "\($0)/\(name).app") } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let url = byID.first ?? byName.first else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        return image
    }

    /// 앱이 없고 CLI만 있을 때. 설치된 앱 아이콘을 못 찾으면 앱에 넣어 둔 아이콘을 쓴다.
    private static func bundledIcon(_ activity: IslandActivity) -> NSImage? {
        guard case .agent(let tool, _, _, _, _) = activity.payload, tool != .custom else { return nil }
        let url = Bundle.main.url(forResource: tool.rawValue, withExtension: "png")
            ?? Bundle.main.url(forResource: tool.rawValue, withExtension: "png", subdirectory: "ToolIcons")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 128, height: 128)
        return image
    }
}

private extension IslandActivity {
    /// 옅은 바탕에 색 기호. 안내(흰색)를 진한 바탕에 두면 기호가 바탕에 묻힌다.
    var usesSoftTile: Bool {
        switch payload {
        case .power, .hint: return true
        default: return false
        }
    }
}
