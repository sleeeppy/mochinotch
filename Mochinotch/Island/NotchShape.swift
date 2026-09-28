import SwiftUI

/// 맥북 노치 윤곽. 윗변은 화면 위 끝에 붙고, 위 모서리는 바깥으로 휘어 메뉴 막대로 이어진다.
struct NotchShape: Shape {
    /// 위 모서리가 바깥으로 휘는 반경. 몸통은 좌우로 이만큼 안쪽에 선다.
    var shoulder: CGFloat
    var radius: CGFloat
    /// `false`면 윗변을 긋지 않는다. 테두리를 그릴 때 화면 끝에 선이 생기지 않게.
    var closesTop = true
    /// 아래 선만 이만큼 내린다. 좌우 변의 가로 위치는 그대로다.
    var bottomBleed: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, radius) }
        set {
            shoulder = newValue.first
            radius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(max(shoulder, 0), rect.width / 4, rect.height / 2)
        let bodyWidth = rect.width - top * 2
        let bottom = min(max(radius, 0), bodyWidth / 2, rect.height - top)
        let left = rect.minX + top
        let right = rect.maxX - top
        let floor = rect.maxY + bottomBleed

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + top),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: left, y: floor - bottom))
        path.addQuadCurve(
            to: CGPoint(x: left + bottom, y: floor),
            control: CGPoint(x: left, y: floor)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: floor))
        path.addQuadCurve(
            to: CGPoint(x: right, y: floor - bottom),
            control: CGPoint(x: right, y: floor)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )
        if closesTop {
            path.closeSubpath()
        }
        return path
    }
}
