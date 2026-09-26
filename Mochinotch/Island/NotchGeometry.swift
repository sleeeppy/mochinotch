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
    /// 창 전체를 채우는 검은 판.
    case fill
    /// 노치 오른쪽 끝에 붙는 작은 원. 알림 하나.
    case badge
}

enum IslandAnchor: Equatable {
    case centerTop
    case trailing
}

struct IslandMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    /// 노치 좌우로 뻗는 귀의 너비. 글자는 이 안에만 둔다.
    var ear: CGFloat
    var camera: CGFloat
    var chrome: IslandChrome
    var anchor: IslandAnchor

    /// 시안 A보다 작게. 아이콘 14pt, 점은 그 안에 걸친다.
    static let badgeIcon: CGFloat = 14
    static let badgeDot: CGFloat = 4.5
    static let badgeSide: CGFloat = 17

    static func resolve(
        notch: NotchInfo,
        presentation: IslandPresentation,
        rowCount: Int,
        badge: Bool = false
    ) -> IslandMetrics {
        if badge {
            return IslandMetrics(
                width: badgeSide,
                height: badgeSide,
                radius: badgeSide / 2,
                ear: 0,
                camera: 0,
                chrome: .badge,
                anchor: .trailing
            )
        }

        let cameraW = notch.cameraWidth
        let cameraH = max(notch.anchorHeight, 28)

        switch presentation {
        case .idle:
            if notch.hasNotch {
                return fill(width: cameraW, height: cameraH, radius: cameraH / 2, ear: 0, camera: cameraW)
            }
            return fill(width: 148, height: 32, radius: 16, ear: 74, camera: 0)

        case .compact:
            let ear: CGFloat = 112
            let height = max(cameraH, 32)
            if notch.hasNotch {
                return fill(width: cameraW + ear * 2, height: height, radius: height / 2, ear: ear, camera: cameraW)
            }
            return fill(width: 300, height: 36, radius: 18, ear: 150, camera: 0)

        case .expanded:
            let rows = max(rowCount, 1)
            let header: CGFloat = notch.hasNotch ? cameraH + 36 : 52
            let height = min(520, header + CGFloat(rows) * 68 + 18)
            return fill(width: 386, height: height, radius: 32, ear: 0, camera: 0)
        }
    }

    private static func fill(
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat,
        ear: CGFloat,
        camera: CGFloat
    ) -> IslandMetrics {
        IslandMetrics(
            width: width,
            height: height,
            radius: radius,
            ear: ear,
            camera: camera,
            chrome: .fill,
            anchor: .centerTop
        )
    }

    func screenRect(notch: NotchInfo) -> CGRect {
        guard notch.screenFrame.width > 0 else { return .zero }
        switch anchor {
        case .centerTop:
            return CGRect(
                x: notch.centerX - width / 2,
                y: notch.screenFrame.maxY - height,
                width: width,
                height: height
            )
        case .trailing:
            let rightEdge = notch.notchFrame?.maxX ?? (notch.centerX + 74)
            let band = notch.anchorHeight
            return CGRect(
                x: rightEdge - 2,
                y: notch.screenFrame.maxY - band + (band - height) / 2,
                width: width,
                height: height
            )
        }
    }
}
