import AppKit
import SwiftUI

struct IslandRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = model.metrics.radius
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.18) : IslandMotion.morph

        Group {
            if model.metrics.chrome == .badge, let activity = model.badgeActivity {
                NoticeBadge(activity: activity)
                    .onTapGesture { model.expandNow() }
            } else {
                plate(radius: radius, animation: animation)
            }
        }
    }

    private func plate(radius: CGFloat, animation: Animation) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(IslandColor.plate)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(IslandColor.hairline.opacity(model.presentation == .idle ? 0 : 1), lineWidth: 1)
                }
                .overlay {
                    if model.featured?.isFailure == true && model.presentation != .idle {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(IslandColor.danger.opacity(0.85), lineWidth: 1.5)
                            .blur(radius: 0.4)
                    }
                }

            IslandFace()
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .animation(animation, value: model.presentation)
        .animation(animation, value: model.metrics.radius)
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
    }
}

private struct NoticeBadge: View {
    var activity: IslandActivity
    @State private var popped = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ActivityIcon(activity: activity, size: IslandMetrics.badgeIcon, circular: true)
                .background {
                    Circle()
                        .fill(Color.black)
                        .padding(-1)
                }

            Circle()
                .fill(IslandColor.danger)
                .frame(width: IslandMetrics.badgeDot, height: IslandMetrics.badgeDot)
                .overlay {
                    Circle().strokeBorder(Color.black, lineWidth: 0.6)
                }
                .offset(x: 1.5, y: -1.5)
        }
        .frame(width: IslandMetrics.badgeSide, height: IslandMetrics.badgeSide, alignment: .bottomLeading)
        .scaleEffect(popped ? 1 : 0.35, anchor: .bottomLeading)
        .onAppear {
            withAnimation(IslandMotion.morph) {
                popped = true
            }
        }
    }
}

private struct Shake {
    var x: CGFloat = 0
}

private struct IslandFace: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.presentation {
            case .idle:
                Color.clear
            case .compact:
                CompactIslandContent()
                    .transition(.opacity)
            case .expanded:
                ExpandedIslandContent()
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(IslandMotion.content, value: model.presentation)
    }
}

private struct CompactIslandContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let metrics = model.metrics
        let activity = model.featured

        HStack(spacing: 0) {
            ear(activity, alignment: .leading)
                .frame(width: metrics.ear, alignment: .leading)
            Color.clear
                .frame(width: metrics.camera)
            ear(activity, alignment: .trailing)
                .frame(width: metrics.ear, alignment: .trailing)
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
        if let activity {
            if alignment == .leading {
                HStack(spacing: 6) {
                    ActivityIcon(activity: activity, size: 18)
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

    var body: some View {
        let topInset = model.notch.hasNotch ? model.notch.anchorHeight : 14
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
            header
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            if model.activities.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("もちノッチ")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandColor.secondary)
            Spacer()
            if !model.activities.isEmpty {
                Button("지우기") {
                    model.clearHistory()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandColor.secondary)
            }
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
    var circular: Bool = false

    var body: some View {
        if activity.showsAppIcon, let image = Self.appIcon(activity.iconBundleIDs) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(iconShape)
        } else {
            ZStack {
                iconShape
                    .fill(activity.tint.opacity(activity.payloadIsPower ? 0.18 : 1))
                Image(systemName: activity.symbol)
                    .font(.system(size: size * (circular ? 0.42 : 0.48), weight: .bold))
                    .foregroundStyle(activity.payloadIsPower ? activity.tint : Color.white)
                    .symbolEffect(.bounce, value: model.chargePulse)
            }
            .frame(width: size, height: size)
        }
    }

    private var iconShape: AnyShape {
        if circular {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    private static func appIcon(_ bundleIDs: [String]) -> NSImage? {
        for id in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 128, height: 128)
            return image
        }
        return nil
    }
}

private extension IslandActivity {
    var payloadIsPower: Bool {
        if case .power = payload { return true }
        return false
    }
}
