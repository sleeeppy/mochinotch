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

/// 노치 아래로 삐져나온 맡긴 파일. 사진 위쪽은 노치 뒤에 숨고 아랫단만 보인다.
enum ShelfLayout {
    static let card: CGFloat = 40
    /// 평소에 노치 아래로 나온 길이.
    static let peek: CGFloat = 11
    /// 마우스를 올려 벌렸을 때 나온 길이.
    static let openPeek: CGFloat = 38
    static let restWidth: CGFloat = 104
    static let openWidth: CGFloat = 200
    static let maxCards = 3
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

    static let peekIcon: CGFloat = 26
    static let peekSpacing: CGFloat = 8.1
    /// 왼쪽은 배지가 없어서 아이콘 사이를 더 붙인다.
    static let peekAgentSpacing: CGFloat = 5
    /// 노치 끝과 첫 아이콘, 마지막 아이콘과 몸통 끝 사이.
    static let peekInset: CGFloat = 6
    static let maxPeekSlots = 5
    /// Dock 배지처럼 아이콘 폭의 절반쯤. 더 작으면 숫자가 안 읽힌다.
    static let peekBadge: CGFloat = 11

    /// `peekSlots`와 `agentSlots`는 접혀 있을 때만 쓴다. 늘어나거나 펼쳐지면 그 모양이 우선이다.
        static func resolve(
        notch: NotchInfo,
        presentation: IslandPresentation,
        rowCount: Int,
        peekSlots: Int = 0,
        agentSlots: Int = 0,
        settingsHeight: CGFloat? = nil,
        listHeight: CGFloat? = nil
    ) -> IslandMetrics {
        let cameraW = notch.cameraWidth
        let cameraH = max(notch.anchorHeight, 28)

        switch presentation {
        case .idle where peekSlots > 0 || agentSlots > 0:
            // 일반 알림은 오른쪽으로, 에이전트 작업은 왼쪽으로. 노치 몸통은 그 자리에 둔다.
            var metrics = resolve(notch: notch, presentation: .idle, rowCount: rowCount)
            let right = peekEar(slots: peekSlots, spacing: peekSpacing)
            let left = peekEar(slots: agentSlots, spacing: peekAgentSpacing)
            metrics.width += left + right
            metrics.ear = right
            metrics.shift = (right - left) / 2
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
            let header: CGFloat = notch.hasNotch ? cameraH + 44 : 58
            if let settingsHeight {
                return fill(
                    width: 386 + expandedShoulder * 2,
                    height: min(maxExpandedHeight, header + settingsHeight),
                    radius: 30,
                    shoulder: expandedShoulder,
                    ear: 0,
                    camera: 0
                )
            }
            let rows = max(rowCount, 1)
            let body = listHeight ?? CGFloat(rows) * 58 + 10
            let height = min(maxExpandedHeight, header + body)
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

    /// 파일을 끌고 노치 가까이 오면 놓을 자리만큼 아래로 커진다. 위에 올라오면 조금 더 부푼다.
    /// 화면 맨 위까지 끌고 가면 Mission Control이 열리므로, 그보다 한참 아래에서 놓을 수 있게 길게 내린다.
    static func dropZone(notch: NotchInfo, targeted: Bool) -> IslandMetrics {
        let header: CGFloat = notch.hasNotch ? max(notch.anchorHeight, 28) : 6
        let grow: CGFloat = targeted ? 1 : 0
        return fill(
            width: 360 + grow * 24 + expandedShoulder * 2,
            height: header + 112 + grow * 12,
            radius: 24,
            shoulder: expandedShoulder,
            ear: 0,
            camera: 0
        )
    }

    /// 노치 밖으로 아이콘 칸만큼 뻗는 폭. 0칸이면 그 방향은 접힌 노치 그대로다.
    private static func peekEar(slots: Int, spacing: CGFloat) -> CGFloat {
        guard slots > 0 else { return 0 }
        let count = CGFloat(min(slots, maxPeekSlots))
        return peekInset * 2 + notchShoulder + count * peekIcon + (count - 1) * spacing
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

    static let maxExpandedHeight: CGFloat = 520    /// 펼친 판의 그림자가 잘리지 않을 여백.
    private static let shadowMargin: CGFloat = 28

    /// 모든 상태를 담는 고정 창. 노치 가운데를 기준으로 좌우 대칭이다.
    static func canvas(notch: NotchInfo) -> CGRect {
        guard notch.screenFrame.width > 0 else { return .zero }
        let plates: [IslandPresentation] = [.idle, .compact, .expanded]
        let widest = plates
            .map { resolve(notch: notch, presentation: $0, rowCount: 0, peekSlots: maxPeekSlots, agentSlots: maxPeekSlots) }
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
    /// 알림이 늘어날 때는 끝과 끝을 그대로 잇는다. 왼쪽이나 오른쪽으로 치우친 상태에서 펼칠 때는,
    /// 먼저 노치 한가운데로 모은 다음 그 가운데에서 양쪽으로 벌린다.
    func morphed(to target: IslandMetrics, progress: CGFloat) -> IslandMetrics {
        func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
            from + (to - from) * progress
        }
        let left = shift - width / 2
        let right = shift + width / 2
        let anchor = gatherAnchor(left: left, right: right)
        let expanding = target.height > height + 4
        let recenters = expanding && anchor.needed
        // 치우친 채로 아래로 커지면 늘어난 쪽에서 열리는 느낌이 난다. 가운데로 모인 뒤에 키운다.
        let bloom = recenters ? Self.smooth(progress, from: 0.14) : progress
        let notchWidth = max(camera, target.camera)
        let notchHeight = min(height, target.height)
        var shown = target
        shown.ear = lerp(ear, target.ear, progress)
        shown.camera = lerp(camera, target.camera, progress)

        if recenters, let anchorLeft = anchor.left, let anchorRight = anchor.right {
            // 귀를 다 접은 뒤에 키우면 왼쪽이 줄었다가 뽀용 하고 벌어진다. 자라는 동안 조금만 모은다.
            let gather = Self.smooth(progress, until: 0.42) * 0.32
            let bloom = progress
            shown.height = lerp(height, target.height, bloom)
            shown.radius = lerp(radius, target.radius, bloom)
            shown.shoulder = lerp(shoulder, target.shoulder, bloom)
            let gatheredLeft = lerp(left, anchorLeft, gather)
            let gatheredRight = lerp(right, anchorRight, gather)
            let shownLeft = lerp(gatheredLeft, target.shift - target.width / 2, bloom)
            let shownRight = lerp(gatheredRight, target.shift + target.width / 2, bloom)
            shown.width = max(1, shownRight - shownLeft)
            shown.shift = (shownLeft + shownRight) / 2
        } else {
            // 세로는 이동 거리가 길다. 같은 비율로 줄이면 양옆이 노치 폭에 먼저 도착하고, 긴 세로가 남아 노치가 비친다.
            let drop = target.height + 4 < height ? Self.easeDown(progress) : bloom
            shown.height = lerp(height, target.height, drop)
            shown.radius = lerp(radius, target.radius, drop)
            shown.shoulder = lerp(shoulder, target.shoulder, drop)
            shown.width = max(1, lerp(width, target.width, bloom))
            shown.shift = lerp(shift, target.shift, bloom)
        }
        // 한쪽으로 치우치거나 노치 아래로 내려온 만큼 세로 변을 카메라 밖으로 민다.
        // 켜고 끄듯 밀면 치우침이나 높이가 1pt를 넘는 순간 벽이 7pt 튄다.
        let offCenter = max(abs(shift), abs(target.shift))
        let hang = shown.height - notchHeight
        let wallWeight = min(1, max(0, max(offCenter, hang)) / 6)
        return shown.covering(notchWidth: notchWidth, notchHeight: notchHeight, wallWeight: wallWeight)
    }

    /// 몸통이 하드웨어 노치보다 작아지거나 한쪽으로 빠져 노치 가장자리가 보이지 않게 한다.
    /// 세로 변은 바깥 폭보다 어깨만큼 안쪽에 있고, 아래 모서리는 거기서 더 들어간다.
    private func covering(notchWidth: CGFloat, notchHeight: CGFloat, wallWeight: CGFloat) -> IslandMetrics {
        var shown = self
        if notchHeight > 1 {
            shown.height = max(shown.height, notchHeight)
        }
        if notchWidth > 1 {
            let lip = shown.wallClearance(notchHeight: notchHeight) * wallWeight
            let leftEdge = min(shown.shift - shown.width / 2, -notchWidth / 2 - lip)
            let rightEdge = max(shown.shift + shown.width / 2, notchWidth / 2 + lip)
            shown.width = max(1, rightEdge - leftEdge)
            shown.shift = (leftEdge + rightEdge) / 2
        }
        return shown
    }

    /// 노치 높이 안에서 실루엣이 카메라 가장자리보다 안으로 들어가는 거리.
    private func wallClearance(notchHeight: CGFloat) -> CGFloat {
        let inset = min(max(shoulder, 0), height / 2)
        let corner = min(max(radius, 0), max(0, height - inset))
        let hardwareRadius: CGFloat = 10
        let straightBottom = max(0, notchHeight - hardwareRadius)
        let curveStart = height - corner
        var bite: CGFloat = 0
        if corner > 0, curveStart < straightBottom {
            let remaining = height - straightBottom
            let t = 1 - sqrt(max(0, remaining / corner))
            bite = t * t * corner
        }
        return inset + bite + 1
    }

    /// 펼치기 전에 돌아올 노치 가장자리. 오른쪽만 늘어났으면 오른쪽 끝을, 왼쪽만 늘어났으면 왼쪽 끝을 당긴다.
    private func gatherAnchor(left: CGFloat, right: CGFloat) -> (needed: Bool, left: CGFloat?, right: CGFloat?) {
        let anchorLeft: CGFloat
        let anchorRight: CGFloat
        if camera > 1 {
            anchorLeft = -camera / 2
            anchorRight = camera / 2
        } else if left < -right {
            anchorLeft = -right
            anchorRight = right
        } else {
            anchorLeft = left
            anchorRight = -left
        }
        let needed = left < anchorLeft - 1 || right > anchorRight + 1
        return (needed, anchorLeft, anchorRight)
    }

    /// `until`에 1이 되고 그 뒤로는 1을 유지한다. 스프링이 0 아래로 튀면 0이다.
    private static func smooth(_ progress: CGFloat, until end: CGFloat) -> CGFloat {
        guard progress > 0 else { return 0 }
        let u = min(1, progress / end)
        return u * u * (3 - 2 * u)
    }

    /// 접힐 때 세로만 앞당긴다. 처음이 더 빠르고, 끝에서는 양옆과 같이 도착한다.
    private static func easeDown(_ progress: CGFloat) -> CGFloat {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return progress }
        return 1 - (1 - progress) * (1 - progress)
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
