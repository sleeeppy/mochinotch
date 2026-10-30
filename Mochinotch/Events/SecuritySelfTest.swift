import Darwin
import Foundation

/// `Mochinotch --self-test`에서 이벤트, 업데이트, 훅 병합을 확인한다.
enum SecuritySelfTest {
    static func run() -> Int32 {
        let tests: [(String, () throws -> Void)] = [
            ("음수 Content-Length는 거절한다", testNegativeLength),
            ("POST /event가 아니면 거절한다", testRejectsGet),
            ("본문 길이는 바이트로 자른다", testByteLength),
            ("출시 전 태그가 이전 버전보다 새 것이다", testPrereleaseNewer),
            ("같은 숫자의 출시 전 태그는 정식보다 낮다", testPrereleaseOlderThanRelease),
            ("순수 버전 비교는 그대로다", testPlainVersions),
            ("http DMG와 대문자 SHA256를 가른다", testDownloadChoice),
            ("격리 해제는 바깥 심볼릭 링크를 따라가지 않는다", testQuarantineSkipsSymlink),
            ("테이블 뒤의 Codex notify는 하나로 감싼다", testCodexNotifyAfterTable),
            ("Codex notify를 두 번 넣지 않는다", testCodexNotifyIdempotent),
            ("훅 경로는 항상 셸 따옴표로 감싼다", testShellQuote),
            ("꺼 둔 Kiro 훅은 유지한다", testDisabledKiroHook),
            ("이벤트 토큰이 다르면 거절한다", testEventToken)
        ]
        var failed = 0
        for (name, test) in tests {
            do {
                try test()
                print("통과  \(name)")
            } catch {
                failed += 1
                print("실패  \(name): \(error)")
            }
        }
        if failed == 0 {
            print("보안 \(tests.count)개 모두 통과")
            return 0
        }
        print("보안 \(tests.count)개 중 \(failed)개 실패")
        return 1
    }

    private static func testNegativeLength() throws {
        let request = Data("POST /event HTTP/1.1\r\nContent-Length: -1\r\n\r\n{}".utf8)
        try expect(EventHTTP.parse(request, complete: true) == .reject, "음수 길이를 받았다")
    }

    private static func testRejectsGet() throws {
        let request = Data("GET /event HTTP/1.1\r\nX-Ignore: POST \r\nContent-Length: 2\r\n\r\n{}".utf8)
        try expect(EventHTTP.parse(request, complete: true) == .reject, "GET을 받았다")
    }

    private static func testByteLength() throws {
        let json = #"{"title":"가나다"}"#
        let payload = Data(json.utf8)
        var request = Data("POST /event HTTP/1.1\r\nContent-Length: \(payload.count)\r\nX-Mochinotch-Token: secret\r\n\r\n".utf8)
        request.append(payload)
        request.append(Data("XXXX".utf8))
        guard case .event(let body, let token) = EventHTTP.parse(request, complete: true) else {
            throw Failure("이벤트로 풀지 못했다")
        }
        try expect(body == payload, "본문 \(body.count)바이트")
        try expect(token == "secret", "토큰 \(token)")
    }

    private static func testPrereleaseNewer() throws {
        try expect(ReleaseVersion.isNewer("0.6.10-rc1", than: "0.6.9"), "0.6.10-rc1")
        try expect(ReleaseVersion.isNewer("1.2.3-rc.1", than: "1.2.2"), "1.2.3-rc.1")
        try expect(ReleaseVersion.isNewer("v0.7.0", than: "0.6.9"), "v0.7.0")
        try expect(ReleaseVersion.isNewer("1.10.0", than: "1.9.9"), "1.10.0")
    }

    private static func testPrereleaseOlderThanRelease() throws {
        try expect(!ReleaseVersion.isNewer("1.2.3-rc.1", than: "1.2.3"), "rc가 정식보다 높다")
        try expect(!ReleaseVersion.isNewer("v1.2.3", than: "1.2.3"), "같은 버전")
    }

    private static func testPlainVersions() throws {
        try expect(ReleaseVersion.parse("v0.6.10-rc1")?.numbers == [0, 6, 10], "숫자 조각")
    }

    private static func testDownloadChoice() throws {
        let json: [String: Any] = [
            "assets": [
                [
                    "name": "Evil.dmg",
                    "browser_download_url": "http://evil.example/update.dmg",
                    "digest": "SHA256:abcd"
                ],
                [
                    "name": "Mochinotch.dmg",
                    "browser_download_url": "https://github.com/sleeeppy/mochinotch/releases/download/v9/Mochinotch.dmg",
                    "digest": "SHA256:" + String(repeating: "ab", count: 32)
                ]
            ]
        ]
        let page = URL(string: "https://evil.example/release")!
        let release = AppUpdater.release(from: json, tag: "v9.0.0", page: page)
        try expect(release.dmg?.host == "github.com", "host \(release.dmg?.host ?? "nil")")
        try expect(release.sha256 == String(repeating: "ab", count: 32), "digest \(release.sha256 ?? "nil")")
        try expect(release.page.host == "github.com", "page \(release.page.host ?? "nil")")
    }

    private static func testQuarantineSkipsSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mochi-quarantine-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("Mochinotch.app/Contents", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = bundle.appendingPathComponent("inside.bin")
        let target = outside.appendingPathComponent("secret.bin")
        try Data("in".utf8).write(to: inside)
        try Data("out".utf8).write(to: target)
        try markQuarantine(inside)
        try markQuarantine(target)
        try FileManager.default.createSymbolicLink(
            at: bundle.appendingPathComponent("escape"),
            withDestinationURL: target
        )
        AppUpdater.clearQuarantine(root.appendingPathComponent("Mochinotch.app"))
        try expect(!hasQuarantine(inside), "앱 안 파일이 그대로다")
        try expect(hasQuarantine(target), "바깥 파일의 격리가 지워졌다")
    }

    private static func testCodexNotifyAfterTable() throws {
        try withHome("/tmp/mochi-audit-home") {
        let merged = try HookInstaller.previewCodex("""
        [model]
        name = "gpt"

        notify = ["/bin/echo", "keep-me"]
        """)
        let lines = merged.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify")
        }
        try expect(lines.count == 1, "notify \(lines.count)줄\n\(merged)")
        try expect(merged.contains("mochinotch-notify"), "릴레이가 없다")
        try expect(merged.contains("keep-me"), "원래 명령이 없다")
        try expect(merged.contains("--chain"), "chain이 없다")
        }
    }

    private static func testCodexNotifyIdempotent() throws {
        try withHome("/tmp/mochi-audit-home") {
        let once = try HookInstaller.previewCodex("notify = [\"/bin/echo\", \"keep-me\"]\n\n[model]\nname = \"gpt\"\n")
        let twice = try HookInstaller.previewCodex(once)
        try expect(once == twice, "두 번째에 또 고쳤다")
        let lines = twice.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify")
        }
        try expect(lines.count == 1, "notify \(lines.count)줄")
        }
    }

    private static func testShellQuote() throws {
        try withHome("/tmp/mochi-audit-dollar$(id)") {
        let merged = try HookInstaller.previewClaude(nil)
        let parsed = try OrderedJSON.parse(merged)
        let command = parsed["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"]?.stringValue ?? ""
        try expect(command.contains("$(id)"), "경로가 없다: \(command)")
        try expect(command.contains("'"), "따옴표가 없다: \(command)")
        }
    }

    private static func testDisabledKiroHook() throws {
        try withHome("/tmp/mochi-audit-home") {
        let original = """
        {"version":"v1","hooks":[{"enabled":false,"trigger":"Stop","action":{"type":"command","command":"\(HookInstaller.relayURL.path) --source kiro"},"extra":"keep"}]}
        """
        let merged = HookInstaller.previewKiro(original)
        try expect(merged.contains("\"enabled\""), "enabled가 사라졌다")
        try expect(merged.contains("keep"), "extra가 사라졌다")
        }
    }

    private static func testEventToken() throws {
        let previous = EventToken.storageURL
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-token-\(UUID().uuidString)")
        EventToken.storageURL = url
        defer {
            EventToken.storageURL = previous
            try? FileManager.default.removeItem(at: url)
        }
        let token = EventToken.loadOrCreate()
        try expect(EventToken.accepts(token), "만든 토큰을 거절했다")
        try expect(!EventToken.accepts(token + "x"), "다른 토큰을 받았다")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        try expect((mode?.intValue ?? 0) & 0o077 == 0, "모드 \(String(mode?.intValue ?? 0, radix: 8))")
    }

    private static func withHome(_ path: String, _ body: () throws -> Void) throws {
        let previous = HookInstaller.homeOverride
        HookInstaller.homeOverride = URL(fileURLWithPath: path, isDirectory: true)
        defer { HookInstaller.homeOverride = previous }
        try body()
    }

    private static func markQuarantine(_ url: URL) throws {
        let value = Data("0083;00000000;test;AAAA".utf8)
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return value.withUnsafeBytes { buffer in
                setxattr(path, "com.apple.quarantine", buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        try expect(result == 0, "xattr \(result)")
    }

    private static func hasQuarantine(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
