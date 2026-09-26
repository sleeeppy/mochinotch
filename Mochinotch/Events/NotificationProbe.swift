import Foundation
import SQLite3

/// Phase 4a. 알림 센터 DB를 실제로 해석하지 않고, 읽기 가능 여부와 테이블 이름만 확인한다.
enum NotificationProbe {
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    static func run() -> String {
        let path = databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return "알림 데이터베이스를 찾지 못했어요.\n\(path)"
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return """
            파일은 있지만 읽을 수 없어요.
            시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에 Mochinotch를 넣은 뒤 앱을 다시 실행하세요.

            \(path)
            """
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            return "SQLite를 열지 못했어요: \(message)"
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            return "스키마를 읽지 못했어요: \(message)"
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) {
                names.append(String(cString: raw))
            }
        }
        if names.isEmpty {
            return "열었지만 테이블이 비어 있어요. macOS가 스키마를 바꿨을 수 있어요."
        }
        return "읽기 성공. 테이블 \(names.count)개:\n" + names.joined(separator: ", ")
    }
}
