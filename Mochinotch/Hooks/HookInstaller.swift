import AppKit
import Foundation

enum HookTool: String, CaseIterable, Sendable {
    case claude
    case cursor
    case codex
    case kiro

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .kiro: return "Kiro"
        }
    }

    /// 설정이 바뀌면 다시 켜야 하는 앱. 터미널에서 도는 CLI는 새 세션부터 읽는다.
    var appBundleIDs: [String] {
        switch self {
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .codex: return ["com.openai.codex"]
        case .kiro: return ["dev.kiro.desktop"]
        }
    }

    /// Kiro는 `~/.kiro/hooks/`를 지켜보다가 바로 다시 읽는다.
    var needsRestart: Bool {
        self != .kiro
    }

    fileprivate var configPath: String {
        switch self {
        case .claude: return ".claude/settings.json"
        case .cursor: return ".cursor/hooks.json"
        case .codex: return ".codex/config.toml"
        case .kiro: return ".kiro/hooks/mochinotch.json"
        }
    }

    fileprivate var cliNames: [String] {
        switch self {
        case .claude: return ["claude"]
        case .cursor: return ["cursor-agent"]
        case .codex: return ["codex"]
        case .kiro: return ["kiro-cli"]
        }
    }
}

struct AgentLinkStatus: Equatable, Sendable {
    /// 이 맥에서 찾은 도구.
    var present: [HookTool] = []
    var connected: [HookTool] = []
    /// `~/.local/bin/mochinotch-notify`가 지금 이 앱을 부른다.
    var relayReady = false

    var missing: [HookTool] {
        present.filter { !connected.contains($0) }
    }

    var ready: Bool {
        !present.isEmpty && missing.isEmpty && relayReady
    }
}

struct HookInstallResult: Sendable {
    /// 설정 파일을 실제로 고친 도구. 이 도구의 앱만 다시 켠다.
    var changed: [HookTool] = []
    var connected: [HookTool] = []
    var failures: [(tool: HookTool, message: String)] = []
}

/// hook 설정은 전부 `~/.local/bin/mochinotch-notify`를 부른다. 그 파일은 앱 실행 파일을 부르는 셸 스크립트라
/// 앱을 옮기거나 업데이트해도 설정 파일은 그대로 두고 이 파일만 고친다.
enum HookInstaller {
    static let relayMarker = "# mochinotch-relay"
    private static let claudeEvents = ["Stop", "Notification", "StopFailure"]

    static var home: URL {
        let path = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var relayURL: URL {
        home.appendingPathComponent(".local/bin/mochinotch-notify")
    }

    /// 다운로드 폴더에서 바로 연 앱은 macOS가 임시 경로로 옮겨 실행한다. 그 경로는 곧 사라진다.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    // MARK: 상태

    static func status() -> AgentLinkStatus {
        var status = AgentLinkStatus()
        status.relayReady = relayPointsHere()
        for tool in HookTool.allCases {
            if isPresent(tool) { status.present.append(tool) }
            if isConnected(tool) { status.connected.append(tool) }
        }
        return status
    }

    static func isPresent(_ tool: HookTool) -> Bool {
        let manager = FileManager.default
        let folder = home.appendingPathComponent(String(tool.configPath.prefix { $0 != "/" }))
        if manager.fileExists(atPath: folder.path) { return true }
        if tool.appBundleIDs.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
            return true
        }
        let bins = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        return tool.cliNames.contains { name in
            bins.contains { manager.isExecutableFile(atPath: "\($0)/\(name)") }
        }
    }

    static func isConnected(_ tool: HookTool) -> Bool {
        let url = home.appendingPathComponent(tool.configPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        switch tool {
        case .claude:
            guard let hooks = (try? jsonObject(text))?["hooks"] else { return false }
            return claudeEvents.allSatisfy { event in
                hasRelay(hooks[event], source: "claude")
            }
        case .cursor:
            guard let hooks = (try? jsonObject(text))?["hooks"] else { return false }
            return hasRelay(hooks["stop"], source: "cursor")
        case .codex:
            // 다른 도구가 notify를 감싸 우리 명령을 인자 안에 넣어 두기도 한다.
            return text.contains("mochinotch-notify")
        case .kiro:
            guard let hooks = (try? jsonObject(text))?["hooks"]?.arrayValue else { return false }
            return hooks.contains { hook in
                if case .bool(false)? = hook["enabled"] { return false }
                return hook["trigger"]?.stringValue == "Stop" && hasRelay(hook["action"], source: "kiro")
            }
        }
    }

    private static func hasRelay(_ value: OrderedJSON?, source: String) -> Bool {
        (value?.commands ?? []).contains { command in
            command.contains("mochinotch-notify") && command.contains("--source \(source)")
        }
    }

    // MARK: 설치

    static func install(tools: [HookTool]) -> HookInstallResult {
        var result = HookInstallResult()
        do {
            try writeRelay()
        } catch {
            for tool in tools { result.failures.append((tool, "전달 스크립트를 만들지 못했어요")) }
            return result
        }
        for tool in tools {
            do {
                if try merge(tool) { result.changed.append(tool) }
                result.connected.append(tool)
            } catch {
                result.failures.append((tool, error.localizedDescription))
            }
        }
        return result
    }

    /// 켤 때마다 부른다. 이미 연결한 사람만, 앱이 옮겨졌거나 예전 python 스크립트가 남아 있으면 이 앱을 가리키게 고친다.
    static func refreshRelayIfNeeded() {
        guard FileManager.default.fileExists(atPath: relayURL.path),
              !isTranslocated,
              Bundle.main.bundlePath.contains("/Applications/"),
              !relayPointsHere() else { return }
        try? writeRelay()
    }

    private static func relayPointsHere() -> Bool {
        guard let text = try? String(contentsOf: relayURL, encoding: .utf8),
              let executable = Bundle.main.executablePath else { return false }
        return text.contains(relayMarker) && text.contains(shellQuoted(executable))
    }

    private static func writeRelay() throws {
        guard let executable = Bundle.main.executablePath, !isTranslocated else {
            throw InstallError.translocated
        }
        let script = """
        #!/bin/sh
        \(relayMarker)
        # Mochinotch가 만든 파일이에요. AI 도구의 hook이 부르면 작업 완료를 노치로 보냅니다.
        APP=\(shellQuoted(executable))
        if [ ! -x "$APP" ]; then
          [ "$1" = "--source" ] && [ "$2" = "cursor" ] && printf '{}\\n'
          exit 0
        fi
        exec "$APP" --hook "$@"

        """
        let manager = FileManager.default
        try manager.createDirectory(at: relayURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script.utf8).write(to: relayURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: relayURL.path)
    }

    /// 고쳤으면 true. 이미 연결돼 있으면 파일을 건드리지 않는다.
    private static func merge(_ tool: HookTool) throws -> Bool {
        if isConnected(tool) { return false }
        let url = home.appendingPathComponent(tool.configPath)
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        let updated: String
        switch tool {
        case .claude: updated = try mergedClaude(existing)
        case .cursor: updated = try mergedCursor(existing)
        case .codex: updated = try mergedCodex(existing ?? "")
        case .kiro: updated = kiroHook()
        }
        if existing != nil {
            let backup = url.appendingPathExtension("mochinotch.bak")
            try? manager.removeItem(at: backup)
            try manager.copyItem(at: url, to: backup)
        }
        try Data(updated.utf8).write(to: url, options: .atomic)
        return true
    }

    private static func relayCommand(source: String) -> String {
        let path = relayURL.path
        let quoted = path.contains(" ") ? shellQuoted(path) : path
        return "\(quoted) --source \(source)"
    }

    private static func mergedClaude(_ existing: String?) throws -> String {
        var root = try jsonObject(existing ?? "")
        var hooks = try objectValue(root["hooks"])
        let entry = OrderedJSON.object([
            ("hooks", .array([.object([("type", .string("command")), ("command", .string(relayCommand(source: "claude")))])])),
        ])
        for event in claudeEvents where !hasRelay(hooks[event], source: "claude") {
            hooks[event] = .array(try arrayValue(hooks[event]) + [entry])
        }
        root["hooks"] = hooks
        return root.text() + "\n"
    }

    private static func mergedCursor(_ existing: String?) throws -> String {
        var root = try jsonObject(existing ?? "")
        if root["version"] == nil { root["version"] = .number("1") }
        var hooks = try objectValue(root["hooks"])
        if !hasRelay(hooks["stop"], source: "cursor") {
            let entry = OrderedJSON.object([("command", .string(relayCommand(source: "cursor")))])
            hooks["stop"] = .array(try arrayValue(hooks["stop"]) + [entry])
        }
        root["hooks"] = hooks
        return root.text() + "\n"
    }

    /// Mochinotch만 쓰는 파일이라 통째로 쓴다.
    private static func kiroHook() -> String {
        let hook = OrderedJSON.object([
            ("name", .string("Mochinotch")),
            ("description", .string("작업이 끝나면 노치에 알려요")),
            ("trigger", .string("Stop")),
            ("action", .object([("type", .string("command")), ("command", .string(relayCommand(source: "kiro")))])),
            ("timeout", .number("10")),
        ])
        return OrderedJSON.object([("version", .string("v1")), ("hooks", .array([hook]))]).text() + "\n"
    }

    private static func objectValue(_ value: OrderedJSON?) throws -> OrderedJSON {
        guard let value else { return .object([]) }
        guard case .object = value else { throw InstallError.unreadable }
        return value
    }

    private static func arrayValue(_ value: OrderedJSON?) throws -> [OrderedJSON] {
        guard let value else { return [] }
        guard let items = value.arrayValue else { throw InstallError.unreadable }
        return items
    }

    /// notify는 맨 위 테이블 키라 첫 `[섹션]` 앞에서만 찾는다. 원래 명령은 `--chain`으로 넘겨 그대로 이어서 실행한다.
    private static func mergedCodex(_ existing: String) throws -> String {
        let headEnd = firstTableHeader(in: existing) ?? existing.endIndex
        let head = existing[..<headEnd]
        let tail = existing[headEnd...]
        var command = [relayURL.path, "--source", "codex"]
        if let found = try TOMLNotify.find(in: head) {
            if !found.values.isEmpty {
                command += ["--chain", OrderedJSON.array(found.values.map(OrderedJSON.string)).text(indent: nil)]
            }
            var updated = existing
            updated.replaceSubrange(found.range, with: "notify = " + TOMLNotify.array(command))
            return updated
        }
        var prefix = String(head)
        if !prefix.isEmpty, !prefix.hasSuffix("\n") { prefix += "\n" }
        prefix += "# Mochinotch\nnotify = \(TOMLNotify.array(command))\n"
        if !tail.isEmpty { prefix += "\n" }
        return prefix + tail
    }

    private static func firstTableHeader(in text: String) -> String.Index? {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line.drop(while: { $0 == " " || $0 == "\t" }).first == "[" { return lineStart }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return nil
    }

    // MARK: 도구

    private static func jsonObject(_ text: String) throws -> OrderedJSON {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([]) }
        guard let value = try? OrderedJSON.parse(text), case .object = value else {
            throw InstallError.unreadable
        }
        return value
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    enum InstallError: LocalizedError {
        case unreadable
        case translocated
        case codexNotify

        var errorDescription: String? {
            switch self {
            case .unreadable: return "설정 파일을 읽지 못했어요"
            case .translocated: return "앱을 응용 프로그램 폴더로 옮긴 뒤 연결해 주세요"
            case .codexNotify: return "Codex 설정의 notify를 읽지 못했어요"
            }
        }
    }
}

/// Codex `config.toml`의 맨 위 `notify = [ ... ]`만 읽고 쓴다. 문자열 배열만 다룬다.
private enum TOMLNotify {
    struct Found {
        var range: Range<String.Index>
        var values: [String]
    }

    static func find(in head: Substring) throws -> Found? {
        var lineStart = head.startIndex
        while lineStart < head.endIndex {
            let lineEnd = head[lineStart...].firstIndex(of: "\n") ?? head.endIndex
            let line = head[lineStart..<lineEnd]
            let keyStart = line.firstIndex(where: { $0 != " " && $0 != "\t" }) ?? line.endIndex
            if line[keyStart...].hasPrefix("notify") {
                var cursor = line.index(keyStart, offsetBy: 6)
                skipSpaces(head, &cursor)
                if cursor < head.endIndex, head[cursor] == "=" {
                    cursor = head.index(after: cursor)
                    skipSpaces(head, &cursor)
                    guard cursor < head.endIndex, head[cursor] == "[" else { throw HookInstaller.InstallError.codexNotify }
                    let (values, end) = try parseArray(head, from: cursor)
                    return Found(range: lineStart..<end, values: values)
                }
            }
            lineStart = lineEnd < head.endIndex ? head.index(after: lineEnd) : head.endIndex
        }
        return nil
    }

    static func array(_ values: [String]) -> String {
        "[" + values.map(basicString).joined(separator: ", ") + "]"
    }

    private static func basicString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7f {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    private static func skipSpaces(_ text: Substring, _ cursor: inout String.Index) {
        while cursor < text.endIndex, text[cursor] == " " || text[cursor] == "\t" {
            cursor = text.index(after: cursor)
        }
    }

    /// `[`에서 시작해 짝이 맞는 `]` 다음 위치를 돌려준다. 줄바꿈, 주석, 끝 쉼표를 허용한다.
    private static func parseArray(_ text: Substring, from start: String.Index) throws -> ([String], String.Index) {
        var values: [String] = []
        var cursor = text.index(after: start)
        while cursor < text.endIndex {
            let character = text[cursor]
            switch character {
            case " ", "\t", "\n", "\r", ",":
                cursor = text.index(after: cursor)
            case "#":
                cursor = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            case "]":
                return (values, text.index(after: cursor))
            case "\"", "'":
                if text[cursor...].hasPrefix(String(repeating: character, count: 3)) {
                    throw HookInstaller.InstallError.codexNotify
                }
                let (value, next) = try parseString(text, from: cursor, literal: character == "'")
                values.append(value)
                cursor = next
            default:
                throw HookInstaller.InstallError.codexNotify
            }
        }
        throw HookInstaller.InstallError.codexNotify
    }

    private static func parseString(_ text: Substring, from start: String.Index, literal: Bool) throws -> (String, String.Index) {
        let quote: Character = literal ? "'" : "\""
        var cursor = text.index(after: start)
        var value = ""
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == quote { return (value, text.index(after: cursor)) }
            if character == "\n" { break }
            if !literal, character == "\\" {
                cursor = text.index(after: cursor)
                guard cursor < text.endIndex else { break }
                switch text[cursor] {
                case "\"": value.append("\"")
                case "\\": value.append("\\")
                case "b": value.append("\u{08}")
                case "t": value.append("\t")
                case "n": value.append("\n")
                case "f": value.append("\u{0C}")
                case "r": value.append("\r")
                case "u", "U":
                    let width = text[cursor] == "u" ? 4 : 8
                    let digitsStart = text.index(after: cursor)
                    guard let digitsEnd = text.index(digitsStart, offsetBy: width, limitedBy: text.endIndex),
                          let code = UInt32(text[digitsStart..<digitsEnd], radix: 16),
                          let scalar = Unicode.Scalar(code) else { throw HookInstaller.InstallError.codexNotify }
                    value.unicodeScalars.append(scalar)
                    cursor = text.index(before: digitsEnd)
                default:
                    throw HookInstaller.InstallError.codexNotify
                }
            } else {
                value.append(character)
            }
            cursor = text.index(after: cursor)
        }
        throw HookInstaller.InstallError.codexNotify
    }
}
