import AppKit
import SwiftUI

struct IslandRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.18) : IslandMotion.morph

        plate(metrics: model.metrics, animation: animation)
    }

    /// 창은 고정이고, 모양은 그 안 위 가운데에 붙어 자란다. 글자는 최종 크기로 먼저 놓이고 모양이 그걸 드러낸다.
    private func plate(metrics: IslandMetrics, animation: Animation) -> some View {
        MorphingNotch(target: metrics, animation: animation, instant: model.introDirect) { shown in
            let shape = NotchShape(shoulder: shown.shoulder, radius: shown.radius)
            let depth = min(1, max(0, (shown.height - 70) / 140))

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

                if model.featured?.isFailure == true && model.presentation != .idle {
                    NotchShape(shoulder: shown.shoulder, radius: shown.radius, closesTop: false)
                        .stroke(IslandColor.danger.opacity(0.85), lineWidth: 1.5)
                        .blur(radius: 0.4)
                        .frame(width: shown.width, height: shown.height)
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
    private var lineOpacity: Double {
        guard envelope > 0.001 else { return 0 }
        if travel < 0.47 { return 1 }
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
private struct MorphingNotch<Content: View>: View {
    let target: IslandMetrics
    let animation: Animation
    /// 켤 때 인사처럼 모양을 밖에서 매 프레임 그릴 때. 스프링을 다시 걸지 않는다.
    var instant = false
    @ViewBuilder var content: (IslandMetrics) -> Content

    @State private var base: IslandMetrics?
    @State private var goal: IslandMetrics?
    @State private var progress: CGFloat = 1
    /// 스프링이 그리고 있는 실제 진행. 상태값은 곧바로 1이 되므로 끊김은 여기서 읽는다.
    @State private var clock = MorphClock()

    var body: some View {
        MorphingFrame(
            base: base ?? target,
            goal: goal ?? target,
            progress: progress,
            clock: clock,
            content: content
        )
        .onChange(of: target, initial: true) { _, new in
            guard let base, let goal else {
                base = new
                goal = new
                progress = 1
                clock.value = 1
                return
            }
            self.base = base.morphed(to: goal, progress: clock.value)
            self.goal = new
            guard let base = self.base, base != new else { return }
            if instant {
                self.base = new
                self.goal = new
                progress = 1
                clock.value = 1
                return
            }
            progress = 0
            clock.value = 0
            let shrinking = new.height + 4 < base.height || new.width + 8 < base.width
            withAnimation(shrinking ? IslandMotion.settle : animation) { progress = 1 }
        }
    }
}

/// 스프링은 진행 값만 움직인다. 폭·높이·어깨를 따로 튀기면 보정된 세로보다 더 작아진다.
private struct MorphingFrame<Content: View>: View, Animatable {
    var base: IslandMetrics
    var goal: IslandMetrics
    var progress: CGFloat
    var clock: MorphClock
    var content: (IslandMetrics) -> Content

    var animatableData: CGFloat {
        get { progress }
        set {
            progress = newValue
            clock.value = newValue
        }
    }

    var body: some View {
        content(base.morphed(to: goal, progress: progress))
            .transaction { $0.animation = nil }
    }
}

private final class MorphClock {
    var value: CGFloat = 1
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
                        ActivityIcon(activity: group.latest, size: IslandMetrics.peekIcon)
                            .overlay(alignment: .topTrailing) {
                                DockBadge(count: group.count)
                                    .offset(x: 3, y: -3)
                            }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
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
            switch model.presentation {
            case .idle:
                if metrics.chrome == .peek, !notices.isEmpty || !agents.isEmpty {
                    PeekContent(metrics: shape, notices: notices, agents: agents)
                        .frame(width: shape.width, height: shape.height)
                        .transition(IslandMotion.contentTransition)
                }
            case .compact:
                CompactIslandContent(metrics: metrics, activity: model.featured)
                    .frame(width: metrics.width, height: metrics.height)
                    .transition(IslandMotion.contentTransition)
            case .expanded:
                ExpandedIslandContent(metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height, alignment: .top)
                    .transition(IslandMotion.contentTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                ForEach(Array(activity.leadingText.enumerated()), id: \.offset) { index, letter in
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
        if let activity, !activity.isIntro {
            if alignment == .leading {
                HStack(spacing: 6) {
                    ActivityIcon(activity: activity, size: activity.compactIconSize)
                    Text(activity.leadingText)
                        .lineLimit(1)
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
        if let percent = activity.percent {
            HStack(spacing: 0) {
                Text("\(percent)")
                    .contentTransition(.numericText(value: Double(percent)))
                Text("%")
            }
            .monospacedDigit()
            .foregroundStyle(activity.tint)
            .animation(.snappy(duration: 0.35), value: percent)
        } else if !activity.trailingText.isEmpty {
            Text(activity.trailingText)
                .foregroundStyle(activity.tint)
        }
    }
}

private struct ExpandedIslandContent: View {
    @Environment(AppModel.self) private var model
    let metrics: IslandMetrics
    @State private var clearHovered = false

    var body: some View {
        let topInset = model.notch.hasNotch ? model.notch.anchorHeight : 14
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
            header
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            ZStack(alignment: .topLeading) {
                if model.activities.isEmpty {
                    empty
                        .transition(.opacity.animation(.easeOut(duration: 0.26).delay(0.14)))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, metrics.shoulder)
    }

    private var header: some View {
        HStack {
            Text("もちノッチ")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandColor.secondary)
            Spacer()
            if !model.activities.isEmpty {
                Button {
                    model.clearHistory()
                } label: {
                    Text("지우기")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(clearHovered ? IslandColor.primary : IslandColor.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(clearHovered ? IslandColor.rowHighlight : Color.clear))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { clearHovered = hovering }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.activities.isEmpty)
    }

    private var history: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.activities) { activity in
                    ActivityRow(activity: activity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("지금은 조용해요")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("충전기, 작업 완료, 알림이 여기 쌓여요.")
                .font(.system(size: 12))
                .foregroundStyle(IslandColor.secondary)
        }
        .foregroundStyle(IslandColor.primary)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    var activity: IslandActivity
    @State private var hovered = false

    var body: some View {
        Group {
            if activity.openBundleIDs.isEmpty {
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
        .onHover { hovered = $0 }
    }

    private var row: some View {
        HStack(spacing: 12) {
            ActivityIcon(activity: activity, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.expandedTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandColor.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.relative.localizedString(for: activity.createdAt, relativeTo: Date()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandColor.secondary)
                }
                Text(activity.expandedDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(IslandColor.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovered ? IslandColor.rowHighlight : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct ActivityIcon: View {
    @Environment(AppModel.self) private var model
    var activity: IslandActivity
    var size: CGFloat

    var body: some View {
        if activity.showsAppIcon, let image = Self.appIcon(activity.iconBundleIDs, names: activity.iconAppNames) {
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
        if bundleIDs.contains(Bundle.main.bundleIdentifier ?? ""), let image = NSApp.applicationIconImage {
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
