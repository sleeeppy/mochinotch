import Foundation
import Security

/// 루프백 이벤트와 `mochinotch://`에 붙는 사용자 전용 토큰.
/// 다른 계정과 웹페이지는 이 파일을 읽지 못한다.
enum EventToken {
    static let headerName = "X-Mochinotch-Token"
    static var storageURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Mochinotch/event.token")

    /// 앱이 뜰 때 만든다. 이미 있으면 그대로 쓴다.
    @discardableResult
    static func loadOrCreate() -> String {
        if let existing = read() { return existing }
        let created = randomToken()
        write(created)
        return read() ?? created
    }

    static func current() -> String? {
        read()
    }

    static func accepts(_ presented: String) -> Bool {
        guard let expected = read() else { return false }
        let left = Array(presented.utf8)
        let right = Array(expected.utf8)
        guard left.count == right.count, !left.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    private static func read() -> String? {
        guard let text = try? String(contentsOf: storageURL, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        return token
    }

    private static func write(_ token: String) {
        let manager = FileManager.default
        let directory = storageURL.deletingLastPathComponent()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = token.data(using: .utf8) else { return }
        storageURL.path.withCString { path in
            let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            _ = fchmod(fd, 0o600)
            data.withUnsafeBytes { buffer in
                _ = Darwin.write(fd, buffer.baseAddress, buffer.count)
            }
        }
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max)
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
