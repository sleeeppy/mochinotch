import CryptoKit
import Foundation
import Security

/// GitHub 릴리즈의 DMG를 받아, 이 앱이 꺼지면 같은 자리에 새 앱을 넣고 다시 켠다.
/// 새 앱이 지금 앱과 같은 인증서로 서명되어야 macOS가 같은 앱으로 보고 권한을 이어 준다.
enum AppUpdater {
    struct Release: Equatable {
        var version: String
        var page: URL
        var dmg: URL?
        /// GitHub가 올린 파일마다 붙여 주는 SHA-256.
        var sha256: String?
    }

    enum Failure: Error {
        case notReplaceable
        case noDownload
        case download
        case checksum
        case mount
        case missingApp
        case version
        case signature
    }

    static func release(from json: [String: Any], tag: String, page: URL) -> Release {
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let url = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let digest = (dmg?["digest"] as? String).flatMap { value -> String? in
            guard value.hasPrefix("sha256:") else { return nil }
            return String(value.dropFirst("sha256:".count)).lowercased()
        }
        return Release(version: tag, page: page, dmg: url, sha256: digest)
    }

    /// DMG 안에서 바로 켰거나 macOS가 격리한 사본이면 바꿀 자리가 없다.
    static func canReplace(_ app: URL = Bundle.main.bundleURL) -> Bool {
        let path = app.path
        guard !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") else { return false }
        let manager = FileManager.default
        return manager.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && manager.isWritableFile(atPath: path)
    }

    /// 새 앱을 꺼내 확인하고, 이 앱이 꺼지길 기다렸다 바꿔 넣을 스크립트를 띄운다. 끝나면 앱을 끄면 된다.
    static func prepare(_ release: Release) async throws {
        let target = Bundle.main.bundleURL
        guard canReplace(target) else { throw Failure.notReplaceable }
        guard let source = release.dmg else { throw Failure.noDownload }
        let manager = FileManager.default
        let work = manager.temporaryDirectory
            .appendingPathComponent("mochinotch-update-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let dmg = work.appendingPathComponent("update.dmg")
            try await download(source, to: dmg)
            try verifyChecksum(dmg, expected: release.sha256)
            let staged = try extractApp(dmg, into: work)
            try verify(staged, version: release.version)
            try launchSwap(staged: staged, target: target, work: work)
            log("ready \(release.version)")
        } catch {
            try? manager.removeItem(at: work)
            log("failed \(release.version) \(error)")
            throw error
        }
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Mochinotch", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    /// 값이 없던 예전 릴리즈는 서명 확인만 한다.
    private static func verifyChecksum(_ file: URL, expected: String?) throws {
        guard let expected else { return }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw Failure.checksum }
    }

    private static func extractApp(_ dmg: URL, into work: URL) throws -> URL {
        let manager = FileManager.default
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try manager.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-noverify", "-mountpoint", mount.path]) else {
            throw Failure.mount
        }
        defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let items = (try? manager.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw Failure.missingApp }
        let staged = work.appendingPathComponent(app.lastPathComponent)
        guard run("/usr/bin/ditto", [app.path, staged.path]) else { throw Failure.missingApp }
        // 받은 파일에 격리 표시가 붙어 있으면 다시 켤 때 확인되지 않은 개발자 경고가 뜬다.
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    /// 같은 앱, 받으려던 버전, 지금 앱과 같은 서명인지 본다.
    private static func verify(_ app: URL, version expected: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version == expected.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        else { throw Failure.version }

        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate,
              SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess
        else { throw Failure.signature }
    }

    private static func launchSwap(staged: URL, target: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(getpid()), staged.path, target.path, work.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// 앱이 30초 안에 꺼지지 않으면 아무것도 바꾸지 않는다. 넣다가 실패하면 원래 앱을 되돌린다.
    private static let swapScript = """
        #!/bin/sh
        pid="$1"; staged="$2"; target="$3"; work="$4"
        tries=0
        while kill -0 "$pid" 2>/dev/null; do
          tries=$((tries + 1))
          [ "$tries" -gt 150 ] && exit 1
          sleep 0.2
        done
        if mv "$target" "$work/previous.app"; then
          if mv "$staged" "$target"; then
            rm -rf "$work"
          else
            mv "$work/previous.app" "$target"
          fi
        fi
        open "$target"

        """

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func log(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Mochinotch/update.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
