import Foundation

/// `v0.6.10-rc1`처럼 출시 전 표기가 붙은 태그도 숫자 순서로 비교한다.
/// 숫자가 같으면 출시 전 버전이 정식 버전보다 낮다.
struct ReleaseVersion: Comparable {
    var numbers: [Int]
    var prerelease: [String]

    static func parse(_ text: String) -> ReleaseVersion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces[0]
        guard !core.isEmpty else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: true).compactMap { component -> Int? in
            let digits = component.prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return Int(digits)
        }
        guard !numbers.isEmpty else { return nil }
        let prerelease = pieces.count > 1
            ? pieces[1].split(separator: ".", omittingEmptySubsequences: true).map(String.init)
            : []
        return ReleaseVersion(numbers: numbers, prerelease: prerelease)
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let remote = parse(remote), let local = parse(local) else { return false }
        return remote > local
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        let identifiers = max(lhs.prerelease.count, rhs.prerelease.count)
        for index in 0..<identifiers {
            if index >= lhs.prerelease.count { return true }
            if index >= rhs.prerelease.count { return false }
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            switch (Int(left), Int(right)) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none) where left != right:
                return left < right
            default:
                continue
            }
        }
        return false
    }
}
