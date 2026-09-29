import SwiftUI

enum IslandMotion {
    /// 살짝 튀는 스프링. 애플 다이나믹 아일랜드에 가까운 감쇠.
    static let morph: Animation = .spring(response: 0.46, dampingFraction: 0.74, blendDuration: 0.12)
    /// 접힐 때. 같은 속도지만 다 접힌 뒤에 다시 부풀지 않는다.
    static let settle: Animation = .spring(response: 0.46, dampingFraction: 1, blendDuration: 0.12)
    /// 들어올 때는 모양이 먼저 벌어진 뒤 흐림에서 또렷해지고, 나갈 때는 모양이 접히기 전에 빨리 빠진다.
    static let contentTransition: AnyTransition = .asymmetric(
        insertion: AnyTransition(.blurReplace).animation(.easeOut(duration: 0.26).delay(0.1)),
        removal: .opacity.animation(.easeIn(duration: 0.1))
    )
}

/// 한 축의 스프링 응답. SwiftUI 스프링과 같은 `response`, `damping`이다.
struct IntroSpring {
    var response: Double
    var damping: Double

    /// 밖으로 나가며 한 번 크게 넘었다가 앉는다.
    static let pop = IntroSpring(response: 0.5, damping: 0.52)
    /// 한쪽을 톡 내밀되 조금 더 느긋하게.
    static let peek = IntroSpring(response: 0.42, damping: 0.5)
    /// 옆에서 조인 만큼 아래로 뿅 밀려 나온다.
    static let plop = IntroSpring(response: 0.4, damping: 0.5)
    /// 놓은 떡이 가운데로 빠르게 튕겨 들어온다.
    static let recoil = IntroSpring(response: 0.38, damping: 0.55)
    /// 조였던 힘이 옆으로 터진다. 들어올 때보다 빠르다.
    static let fling = IntroSpring(response: 0.35, damping: 0.52)
    /// 옆이 터지는 순간 아래로 나왔던 부분이 위로 확 당겨진다.
    static let snapUp = IntroSpring(response: 0.3, damping: 0.6)
    /// 노치 안으로 돌아올 때. 안에서는 흔들림이 안 보이니 거의 튀지 않는다.
    static let tuck = IntroSpring(response: 0.4, damping: 0.95)
    /// 아래로 눌리는 준비 동작.
    static let drip = IntroSpring(response: 0.46, damping: 0.62)
    /// 바닥. 옆보다 느려서 폭과 높이가 엇박으로 출렁인다.
    static let drop = IntroSpring(response: 0.62, damping: 0.46)
    /// 좌우로 옮겨 갈 때.
    static let slide = IntroSpring(response: 0.52, damping: 0.64)
    /// 떡을 잡아당기듯 무겁게 늘어난다.
    static let pull = IntroSpring(response: 1.1, damping: 0.92)
    /// 머무는 동안 숨 쉬듯 부푼다.
    static let breathe = IntroSpring(response: 1.2, damping: 0.8)
    /// 방울을 삼킬 때 꿀꺽.
    static let gulp = IntroSpring(response: 0.34, damping: 0.45)

    func step(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping >= 1 {
            return 1 - exp(-omega * t) * (1 + omega * t)
        }
        let damped = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * t)
        return 1 - decay * (cos(damped * t) + damping * omega / damped * sin(damped * t))
    }
}

/// 목표를 바꿀 때 앞 스프링을 멈추지 않고 새 응답을 더한다. 속도가 그대로 이어지고,
/// 앞 스프링이 앉은 뒤에 시작하면 끊어서, 넘실대는 중에 시작하면 이어서 보인다.
struct IntroTrack {
    private var origin: Double
    private var keys: [(at: Double, to: Double, spring: IntroSpring)] = []

    init(_ origin: Double = 0) {
        self.origin = origin
    }

    mutating func to(_ value: Double, at time: Double, _ spring: IntroSpring) {
        keys.append((time, value, spring))
    }

    func value(_ t: Double) -> Double {
        var previous = origin
        var sum = origin
        for key in keys {
            sum += (key.to - previous) * key.spring.step(t - key.at)
            previous = key.to
        }
        return sum
    }
}

/// 노치에서 떨어져 나오는 모찌 방울. 위치는 노치 가운데 위 끝에서 잰다.
struct IntroBall {
    var x: IntroTrack
    var y: IntroTrack
    var size = IntroTrack()
    /// 양수면 옆으로 퍼지고, 음수면 위아래로 늘어난다.
    var squash = IntroTrack()
    /// 몸통과 방울을 잇는 떡 줄. 1이면 보통 굵기, 0이면 없다.
    var tether = IntroTrack()
    /// 빨리 움직일수록 가는 쪽으로 늘어난다.
    var stretchesWithSpeed = false
    /// 뒤따라오는 작은 방울 수. 빠를 때만 떨어져 보여서 끈적한 꼬리가 된다.
    var trail = 0
}

struct IntroBead: Equatable {
    var x: CGFloat
    var y: CGFloat
    var rx: CGFloat
    var ry: CGFloat
}

struct IntroPose {
    var left: CGFloat
    var right: CGFloat
    var drop: CGFloat
    var beads: [IntroBead]
}

enum IntroStudy: CaseIterable {
    case mochi
    case taffy
    case taffyTwice

    var title: String {
        switch self {
        case .mochi: return "인트로 · 모찌 (기본)"
        case .taffy: return "인트로 · 늘이기 · 길게 당겼다 놓음"
        case .taffyTwice: return "인트로 · 늘이기 두 번 · 한 번 늘이고 잠깐 뒤 더 길게"
        }
    }
}

/// 켤 때 인사의 안무. 노치 밖으로 내미는 왼쪽, 오른쪽 길이와 아래로 늘어나는 길이를 초 단위로 적는다.
struct IntroScript {
    var left = IntroTrack()
    var right = IntroTrack()
    var drop = IntroTrack()
    var balls: [IntroBall] = []
    /// 아이콘과 이름이 나오는 시각.
    var reveal: Double
    /// 윤곽을 따라 빛이 한 바퀴 도는 시작 시각.
    var glow: Double?
    var length: Double

    /// 로고가 서는 마지막 모양. 아이콘과 이름이 크게 들어갈 만큼.
    static let logoSides = 170.0
    static let logoDrop = 50.0

    mutating func sides(_ value: Double, at time: Double, _ spring: IntroSpring) {
        left.to(value, at: time, spring)
        right.to(value, at: time, spring)
    }

    /// 로고로 벌어진다. 옆과 바닥의 속도가 달라 엇박으로 출렁인다.
    mutating func bloom(at time: Double) {
        sides(Self.logoSides, at: time, .pop)
        drop.to(Self.logoDrop, at: time + 0.04, .drop)
    }

    /// 당겼던 떡을 놓는다. 가운데로 빠르게 튕겨 들어와 조이고, 조인 만큼 아래로 밀려 나온다.
    /// 가장 조인 채 한순간 버티다가(놓은 뒤 약 0.23초), 그 힘이 들어올 때보다 빠르게 옆으로 터진다.
    /// 터지는 순간 아래로 나왔던 부분은 위로 조금 당겨졌다가 로고 높이에 앉는다. 터지는 시각을 준다.
    /// 옆은 노치 밖 여유(7pt)보다 덜 조인다. 거기에 닿으면 그 자리에서 딱 멈춰 보인다.
    @discardableResult
    mutating func recoil(at release: Double) -> Double {
        sides(36, at: release, .recoil)
        drop.to(54, at: release + 0.04, .plop)
        let fire = release + 0.25
        sides(Self.logoSides, at: fire, .fling)
        drop.to(40, at: fire, .snapUp)
        drop.to(Self.logoDrop, at: fire + 0.14, .drop)
        return fire
    }

    /// 머무는 동안 한 번 부풀었다 가라앉는다.
    mutating func breathe(from time: Double) {
        sides(Self.logoSides + 6, at: time, .breathe)
        drop.to(Self.logoDrop + 2.5, at: time, .breathe)
        sides(Self.logoSides, at: time + 0.7, .breathe)
        drop.to(Self.logoDrop, at: time + 0.7, .breathe)
    }

    func pose(_ t: Double) -> IntroPose {
        let drop = Self.floor(self.drop.value(t))
        var beads: [IntroBead] = []
        for ball in balls {
            let size = ball.size.value(t)
            guard size > 0.4 else { continue }
            let x = ball.x.value(t)
            let y = ball.y.value(t)
            var squash = ball.squash.value(t)
            if ball.stretchesWithSpeed {
                let dt = 1.0 / 120
                let vx = (x - ball.x.value(t - dt)) / dt
                let vy = (y - ball.y.value(t - dt)) / dt
                squash += min(0.26, max(-0.26, (abs(vx) - abs(vy)) / 3000))
            }
            let tether = ball.tether.value(t)
            if tether > 0.05 {
                beads += Self.string(x: x, from: 38 + Double(drop) - 3, to: y, size: size, strength: tether)
            }
            for step in stride(from: ball.trail, through: 1, by: -1) {
                let past = t - Double(step) * 0.04
                let pastSize = ball.size.value(past) * (1 - 0.22 * Double(step))
                guard pastSize > 0.4 else { continue }
                let radius = CGFloat(pastSize)
                beads.append(IntroBead(x: CGFloat(ball.x.value(past)), y: CGFloat(ball.y.value(past)), rx: radius, ry: radius))
            }
            beads.append(IntroBead(
                x: CGFloat(x),
                y: CGFloat(y),
                rx: CGFloat(size * (1 + squash)),
                ry: CGFloat(size * (1 - squash))
            ))
        }
        return IntroPose(
            left: Self.floor(left.value(t)),
            right: Self.floor(right.value(t)),
            drop: drop,
            beads: beads
        )
    }

    /// 몸통과 방울 사이에 모래시계 모양으로 구슬을 늘어놓는다. 흐리고 자르면 한 줄의 떡이 된다.
    /// 흐림 반경 6에서 반지름이 4pt 아래로 가면 잘려서, 너무 늘이면 가운데가 끊긴다.
    private static func string(x: Double, from top: Double, to bottom: Double, size: Double, strength: Double) -> [IntroBead] {
        let length = bottom - top
        guard length > 4 else { return [] }
        let end = size * 0.62 * strength
        let middle = max(0, end - length / 100 * size * 0.22)
        let count = Int(length / 4)
        return (0...count).map { index in
            let f = Double(index) / Double(max(count, 1))
            let bulge = (2 * f - 1) * (2 * f - 1)
            let radius = CGFloat(middle + (end - middle) * bulge)
            return IntroBead(x: CGFloat(x), y: CGFloat(top + length * f), rx: radius, ry: radius)
        }
    }

    /// 노치 안쪽으로 튄 값은 몇 포인트 안으로 눌러 담는다. 0에서 딱 자르면 그 자리에서 멈칫한다.
    private static func floor(_ value: Double) -> CGFloat {
        guard value < 0 else { return CGFloat(value) }
        return CGFloat(-3 * (1 - exp(value / 3)))
    }

    static func make(_ study: IntroStudy) -> IntroScript {
        switch study {
        case .mochi:
            // 왼쪽 톡, 오른쪽 톡은 살짝 겹치고, 한 번 쉰 뒤 눌렸다가 그 반동으로 크게 벌어진다.
            var script = IntroScript(reveal: 1.52, glow: 1.9, length: 4.5)
            script.left.to(60, at: 0, .peek)
            script.left.to(0, at: 0.3, .tuck)
            script.right.to(60, at: 0.4, .peek)
            script.right.to(0, at: 0.7, .tuck)
            script.sides(12, at: 1.1, .drip)
            script.drop.to(22, at: 1.1, .drip)
            script.bloom(at: 1.46)
            script.breathe(from: 2.5)
            return script

        case .taffy:
            // 떡을 양쪽으로 길게 당기듯 얇게 늘였다가 놓는다. 튕겨 들어와 조인 반동으로 로고가 된다.
            var script = IntroScript(reveal: 0, glow: nil, length: 0)
            script.sides(205, at: 0, .pull)
            let fire = script.recoil(at: 1.4)
            script.reveal = fire + 0.06
            script.glow = fire + 0.45
            script.breathe(from: fire + 0.95)
            script.length = fire + 2.75
            return script

        case .taffyTwice:
            // 한 번만 늘이고 그 자리에서 잠깐 버틴 뒤, 더 길게 늘인다.
            // 두 번째 놓은 반동으로만 로고가 된다.
            var script = IntroScript(reveal: 0, glow: nil, length: 0)
            script.sides(118, at: 0, .pull)
            script.sides(205, at: 1.55, .pull)
            let fire = script.recoil(at: 2.95)
            script.reveal = fire + 0.06
            script.glow = fire + 0.45
            script.breathe(from: fire + 0.95)
            script.length = fire + 2.75
            return script
        }
    }
}

enum IslandColor {
    static let plate = Color.black
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let rowHighlight = Color.white.opacity(0.08)
    static let charge = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
    /// Dock 배지의 빨강. 시스템 빨강보다 조금 짙다.
    static let dockBadge = Color(red: 0.96, green: 0.23, blue: 0.19)
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let claude = Color(red: 0.855, green: 0.467, blue: 0.341)
    static let cursor = Color(red: 0.486, green: 0.361, blue: 0.988)
    static let codex = Color(red: 0.133, green: 0.773, blue: 0.369)
}

enum MochinotchConfig {
    static let port: UInt16 = 47321
    static let hoverIn = Duration.milliseconds(160)
    static let hoverOut = Duration.milliseconds(220)
    static let historyLimit = 30
}
