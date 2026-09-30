import Foundation

/// `Mochinotch --hook --source claude|cursor|codex`. AI 도구의 hook이 부르면 작업 완료를 노치로 보낸다.
/// 앱이 꺼져 있으면 조용히 끝난다. python 없이 돈다.
enum HookRelay {
    static func run(_ arguments: [String]) -> Int32 {
        var options = Options()
        var index = 0
        func value() -> String {
            index += 1
            return index < arguments.count ? arguments[index] : ""
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--source": options.source = value()
            case "--tool": options.tool = value()
            case "--title": options.title = value()
            case "--detail": options.detail = value()
            case "--kind": options.kind = value()
            case "--bundle-id": options.bundle = value()
            case "--success": options.success = true
            case "--failure":
                options.success = false
                if options.kind.isEmpty { options.kind = "failed" }
            case "--needs-input": options.kind = "needsInput"
            // Codex notify는 한 개만 받는다. 원래 있던 명령(JSON 배열)을 같은 인자로 이어서 실행한다.
            case "--chain": options.chain = value()
            case "--":
                options.positional.append(contentsOf: arguments[(index + 1)...])
                index = arguments.count
            default: options.positional.append(argument)
            }
            index += 1
        }
        // Cursor hook은 표준 출력에 {} 만 내야 이어서 질문을 던지지 않는다.
        defer {
            if options.source == "cursor" {
                FileHandle.standardOutput.write(Data("{}\n".utf8))
            }
        }
        relay(options)
        return 0
    }

    private struct Options {
        var source = ""
        var tool = ""
        var title = ""
        var detail = ""
        var kind = ""
        var success: Bool?
        var bundle = ""
        var chain = ""
        var positional: [String] = []
    }

    private static func relay(_ options: Options) {
        let environment = ProcessInfo.processInfo.environment
        let argPayload = options.positional.last ?? ""
        if !options.chain.isEmpty {
            runChain(options.chain, extra: argPayload)
        }

        var bundle = options.bundle
        if bundle.isEmpty, let program = environment["TERM_PROGRAM"] {
            bundle = [
                "Apple_Terminal": "com.apple.Terminal",
                "iTerm.app": "com.googlecode.iterm2",
                "ghostty": "com.mitchellh.ghostty",
                "WarpTerminal": "dev.warp.Warp-Stable",
            ][program] ?? ""
        }
        // 앱 안의 터미널(Cursor 등)에서 돌면 macOS가 그 앱의 번들 ID를 넣어 준다.
        if bundle.isEmpty, let hosting = environment["__CFBundleIdentifier"], hosting != Bundle.main.bundleIdentifier {
            bundle = hosting
        }

        // Codex는 인자로 넘기고 stdin을 닫지 않을 수 있다. 인자가 있으면 stdin을 기다리지 않는다.
        let readsStdin = isatty(STDIN_FILENO) == 0 && !(options.source == "codex" && !argPayload.isEmpty)
        let stdinEvent = readsStdin ? object(FileHandle.standardInput.readDataToEndOfFile()) : [:]
        let argEvent = object(Data(argPayload.utf8))

        // Cursor는 ~/.claude/settings.json 의 hook도 불러온다. Cursor가 부른 Claude hook은 Cursor stop hook과 겹치니 버린다.
        let fromCursor = stdinEvent["cursor_version"] != nil
            || (stdinEvent["conversation_id"] != nil && stdinEvent["session_id"] == nil)
        if options.source == "claude", fromCursor {
            log(options.source, stdinEvent, "skip: Cursor가 부른 Claude hook")
            return
        }
        log(options.source, stdinEvent, "send")

        var tool = options.tool
        var title = options.title
        var detail = options.detail
        var kind = options.kind

        switch options.source {
        case "claude":
            if tool.isEmpty { tool = "claude" }
            switch stdinEvent["hook_event_name"] as? String ?? "" {
            case "Notification":
                if kind.isEmpty { kind = "needsInput" }
                if title.isEmpty { title = (stdinEvent["title"] as? String).nonEmpty ?? "Claude Code" }
                if detail.isEmpty { detail = firstLine(stdinEvent["message"] as? String) }
            case "StopFailure":
                if kind.isEmpty { kind = "failed" }
                if title.isEmpty { title = "Claude Code 실패" }
            default:
                if kind.isEmpty { kind = "completed" }
                if title.isEmpty { title = "Claude Code 작업 완료" }
                if detail.isEmpty { detail = folderName(stdinEvent["cwd"] as? String) }
            }
        case "cursor":
            if tool.isEmpty { tool = "cursor" }
            let status = (stdinEvent["status"] as? String ?? "completed").lowercased()
            if status == "error" {
                if kind.isEmpty { kind = "failed" }
                if title.isEmpty { title = "Cursor 작업 실패" }
            } else if ["aborted", "cancelled", "canceled"].contains(status) {
                if kind.isEmpty { kind = "cancelled" }
                if title.isEmpty { title = "Cursor 작업 중단" }
            } else {
                if kind.isEmpty { kind = "completed" }
                if title.isEmpty { title = "Cursor 작업 완료" }
            }
            if detail.isEmpty, let root = (stdinEvent["workspace_roots"] as? [Any])?.first {
                detail = folderName(String(describing: root))
            }
        case "codex":
            let event = argEvent.isEmpty ? stdinEvent : argEvent
            if let type = event["type"] as? String, type != "agent-turn-complete" { return }
            if tool.isEmpty { tool = "codex" }
            if kind.isEmpty { kind = "completed" }
            if title.isEmpty { title = "Codex 작업 완료" }
            if detail.isEmpty { detail = firstLine(event["last-assistant-message"] as? String) }
            if detail.isEmpty { detail = folderName(event["cwd"] as? String) }
        default:
            if tool.isEmpty { tool = "custom" }
            if kind.isEmpty { kind = options.success == false ? "failed" : "completed" }
            if title.isEmpty { title = "작업 완료" }
        }
        if options.success == true, kind.isEmpty { kind = "completed" }
        if options.success == false { kind = "failed" }
        if kind.isEmpty { kind = "completed" }

        var payload: [String: Any] = [
            "tool": tool,
            "title": title,
            "detail": detail,
            "kind": kind,
            "success": kind != "failed",
        ]
        if !bundle.isEmpty { payload["bundleID"] = bundle }
        post(payload)
    }

    private static func post(_ payload: [String: Any]) {
        guard let url = URL(string: "http://127.0.0.1:\(MochinotchConfig.port)/event"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url, timeoutInterval: 1.5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 2)
    }

    private static func runChain(_ raw: String, extra: String) {
        guard let command = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [Any],
              !command.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command.map { String(describing: $0) } + (extra.isEmpty ? [] : [extra])
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func object(_ data: Data) -> [String: Any] {
        guard !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }

    private static func firstLine(_ text: String?, limit: Int = 90) -> String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = trimmed.split(whereSeparator: \.isNewline).first else { return "" }
        return String(line.prefix(limit))
    }

    private static func folderName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// 대화 내용은 남기지 않는다. 어떤 hook이 어떤 키로 불렸는지만 적는다.
    private static func log(_ source: String, _ event: [String: Any], _ note: String) {
        let folder = HookInstaller.home.appendingPathComponent("Library/Logs/Mochinotch")
        let url = folder.appendingPathComponent("hooks.log")
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 200_000 {
            let rotated = url.appendingPathExtension("1")
            try? manager.removeItem(at: rotated)
            try? manager.moveItem(at: url, to: rotated)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let keys = event.keys.sorted().joined(separator: ",")
        let name = event["hook_event_name"] as? String ?? ""
        let line = "\(formatter.string(from: Date())) source=\(source) event=\(name) keys=\(keys) \(note)\n"
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
