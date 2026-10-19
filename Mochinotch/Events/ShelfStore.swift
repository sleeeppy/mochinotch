import Foundation

/// 맡긴 파일의 경로만 기억한다. 임시 자리에 있는 파일은 드래그가 끝나 사라지기 전에 노치 폴더로 복사한다.
enum ShelfStore {
    static let storageKey = "shelfFiles"

    static var directory: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.sleeeppy.mochinotch/Shelf", isDirectory: true)
    }()

    static var defaults: UserDefaults = .standard

    /// 심볼릭 링크를 따라간 경로. 같은 파일을 `/tmp`와 `/private/tmp`로 두 번 세지 않는다.
    static func identity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isInsideShelf(_ url: URL) -> Bool {
        let path = identity(url)
        let root = identity(directory)
        return path.hasPrefix(root + "/")
    }

    /// 화면 캡처 썸네일처럼, 놓는 쪽이 드래그 끝에 지우는 파일.
    static func isTemporary(_ url: URL) -> Bool {
        let path = identity(url)
        if isScratch(path) { return true }
        return temporaryRoots().contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// 둘 수 있는 주소. 파일이 없거나 임시 파일을 복사하지 못하면 nil이라, 곧 사라질 경로는 남기지 않는다.
    static func adopt(_ url: URL) -> URL? {
        let source = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        if isInsideShelf(resolved) { return resolved }
        guard isTemporary(resolved) else { return resolved }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = uniqueDestination(named: source.lastPathComponent)
            try FileManager.default.copyItem(at: resolved, to: destination)
            return destination.standardizedFileURL
        } catch {
            return nil
        }
    }

    static func save(_ paths: [String]) {
        defaults.set(paths, forKey: storageKey)
    }

    static func load() -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    /// 저장해 둔 경로 중 아직 파일이 있는 것만, 맡긴 순서대로.
    static func retained() -> [URL] {
        load().compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    /// 노치 폴더 안에서, 아직 맡아 둔 복사본 이외의 파일을 지운다. 폴더 밖은 건드리지 않는다.
    static func sweep(keeping urls: [URL]) {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = identity(root)
        guard rootPath.split(separator: "/").count >= 4 else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }
        let keep = Set(urls.map { identity($0) })
        for item in items where !keep.contains(identity(item)) {
            guard identity(item).hasPrefix(rootPath + "/") else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func uniqueDestination(named fileName: String) -> URL {
        let cleaned = (fileName.isEmpty || fileName == "." || fileName == "..") ? "File" : fileName
        let ext = (cleaned as NSString).pathExtension
        let base = (cleaned as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(cleaned)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path), number < 50 {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = directory.appendingPathComponent(name)
            number += 1
        }
        return candidate
    }

    private static func temporaryRoots() -> [String] {
        let raw = [
            FileManager.default.temporaryDirectory.path,
            NSTemporaryDirectory(),
            "/tmp",
            "/private/tmp",
            "/var/tmp",
            "/private/var/tmp"
        ]
        return raw.map { identity(URL(fileURLWithPath: $0)) }
    }

    /// `/var/folders`와 `TemporaryItems`는 캡처나 드래그가 잠깐 파일을 두는 자리다.
    /// `Desktop/var/folders`처럼 이름만 같은 사용자 폴더는 여기 넣지 않는다.
    private static func isScratch(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains("TemporaryItems") { return true }
        if let varIndex = parts.firstIndex(of: "var"),
           parts.dropFirst(varIndex + 1).first == "folders",
           varIndex == 0 || parts[varIndex - 1] == "private" {
            return true
        }
        for index in parts.indices where parts[index] == "tmp" && index >= 1 && parts[index - 1] == "Data" {
            if parts.contains("Containers") { return true }
        }
        return false
    }
}
