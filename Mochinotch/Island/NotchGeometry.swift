import AppKit

/// 노치(또는 노치가 없을 때의 상단 중앙 알약) 위치.
struct NotchInfo: Equatable {
    var screenFrame: CGRect
    /// 전역 화면 좌표. 원점은 왼쪽 아래.
    var notchFrame: CGRect?
    var hasNotch: Bool

    static let placeholder = NotchInfo(screenFrame: .zero, notchFrame: nil, hasNotch: false)

    var anchorHeight: CGFloat {
        if let notchFrame { return notchFrame.height }
        return 32
    }

    var cameraWidth: CGFloat {
        hasNotch ? (notchFrame?.width ?? 0) : 0
    }

    var centerX: CGFloat {
        notchFrame?.midX ?? screenFrame.midX
    }
}

enum NotchGeometry {
    static func current() -> NotchInfo {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { detect(screen: $0).hasNotch }) {
            return detect(screen: notched)
        }
        if let main = NSScreen.main {
            return detect(screen: main)
        }
        return .placeholder
    }

    /// `auxiliaryTop*Area`는 전역 화면 좌표다. 두 영역 사이 간격이 노치다.
    static func detect(screen: NSScreen) -> NotchInfo {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            if width > 24 {
                let notch = CGRect(
                    x: left.maxX,
                    y: frame.maxY - topInset,
                    width: width,
                    height: topInset
                )
                return NotchInfo(screenFrame: frame, notchFrame: notch, hasNotch: true)
            }
        }

        return NotchInfo(screenFrame: frame, notchFrame: nil, hasNotch: false)
    }
}

enum IslandChrome: Equatable {
    case fill
    /// 접힌 노치가 오른쪽으로만 조금 늘어나 알림 앱 아이콘을 보여 준다.
    case peek
}

struct IslandMetrics: Equatable {
    /// 위 모서리의 휘는 부분까지 포함한 너비.
    var width: CGFloat
    var height: CGFloat
    /// 아래 모서리 반경.
    var radius: CGFloat
    /// 위 모서리가 메뉴 막대로 휘어 나가는 반경.
    var shoulder: CGFloat
    /// 노치 좌우로 뻗는 귀의 너비. 글자는 이 안에만 둔다.
    var ear: CGFloat
    var camera: CGFloat
    var chrome: IslandChrome
    /// 노치 가운데에서 모양 가운데까지의 가로 거리. 오른쪽으로만 늘어날 때 쓴다.
    var shift: CGFloat = 0

    static let peekIcon: CGFloat = 22
    static let peekSpacing: CGFloat = 9
    /// 노치 끝과 첫 아이콘, 마지막 아이콘과 몸통 끝 사이.
    static let peekInset: CGFloat = 6
    static let maxPeekSlots = 5
    /// Dock 배지처럼 아이콘 폭의 절반쯤. 더 작으면 숫자가 안 읽힌다.
    static let peekBadge: CGFloat = 12

    /// `peekSlots`는 접혀 있을 때만 쓴다. 늘어나거나 펼쳐지면 그 모양이 우선이다.
    static func resolve(
        notch: NotchInfo,
        presentation: IslandPresentation,
        rowCount: Int,
        peekSlots: Int = 0
    ) -> IslandMetrics {
        let cameraW = notch.cameraWidth
        let cameraH = max(notch.anchorHeight, 28)

        switch presentation {
        case .idle where peekSlots > 0:
            // 왼쪽 끝은 접힌 노치 그대로 두고, 알림 앱 하나마다 오른쪽 끝을 한 칸씩 민다.
            var metrics = resolve(notch: notch, presentation: .idle, rowCount: rowCount)
            let slots = CGFloat(min(peekSlots, maxPeekSlots))
            let ear = peekInset * 2 + notchShoulder + slots * peekIcon + (slots - 1) * peekSpacing
            metrics.width += ear
            metrics.ear = ear
            metrics.shift = ear / 2
            metrics.chrome = .peek
            return metrics

        case .idle:
            // 휘는 부분까지 노치 폭 안에 넣어, 접혀 있을 때는 하드웨어 노치 뒤로 숨는다.
            if notch.hasNotch {
                return fill(width: cameraW, height: cameraH, radius: notchRadius, shoulder: notchShoulder, ear: 0, camera: cameraW)
            }
            return fill(width: 160, height: 32, radius: notchRadius, shoulder: notchShoulder, ear: 74, camera: 0)

        case .compact:
            // 높이와 모서리는 노치 그대로 두고 옆으로만 늘린다.
            let ear: CGFloat = 112
            if notch.hasNotch {
                return fill(
                    width: cameraW + ear * 2 + notchShoulder * 2,
                    height: cameraH,
                    radius: notchRadius,
                    shoulder: notchShoulder,
                    ear: ear,
                    camera: cameraW
                )
            }
            return fill(width: 300 + notchShoulder * 2, height: 34, radius: notchRadius, shoulder: notchShoulder, ear: 150, camera: 0)

        case .expanded:
            let rows = max(rowCount, 1)
            let header: CGFloat = notch.hasNotch ? cameraH + 36 : 52
            let height = min(maxExpandedHeight, header + CGFloat(rows) * 68 + 18)
            return fill(
                width: 386 + expandedShoulder * 2,
                height: height,
                radius: 30,
                shoulder: expandedShoulder,
                ear: 0,
                camera: 0
            )
        }
    }

    /// 실제 노치 아래 모서리에 가까운 반경.
    private static let notchRadius: CGFloat = 10
    private static let notchShoulder: CGFloat = 6
    private static let expandedShoulder: CGFloat = 16

    private static func fill(
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat,
        shoulder: CGFloat,
        ear: CGFloat,
        camera: CGFloat,
        chrome: IslandChrome = .fill
    ) -> IslandMetrics {
        IslandMetrics(
            width: width,
            height: height,
            radius: radius,
            shoulder: shoulder,
            ear: ear,
            camera: camera,
            chrome: chrome
        )
    }

    static let maxExpandedHeight: CGFloat = 520
    /// 펼친 판의 그림자가 잘리지 않을 여백.
    private static let shadowMargin: CGFloat = 28

    /// 모든 상태를 담는 고정 창. 노치 가운데를 기준으로 좌우 대칭이다.
    static func canvas(notch: NotchInfo) -> CGRect {
        guard notch.screenFrame.width > 0 else { return .zero }
        let plates: [IslandPresentation] = [.idle, .compact, .expanded]
        let widest = plates
            .map { resolve(notch: notch, presentation: $0, rowCount: 0, peekSlots: maxPeekSlots) }
            .map { ($0.width / 2 + abs($0.shift)) * 2 }
            .max() ?? 0
        let width = widest + shadowMargin * 2
        let height = maxExpandedHeight + shadowMargin
        return CGRect(
            x: notch.centerX - width / 2,
            y: notch.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// 두 모양 사이를 `progress`(0은 지금 모양, 1은 `target`)로 잇는다.
    /// 알림이 늘어날 때는 끝과 끝을 그대로 잇는다. 오른쪽으로 치우친 상태에서 펼칠 때만,
    /// 먼저 노치 한가운데로 모은 다음 그 가운데에서 양쪽으로 벌린다.
    func morphed(to target: IslandMetrics, progress: CGFloat) -> IslandMetrics {
        func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
            from + (to - from) * progress
        }
        let expanding = target.height > height + 4
        let recenters = expanding && abs(shift) > 1
        // 치우친 채로 아래로 커지면 오른쪽에서 열리는 느낌이 난다. 가운데로 모인 뒤에 키운다.
        let bloom = recenters ? Self.smooth(progress, from: 0.14) : progress
        var shown = target
        shown.height = lerp(height, target.height, bloom)
        shown.radius = lerp(radius, target.radius, bloom)
        shown.shoulder = lerp(shoulder, target.shoulder, bloom)
        shown.ear = lerp(ear, target.ear, progress)
        shown.camera = lerp(camera, target.camera, progress)

        let left = shift - width / 2
        let right = shift + width / 2
        guard recenters else {
            shown.width = max(1, lerp(width, target.width, progress))
            shown.shift = lerp(shift, target.shift, progress)
            return shown
        }

        let gather = Self.smooth(progress, until: 0.14)
        let gatheredRight = lerp(right, -left, gather)
        let shownLeft = lerp(left, target.shift - target.width / 2, bloom)
        let shownRight = lerp(gatheredRight, target.shift + target.width / 2, bloom)
        shown.width = max(1, shownRight - shownLeft)
        shown.shift = (shownLeft + shownRight) / 2
        return shown
    }

    /// `until`에 1이 되고 그 뒤로는 1을 유지한다. 스프링이 0 아래로 튀면 0이다.
    private static func smooth(_ progress: CGFloat, until end: CGFloat) -> CGFloat {
        guard progress > 0 else { return 0 }
        let u = min(1, progress / end)
        return u * u * (3 - 2 * u)
    }

    /// `from`까지는 0이다가 1에서 1이 된다. 1을 넘으면 스프링이 튀는 만큼 따라간다.
    private static func smooth(_ progress: CGFloat, from start: CGFloat) -> CGFloat {
        guard progress > start else { return 0 }
        guard progress < 1 else { return progress }
        let u = (progress - start) / (1 - start)
        return u * u * (3 - 2 * u)
    }

    func screenRect(notch: NotchInfo) -> CGRect {
        guard notch.screenFrame.width > 0 else { return .zero }
        return CGRect(
            x: notch.centerX + shift - width / 2,
            y: notch.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
