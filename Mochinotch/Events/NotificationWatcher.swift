import Foundation
import SQLite3

struct SystemNotice: Equatable {
    var bundleID: String
    var title: String
    var subtitle: String
    var body: String
}

enum NotificationAccess: Equatable {
    case starting
    case watching
    case missingDatabase
    /// 전체 디스크 접근 권한이 없다.
    case denied
    case failed(String)
}

/// 알림 센터 DB(`usernoted`)의 새 기록을 읽는다. 비공개 포맷이라 읽지 못하는 기록은 건너뛴다.
final class NotificationWatcher {
    var onNotice: ((SystemNotice) -> Void)?
    var onAccessChange: ((NotificationAccess) -> Void)?

    private let queue = DispatchQueue(label: "dev.sleeeppy.mochinotch.notifications")
    private var timer: DispatchSourceTimer?
    private var db: OpaquePointer?
    private var lastID: Int64?
    private var access: NotificationAccess = .starting
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.close()
        }
    }

    private func tick() {
        if db == nil, !open() {
            return
        }
        guard let db else { return }
        if lastID == nil {
            lastID = maxRecordID(db)
            return
        }
        for notice in readNew(db) {
            DispatchQueue.main.async { [onNotice] in
                onNotice?(notice)
            }
        }
    }

    private func open() -> Bool {
        let url = NotificationProbe.databaseURL
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            // 권한이 없으면 폴더 목록조차 못 읽는다.
            let listable = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) != nil
            report(listable ? .missingDatabase : .denied)
            return false
        }
        let path = url.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            report(message.contains("authorization") ? .denied : .failed(message))
            return false
        }
        sqlite3_busy_timeout(handle, 200)
        db = handle
        report(.watching)
        return true
    }

    private func close() {
        sqlite3_close(db)
        db = nil
        lastID = nil
    }

    private func report(_ next: NotificationAccess) {
        guard access != next else { return }
        access = next
        DispatchQueue.main.async { [onAccessChange] in
            onAccessChange?(next)
        }
    }

    private func maxRecordID(_ db: OpaquePointer) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rec_id), 0) FROM record", -1, &statement, nil) == SQLITE_OK else {
            fail(db)
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func readNew(_ db: OpaquePointer) -> [SystemNotice] {
        guard let since = lastID else { return [] }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data
            FROM record r LEFT JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 20
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fail(db)
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, since)

        var notices: [SystemNotice] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            lastID = sqlite3_column_int64(statement, 0)
            let identifier = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: length)
            if let notice = Self.decode(data, fallbackBundleID: identifier), notice.bundleID != ownBundleID {
                notices.append(notice)
            }
        }
        return notices
    }

    /// 스키마가 바뀌었을 수 있으니 닫고 다음 틱에 다시 연다.
    private func fail(_ db: OpaquePointer) {
        let message = String(cString: sqlite3_errmsg(db))
        close()
        report(.failed(message))
    }

    /// 기록은 바이너리 plist다. `app`은 번들 ID, `req`의 `titl`/`subt`/`body`가 배너 글자다.
    static func decode(_ data: Data, fallbackBundleID: String?) -> SystemNotice? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let request = plist["req"] as? [String: Any] ?? [:]
        let bundleID = (plist["app"] as? String) ?? fallbackBundleID ?? ""
        let title = (request["titl"] as? String) ?? ""
        let subtitle = (request["subt"] as? String) ?? ""
        let body = (request["body"] as? String) ?? ""
        guard !bundleID.isEmpty, !(title.isEmpty && body.isEmpty) else { return nil }
        return SystemNotice(bundleID: bundleID, title: title, subtitle: subtitle, body: body)
    }
}
