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

struct IslandMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    /// 노치 좌우로 뻗는 귀의 너비. 글자는 이 안에만 둔다.
    var ear: CGFloat
    var camera: CGFloat

    static func resolve(notch: NotchInfo, presentation: IslandPresentation, rowCount: Int) -> IslandMetrics {
        let cameraW = notch.cameraWidth
        let cameraH = max(notch.anchorHeight, 28)

        switch presentation {
        case .idle:
            if notch.hasNotch {
                return IslandMetrics(width: cameraW, height: cameraH, radius: cameraH / 2, ear: 0, camera: cameraW)
            }
            return IslandMetrics(width: 148, height: 32, radius: 16, ear: 74, camera: 0)

        case .compact:
            let ear: CGFloat = 112
            let height = max(cameraH, 32)
            if notch.hasNotch {
                let width = cameraW + ear * 2
                return IslandMetrics(width: width, height: height, radius: height / 2, ear: ear, camera: cameraW)
            }
            return IslandMetrics(width: 300, height: 36, radius: 18, ear: 150, camera: 0)

        case .expanded:
            let rows = max(rowCount, 1)
            let header: CGFloat = notch.hasNotch ? cameraH + 36 : 52
            let height = min(520, header + CGFloat(rows) * 68 + 18)
            return IslandMetrics(width: 386, height: height, radius: 32, ear: 0, camera: 0)
        }
    }

    func screenRect(notch: NotchInfo) -> CGRect {
        guard notch.screenFrame.width > 0 else { return .zero }
        let x = notch.centerX - width / 2
        let y = notch.screenFrame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
