import Foundation
import SQLite3

/// T3의 질문·승인 카드가 실제로 응답 대기 중인 동안만 알린다.
enum T3QuestionWatcher {
    static func start(onEvent: @escaping @MainActor (IncomingEvent) -> Void) {
        let home = ProcessInfo.processInfo.environment["T3CODE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3")
        let path = home.appendingPathComponent("userdata/statev2.sqlite").path
        guard let url = Bundle.main.url(forResource: "T3PendingRequests", withExtension: "sql"),
              let query = try? String(contentsOf: url, encoding: .utf8) else { return }
        Task.detached(priority: .utility) {
            var previous = Set<String>()
            while !Task.isCancelled {
                let exists = FileManager.default.fileExists(atPath: path)
                if exists, var rows = pending(path: path, query: query) {
                    if !rows.isEmpty, !HookInstaller.isConnected(.codex) { rows.removeAll() }
                    let live = Set(rows.map(\.id))
                    for id in previous.subtracting(live) {
                        await onEvent(IncomingEvent(id: id, tool: "codex", kind: "resolved"))
                    }
                    for row in rows where !previous.contains(row.id) {
                        await onEvent(IncomingEvent(id: row.id, tool: "codex", detail: row.detail,
                                                    kind: "needsInput", bundleID: "com.t3tools.t3code"))
                    }
                    previous = live
                }
                try? await Task.sleep(for: .seconds(exists ? 1 : 30))
            }
        }
    }

    private static func pending(path: String, query: String) -> [(id: String, detail: String)]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        var rows: [(String, String)] = []
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            if let id = sqlite3_column_text(stmt, 0), let detail = sqlite3_column_text(stmt, 1) {
                rows.append(("t3:" + String(cString: id), String(cString: detail)))
            }
            result = sqlite3_step(stmt)
        }
        return result == SQLITE_DONE ? rows : nil
    }
}
