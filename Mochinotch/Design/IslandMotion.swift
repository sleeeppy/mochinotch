import SwiftUI

enum IslandMotion {
    /// 살짝 튀는 스프링. 애플 다이나믹 아일랜드에 가까운 감쇠.
    static let morph: Animation = .spring(response: 0.46, dampingFraction: 0.74, blendDuration: 0.12)
    static let content: Animation = .spring(response: 0.34, dampingFraction: 0.86)
    static let windowDuration: TimeInterval = 0.46

    static var windowTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1.0)
    }
}

enum IslandColor {
    static let plate = Color.black
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.10)
    static let rowHighlight = Color.white.opacity(0.08)
    static let charge = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let claude = Color(red: 0.855, green: 0.467, blue: 0.341)
    static let cursor = Color(red: 0.486, green: 0.361, blue: 0.988)
    static let codex = Color(red: 0.133, green: 0.773, blue: 0.369)
}

enum MochinotchConfig {
    static let port: UInt16 = 47321
    static let hoverIn = Duration.milliseconds(160)
    static let hoverOut = Duration.milliseconds(220)
    static let historyLimit = 12
}
