import Foundation
import SQLite3

/// `Mochinotch --self-test` 로 알림 감시의 복사·조회·삭제를 확인한다.
enum NotificationWatcherSelfTest {
    static func run() -> Int32 {
        NotificationWatcher.readsBanners = false
        NotificationWatcher.writesLog = false
        let tests: [(String, () throws -> Void)] = [
            ("16바이트로 이어진 UUID를 찾는다", testPackedUUIDs),
            ("글자로 적힌 UUID를 찾는다", testStringUUIDs),
            ("경계가 어긋난 UUID도 찾는다", testUnalignedUUID),
            ("파일이 그대로면 사본을 다시 만들지 않는다", testSkipsUnchangedDatabase),
            ("방금 온 기록은 한 번만 알린다", testFreshRecordOnce),
            ("오래된 기록은 알리지 않는다", testStaleRecordIgnored),
            ("알림센터 목록에서 빠지면 지운다", testDismissWhenRemovedFromList),
            ("글자 UUID가 목록에서 빠지면 지운다", testDismissStringUUID),
            ("목록에 한 번도 없던 기록은 남겨 둔다", testKeepUntilListedOnce),
            ("기록 행이 사라지면 지운다", testDismissWhenRowDeleted),
            ("WAL에만 있는 기록을 읽는다", testReadsWalOnlyRecord),
            ("같은 앱의 같은 글은 한 번만 알린다", testDuplicateTextSameApp),
            ("다른 앱의 같은 글은 각각 알린다", testDuplicateTextOtherApp),
            ("중복 판정이 지나면 같은 글도 다시 알린다", testDuplicateTextExpires)
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
            print("\(tests.count)개 모두 통과")
            return 0
        }
        print("\(tests.count)개 중 \(failed)개 실패")
        return 1
    }

    private static func testPackedUUIDs() throws {
        let first = uuid(0x10)
        let second = uuid(0x20)
        let index = NotificationWatcher.DeliveredIndex([first + second])
        try expect(index.contains(first, text: ""), "첫 UUID가 없다")
        try expect(index.contains(second, text: ""), "둘째 UUID가 없다")
        try expect(!index.contains(uuid(0x30), text: ""), "없는 UUID가 있다고 나왔다")
        let header = Data(repeating: 0, count: 16) + first
        try expect(NotificationWatcher.DeliveredIndex([header]).contains(first, text: ""), "헤더 뒤의 UUID가 없다")
    }

    private static func testStringUUIDs() throws {
        let raw = uuid(0x40)
        let text = uuidText(raw)
        let upper = Data(text.uppercased().utf8)
        let lower = Data(text.utf8)
        try expect(NotificationWatcher.DeliveredIndex([upper]).contains(raw, text: text), "대문자 UUID를 못 찾았다")
        try expect(NotificationWatcher.DeliveredIndex([lower]).contains(raw, text: text), "소문자 UUID를 못 찾았다")
        try expect(!NotificationWatcher.DeliveredIndex([upper]).contains(uuid(0x41), text: uuidText(uuid(0x41))), "다른 UUID가 있다고 나왔다")
    }

    private static func testUnalignedUUID() throws {
        let raw = uuid(0x50)
        let shifted = Data([0xAB, 0xCD]) + raw
        try expect(NotificationWatcher.DeliveredIndex([shifted]).contains(raw, text: ""), "어긋난 UUID가 없다")
        try expect(!NotificationWatcher.DeliveredIndex([Data([0x01, 0x02])]).contains(raw, text: ""), "짧은 목록에서 찾았다고 나왔다")
        try expect(!NotificationWatcher.DeliveredIndex([raw]).contains(Data(repeating: 1, count: 15), text: ""), "16바이트가 아닌 값을 찾았다")
    }

    private static func testSkipsUnchangedDatabase() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            flushMain()
            let copied = try fixture.snapshotIdentity()
            watcher.checkOnce()
            watcher.checkOnce()
            watcher.checkOnce()
            flushMain()
            try expect(try fixture.snapshotIdentity() == copied, "같은 파일인데 사본이 바뀌었다")
            try expect(box.notices.isEmpty, "기준만 잡는데 알림이 나왔다")
        }
    }

    private static func testFreshRecordOnce() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0x60, title: "안녕", body: "본문", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "알림 \(box.notices.count)개")
            try expect(box.notices.first?.title == "안녕", "제목 \(box.notices.first?.title ?? "")")
            try expect(box.notices.first?.body == "본문", "본문 \(box.notices.first?.body ?? "")")
            try expect(box.notices.first?.bundleID == Fixture.bundleID, "번들 \(box.notices.first?.bundleID ?? "")")
            let copied = try fixture.snapshotIdentity()
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "같은 기록을 다시 알렸다")
            try expect(try fixture.snapshotIdentity() == copied, "새 기록이 없는데 사본을 다시 만들었다")
        }
    }

    private static func testStaleRecordIgnored() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0x70, title: "어제", body: "지난 알림", fresh: false, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.isEmpty, "오래된 기록을 알렸다")
            try expect(box.dismissals.isEmpty, "오래된 기록을 지웠다고 했다")
        }
    }

    private static func testDismissWhenRemovedFromList() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            let raw = try fixture.insert(id: 1, mark: 0x80, title: "남음", body: "본문", fresh: true, listed: true)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "알림이 안 왔다")
            try expect(box.dismissals.isEmpty, "목록에 있는데 지웠다")
            try fixture.setDelivered(uuid(0x81))
            watcher.checkOnce()
            flushMain()
            try expect(box.dismissals.count == 1, "지움 \(box.dismissals.count)번")
            try expect(box.dismissals.first?.0 == Fixture.bundleID, "번들이 다르다")
            try expect(box.dismissals.first?.1 == "남음", "제목이 다르다")
            try expect(box.dismissals.first?.2 == "본문", "본문이 다르다")
            try expect(raw.count == 16, "UUID 길이가 다르다")
            watcher.checkOnce()
            flushMain()
            try expect(box.dismissals.count == 1, "지움을 반복했다")
        }
    }

    private static func testDismissStringUUID() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            let raw = try fixture.insert(id: 1, mark: 0x90, title: "글자", body: "목록", fresh: true, listed: false)
            try fixture.setDelivered(Data(uuidText(raw).uppercased().utf8))
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1 && box.dismissals.isEmpty, "글자 목록에 있는 기록을 바로 지웠다")
            try fixture.setDelivered(Data("gone".utf8))
            watcher.checkOnce()
            flushMain()
            try expect(box.dismissals.count == 1, "글자 목록에서 빠져도 안 지웠다")
        }
    }

    private static func testKeepUntilListedOnce() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0xA0, title: "대기", body: "아직", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1 && box.dismissals.isEmpty, "오자마자 지웠다")
            try fixture.touch()
            watcher.checkOnce()
            flushMain()
            try expect(box.dismissals.isEmpty, "목록에 들어간 적 없는 기록을 지웠다")
        }
    }

    private static func testDismissWhenRowDeleted() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0xB0, title: "삭제", body: "행", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try fixture.deleteRecord(1)
            watcher.checkOnce()
            flushMain()
            try expect(box.dismissals.count == 1, "행을 지워도 알림이 남았다")
        }
    }

    private static func testDuplicateTextSameApp() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0xD0, title: "빌드 성공", body: "같은 글", fresh: true, listed: false)
            try fixture.insert(id: 2, mark: 0xD1, title: "빌드 성공", body: "같은 글", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "알림 \(box.notices.count)개")
        }
    }

    private static func testDuplicateTextOtherApp() throws {
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0xD2, title: "사진", body: "첨부", fresh: true, listed: false, bundle: "com.example.a")
            try fixture.insert(id: 2, mark: 0xD3, title: "사진", body: "첨부", fresh: true, listed: false, bundle: "com.example.b")
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 2, "알림 \(box.notices.count)개")
        }
    }

    private static func testDuplicateTextExpires() throws {
        let previous = NotificationWatcher.dedupeWindow
        NotificationWatcher.dedupeWindow = 45
        defer { NotificationWatcher.dedupeWindow = previous }
        try withFixture { fixture, watcher, box in
            watcher.checkOnce()
            try fixture.insert(id: 1, mark: 0xD4, title: "다시", body: "같은", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "첫 알림이 없다")
            NotificationWatcher.dedupeWindow = -1
            try fixture.insert(id: 2, mark: 0xD5, title: "다시", body: "같은", fresh: true, listed: false)
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 2, "만료 뒤 \(box.notices.count)개")
        }
    }

    private static func testReadsWalOnlyRecord() throws {
        try withFixture { fixture, watcher, box in
            try fixture.insert(id: 1, mark: 0xC0, title: "기준", body: "이전", fresh: false, listed: false)
            watcher.checkOnce()
            flushMain()
            try fixture.reopenInWALMode()
            try fixture.insert(id: 2, mark: 0xC1, title: "월", body: "최신", fresh: true, listed: false)
            let hidden = try fixture.countRecords(matchingID: 2, immutable: true)
            let visible = try fixture.countRecords(matchingID: 2, immutable: false)
            try expect(hidden == 0, "immutable로 열었는데 WAL 기록이 \(hidden)개 보인다")
            try expect(visible == 1, "읽기 전용으로 WAL 기록이 안 보인다")
            watcher.checkOnce()
            flushMain()
            try expect(box.notices.count == 1, "WAL 기록을 알림 \(box.notices.count)개로 받았다")
            try expect(box.notices.first?.title == "월", "제목 \(box.notices.first?.title ?? "")")
        }
    }

    private static func withFixture(_ body: (Fixture, NotificationWatcher, Box) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let box = Box()
        let watcher = NotificationWatcher()
        watcher.onNotice = { box.notices.append($0) }
        watcher.onDismiss = { bundle, title, body in
            box.dismissals.append((bundle, title, body))
        }
        try body(fixture, watcher, box)
    }

    private static func flushMain() {
        for _ in 0..<8 {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
    }

    fileprivate static func uuid(_ mark: UInt8) -> Data {
        Data([mark] + Array(repeating: mark ^ 0x5A, count: 15))
    }

    private static func uuidText(_ data: Data) -> String {
        let bytes = [UInt8](data)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString.lowercased()
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

private final class Box {
    var notices: [SystemNotice] = []
    var dismissals: [(String, String, String)] = []
}

private final class Fixture {
    static let bundleID = "com.example.fixture"

    let root: URL
    let database: URL
    private var writer: OpaquePointer?
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mochinotch-selftest-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        database = source.appendingPathComponent("db")
        NotificationProbe.databaseOverride = database
        NotificationWatcher.snapshotRoot = root.appendingPathComponent("snap", isDirectory: true)
        writer = try open()
        try exec("""
            CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier VARCHAR, badge INTEGER NULL);
            CREATE TABLE record (
                rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB,
                request_date REAL, request_last_date REAL, delivered_date REAL,
                presented Bool, style INTEGER, snooze_fire_date REAL
            );
            CREATE TABLE delivered (app_id INTEGER PRIMARY KEY, list BLOB);
            INSERT INTO app (app_id, identifier) VALUES (1, '\(Self.bundleID)');
            """)
    }

    func close() {
        if let writer {
            sqlite3_close(writer)
        }
        writer = nil
        NotificationProbe.databaseOverride = nil
        NotificationWatcher.snapshotRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mochinotch-noted", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func insert(id: Int64, mark: UInt8, title: String, body: String, fresh: Bool, listed: Bool, bundle: String = Fixture.bundleID) throws -> Data {
        let raw = NotificationWatcherSelfTest.uuid(mark)
        let plist: [String: Any] = [
            "app": bundle,
            "req": ["titl": title, "body": body]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let when = Date().timeIntervalSince1970 - (fresh ? 0 : 86_400)
        try execute("INSERT INTO record (rec_id, app_id, uuid, data, request_date) VALUES (?, 1, ?, ?, ?)") { statement in
            sqlite3_bind_int64(statement, 1, id)
            bind(statement, 2, raw)
            bind(statement, 3, data)
            sqlite3_bind_double(statement, 4, when)
        }
        if listed {
            try setDelivered(raw)
        }
        return raw
    }

    func setDelivered(_ list: Data) throws {
        try exec("DELETE FROM delivered WHERE app_id = 1")
        try execute("INSERT INTO delivered (app_id, list) VALUES (1, ?)") { statement in
            bind(statement, 1, list)
        }
    }

    func deleteRecord(_ id: Int64) throws {
        try execute("DELETE FROM record WHERE rec_id = ?") { statement in
            sqlite3_bind_int64(statement, 1, id)
        }
    }

    func touch() throws {
        try exec("UPDATE app SET badge = COALESCE(badge, 0) + 1 WHERE app_id = 1")
    }

    func reopenInWALMode() throws {
        sqlite3_close(writer)
        writer = nil
        writer = try open()
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA wal_autocheckpoint=0")
    }

    func countRecords(matchingID id: Int64, immutable: Bool) throws -> Int {
        var db: OpaquePointer?
        let mode = immutable ? "immutable=1" : "mode=ro"
        let uri = "file:\(database.path)?\(mode)"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "열지 못함"
            sqlite3_close(db)
            throw TestFailure(message)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM record WHERE rec_id = ?", -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    func snapshotIdentity() throws -> (UInt64, UInt64) {
        let path = NotificationWatcher.snapshotRoot.appendingPathComponent("db").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
            throw TestFailure("사본이 없다")
        }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        return (inode, size)
    }

    private func open() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "열지 못함"
            sqlite3_close(db)
            throw TestFailure(message)
        }
        return db
    }

    private func exec(_ sql: String) throws {
        guard let writer else { throw TestFailure("데이터베이스가 닫혀 있다") }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(writer, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(writer))
            sqlite3_free(error)
            throw TestFailure(message)
        }
    }

    private func execute(_ sql: String, bind: (OpaquePointer?) -> Void) throws {
        guard let writer else { throw TestFailure("데이터베이스가 닫혀 있다") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(writer, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(String(cString: sqlite3_errmsg(writer)))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestFailure(String(cString: sqlite3_errmsg(writer)))
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ data: Data) {
        _ = data.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), sqliteTransient)
        }
    }
}
