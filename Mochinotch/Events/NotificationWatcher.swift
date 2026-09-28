import AppKit
import ApplicationServices
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

/// 배너가 뜨는 즉시 알림 센터 화면에서 읽고, 배너 없이 쌓인 기록은 데이터베이스로 보완한다.
/// 데이터베이스는 배너가 사라진 뒤에야 갱신되는 경우가 있다.
final class NotificationWatcher {
    var onNotice: ((SystemNotice) -> Void)?
    var onAccessChange: ((NotificationAccess) -> Void)?
    /// 알림센터에서 기록이 사라진 항목. 번들, 제목, 본문.
    var onDismiss: ((String, String, String) -> Void)?
    /// 배너 뒤에도 이 앱의 알림 기록이 없다.
    var onUnstored: ((String) -> Void)?
    /// 뒤늦게 알림 기록과 연결되었다.
    var onStored: ((String) -> Void)?

    private let queue = DispatchQueue(label: "dev.sleeeppy.mochinotch.notifications")
    private var timer: DispatchSourceTimer?
    private var lastID: Int64?
    private var access: NotificationAccess = .starting
    private var recentKeys: [String: Date] = [:]
    /// 배너로 이미 보여 준 기록. 행이 지워지거나 알림센터 목록에서 빠지면 노치에서도 뺀다.
    private var tracked: [Int64: TrackedNotice] = [:]
    /// 배너는 떴는데 아직 데이터베이스 행과 연결하지 못한 알림.
    private var pending: [(bundleID: String, title: String, body: String, at: Date)] = []
    private var bundleIDsByName: [String: String] = [:]
    private var didLogAccessibility = false
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(15))
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
            self?.lastID = nil
        }
    }

    private func tick() {
        for notice in readBanners() where accept(notice) {
            let shown = Self.storedText(notice)
            pending.append((notice.bundleID, shown.title, shown.body, Date()))
            Self.log("banner \(notice.bundleID) \(notice.title)")
            deliver(notice)
        }
        guard let db = openLive() else { return }
        defer { sqlite3_close(db) }
        if lastID == nil {
            lastID = maxRecordID(db)
            Self.log("baseline id=\(lastID ?? -1)")
            return
        }
        for record in readNew(db) {
            let stored = Self.storedText(record.notice)
            let key = "\(record.notice.bundleID)|\(record.notice.title)|\(record.notice.body)"
            let loose = "\(record.notice.title)|\(record.notice.body)"
            let known = recentKeys[key] != nil || recentKeys[loose] != nil
            // 알림센터를 열면 지난 기록 번호가 다시 보인다. 방금 온 것이거나, 이미 배너로 본 것만 따라간다.
            guard known || Self.isFresh(record.delivered) else { continue }
            tracked[record.id] = TrackedNotice(
                bundleID: record.notice.bundleID,
                title: stored.title,
                body: stored.body,
                uuid: record.uuid,
                confirmedInDelivered: false
            )
            guard !known, accept(record.notice) else { continue }
            Self.log("notice \(record.notice.bundleID) \(stored.title)")
            deliver(record.notice)
        }
        linkPending(db)
        dismissCleared(db)
    }


    private struct TrackedNotice {
        var bundleID: String
        var title: String
        var body: String
        var uuid: Data
        var confirmedInDelivered: Bool
    }

    /// 배너와 글자가 달라도, 그 앱의 가장 최근 기록을 배너에 붙인다.
    private func linkPending(_ db: OpaquePointer) {
        let now = Date()
        pending.removeAll { now.timeIntervalSince($0.at) > 45 }
        var stillPending: [(bundleID: String, title: String, body: String, at: Date)] = []
        for item in pending {
            guard let row = newestRecord(db, bundleID: item.bundleID) else {
                if Date().timeIntervalSince(item.at) > 2, loggedMissingLinks.insert(item.bundleID.lowercased()).inserted {
                    Self.log("no row \(item.bundleID)")
                    let bundleID = item.bundleID
                    DispatchQueue.main.async { [onUnstored] in
                        onUnstored?(bundleID)
                    }
                }
                stillPending.append(item)
                continue
            }
            if let existing = tracked[row.id] {
                if existing.title == item.title && existing.body == item.body { continue }
                stillPending.append(item)
                continue
            }
            tracked[row.id] = TrackedNotice(
                bundleID: item.bundleID,
                title: item.title,
                body: item.body,
                uuid: row.uuid,
                confirmedInDelivered: false
            )
            Self.log("linked \(row.id) \(item.bundleID)")
            let bundleID = item.bundleID
            DispatchQueue.main.async { [onStored] in
                onStored?(bundleID)
            }
        }
        pending = stillPending
    }

    /// 알림센터에서 기록이 사라지거나, 보여 주던 목록에서 빠지면 바로 뺀다.
    private func dismissCleared(_ db: OpaquePointer) {
        guard !tracked.isEmpty else { return }
        guard let present = existingIDs(db, ids: Array(tracked.keys)) else { return }
        let lists = deliveredLists(db)
        let gone = tracked.keys.filter { id in
            guard let stored = tracked[id] else { return false }
            if !present.contains(id) { return true }
            let listed = listsContain(stored.uuid, lists)
            if listed {
                tracked[id]?.confirmedInDelivered = true
                return false
            }
            return stored.confirmedInDelivered
        }
        for id in gone {
            guard let stored = tracked.removeValue(forKey: id) else { continue }
            let replaced = tracked.values.contains { $0.title == stored.title && $0.body == stored.body }
            guard !replaced else { continue }
            Self.log("dismissed \(stored.bundleID)")
            let bundleID = stored.bundleID
            let title = stored.title
            let body = stored.body
            DispatchQueue.main.async { [onDismiss] in
                onDismiss?(bundleID, title, body)
            }
        }
    }

    private var loggedMissingLinks = Set<String>()

    /// 앱 테이블이 아니라 기록 안의 번들로 찾는다. 기준 이후에 생긴 행만 배너에 붙인다.
    private func newestRecord(_ db: OpaquePointer, bundleID: String) -> (id: Int64, uuid: Data)? {
        let sql = """
            SELECT r.rec_id, r.uuid, r.data, r.request_date, a.identifier
            FROM record r LEFT JOIN app a ON a.app_id = r.app_id
            ORDER BY r.rec_id DESC LIMIT 40
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let floor = lastID ?? 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let dataLength = Int(sqlite3_column_bytes(statement, 2))
            guard dataLength > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: dataLength)
            let appIdentifier = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            guard let notice = Self.decode(data, fallbackBundleID: appIdentifier) else { continue }
            let matchesBanner = notice.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame
                || appIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
            guard matchesBanner else { continue }
            let requested = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            guard id > floor || Self.isFresh(requested) else { continue }
            let uuidLength = Int(sqlite3_column_bytes(statement, 1))
            let uuid: Data
            if uuidLength > 0, let uuidBytes = sqlite3_column_blob(statement, 1) {
                uuid = Data(bytes: uuidBytes, count: uuidLength)
            } else {
                uuid = Data()
            }
            return (id, uuid)
        }
        return nil
    }

    private func deliveredLists(_ db: OpaquePointer) -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT list FROM delivered", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var lists: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let length = Int(sqlite3_column_bytes(statement, 0))
            guard length > 0, let bytes = sqlite3_column_blob(statement, 0) else { continue }
            lists.append(Data(bytes: bytes, count: length))
        }
        return lists
    }

    private func listsContain(_ uuid: Data, _ lists: [Data]) -> Bool {
        guard uuid.count == 16 else { return false }
        if lists.contains(where: { $0.range(of: uuid) != nil }) { return true }
        let bytes = [UInt8](uuid)
        let formatted = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString
        let encoded = [formatted.lowercased(), formatted.uppercased()].compactMap { $0.data(using: .utf8) }
        return lists.contains { list in encoded.contains { list.range(of: $0) != nil } }
    }

    private func deliver(_ notice: SystemNotice) {
        DispatchQueue.main.async { [onNotice] in
            onNotice?(notice)
        }
    }

    /// 같은 배너가 떠 있는 동안, 그리고 데이터베이스가 뒤늦게 같은 글을 줄 때 한 번만 반영한다.
    private func accept(_ notice: SystemNotice) -> Bool {
        let key = "\(notice.bundleID)|\(notice.title)|\(notice.body)"
        if recentKeys[key] != nil { return false }
        let now = Date()
        recentKeys[key] = now
        recentKeys["\(notice.title)|\(notice.body)"] = now
        if recentKeys.count > 300 {
            let oldest = recentKeys.sorted { $0.value < $1.value }.prefix(100).map(\.key)
            for key in oldest { recentKeys.removeValue(forKey: key) }
        }
        return true
    }

    /// 오른쪽 위 배너의 글. 데이터베이스보다 먼저 있다.
    private func readBanners() -> [SystemNotice] {
        guard AXIsProcessTrusted() else {
            if !didLogAccessibility {
                didLogAccessibility = true
                Self.log("accessibility missing")
            }
            return []
        }
        // 알림센터를 열어 둔 목록은 지난 알림이다. 배너만 새 알림으로 본다.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.notificationcenterui" {
            return []
        }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
        guard let app = apps.first else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return [] }
        return list.flatMap(notices(in:))
    }

    private func notices(in element: AXUIElement) -> [SystemNotice] {
        var description: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        let described = (description as? String) ?? ""
        let texts = staticTexts(in: element)
        if let title = texts.first, !title.isEmpty, described.contains(title) {
            // 알림센터를 연 목록 행도 배너와 같은 역할이다. 목록에는 제목(AXHeading)이 같이 있다.
            guard elementSubrole(element) == "AXNotificationCenterBanner" else { return [] }
            guard !isInsideOpenPanel(element) else { return [] }
            let content = texts.filter { !Self.isRelativeStamp($0) }
            let headline = content.first ?? title
            let message = content.dropFirst().joined(separator: "\n")
            let name = appName(from: described, title: title)
            let bundleID = bundleID(forAppName: name) ?? ""
            guard !bundleID.isEmpty, bundleID != ownBundleID else { return [] }
            return [SystemNotice(bundleID: bundleID, title: headline, subtitle: "", body: message)]
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).flatMap(notices(in:))
    }

    private func elementSubrole(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        return (value as? String) ?? ""
    }

    /// 열린 알림센터 목록의 행은 제목과 같은 묶음에 있다. 오른쪽 위 배너에는 그 제목이 없다.
    private func isInsideOpenPanel(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let node = current else { return false }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef else { return false }
            let parent = parentRef as! AXUIElement
            if childrenContainRole(parent, role: "AXHeading") { return true }
            current = parent
        }
        return false
    }

    private func childrenContainRole(_ element: AXUIElement, role wanted: String) -> Bool {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return false }
        for child in list {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if (role as? String) == wanted { return true }
        }
        return false
    }

    private func appName(from description: String, title: String) -> String {
        guard let range = description.range(of: title), range.lowerBound > description.startIndex else { return "" }
        return description[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func staticTexts(in element: AXUIElement) -> [String] {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if (role as? String) == kAXStaticTextRole as String {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            if let text = value as? String, !text.isEmpty { return [text] }
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).flatMap(staticTexts(in:))
    }

    private func bundleID(forAppName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = bundleIDsByName[trimmed] { return cached }
        let directories = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        for directory in directories {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(item)
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                let names = Self.applicationNames(bundle) + [item.replacingOccurrences(of: ".app", with: "")]
                if names.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    bundleIDsByName[trimmed] = identifier
                    return identifier
                }
            }
        }
        return nil
    }

    private static func applicationNames(_ bundle: Bundle) -> [String] {
        var names: [String] = []
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = bundle.object(forInfoDictionaryKey: key) as? String { names.append(name) }
        }
        for language in ["ko", "en"] {
            guard let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
                  let dictionary = NSDictionary(contentsOfFile: path) else { continue }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = dictionary[key] as? String { names.append(name) }
            }
        }
        return names
    }

    /// 읽기 전용으로 원본을 열면 WAL에만 있는 최신 알림이 안 보인다. 세 파일을 같이 떠서 연다.
    private func openLive() -> OpaquePointer? {
        let source = NotificationProbe.databaseURL
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            let listable = (try? FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)) != nil
            report(listable ? .missingDatabase : .denied)
            Self.log("open denied listable=\(listable)")
            return nil
        }
        let path = snapshotDatabase(source)?.path ?? source.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let uri = "file:\(path)?immutable=1"
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            report(message.contains("authorization") ? .denied : .failed(message))
            Self.log("open failed \(message)")
            return nil
        }
        sqlite3_busy_timeout(handle, 80)
        report(.watching)
        return handle
    }

    private func snapshotDatabase(_ source: URL) -> URL? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mochinotch-noted", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let dest = root.appendingPathComponent("db")
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: source.path + suffix)
                let to = URL(fileURLWithPath: dest.path + suffix)
                if FileManager.default.fileExists(atPath: to.path) {
                    try FileManager.default.removeItem(at: to)
                }
                // 잠금 파일까지 복사하면 읽기 연결이 그 잠금에서 멈춘다.
                guard suffix != "-shm", FileManager.default.fileExists(atPath: from.path) else { continue }
                try FileManager.default.copyItem(at: from, to: to)
            }
            return dest
        } catch {
            Self.log("snapshot failed")
            return nil
        }
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

    private struct StoredRecord {
        var id: Int64
        var notice: SystemNotice
        var delivered: Double?
        var uuid: Data
    }

    /// 처음 요청된 시각이 최근인 것만 새 알림이다. 초·밀리초, 유닉스·2001년 기준을 모두 본다.
    private static func isFresh(_ delivered: Double?) -> Bool {
        guard let delivered, delivered > 1 else { return false }
        for scale in [1.0, 1000.0] {
            let seconds = delivered / scale
            let candidates = [
                Date(timeIntervalSince1970: seconds),
                Date(timeIntervalSinceReferenceDate: seconds)
            ]
            if candidates.contains(where: { abs($0.timeIntervalSinceNow) < 90 }) { return true }
        }
        return false
    }

    /// 배너 안에 같이 있는 ‘6분 전’은 본문이 아니다.
    private static func isRelativeStamp(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["방금", "지금", "어제", "그저께"].contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return true
        }
        if trimmed.range(of: #"^\d+\s*(초|분|시간|일|주|달|개월)\s*전$"#, options: .regularExpression) != nil {
            return true
        }
        return trimmed.range(of: #"^\d+\s*[smhdw]\s*ago$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func storedText(_ notice: SystemNotice) -> (title: String, body: String) {
        let title = [notice.title, notice.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        return (title, notice.body)
    }

    private func existingIDs(_ db: OpaquePointer, ids: [Int64]) -> Set<Int64>? {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT rec_id FROM record WHERE rec_id IN (\(placeholders))", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        for (offset, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(offset + 1), id)
        }
        var present = Set<Int64>()
        while sqlite3_step(statement) == SQLITE_ROW {
            present.insert(sqlite3_column_int64(statement, 0))
        }
        return present
    }

    private func readNew(_ db: OpaquePointer) -> [StoredRecord] {
        guard let since = lastID else { return [] }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.request_date, r.uuid
            FROM record r LEFT JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 40
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            fail(db)
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, since)

        var records: [StoredRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            lastID = id
            let identifier = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let length = Int(sqlite3_column_bytes(statement, 2))
            guard length > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: length)
            if let notice = Self.decode(data, fallbackBundleID: identifier), notice.bundleID != ownBundleID {
                let delivered = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
                let uuidLength = Int(sqlite3_column_bytes(statement, 4))
                let uuid: Data
                if uuidLength > 0, let uuidBytes = sqlite3_column_blob(statement, 4) {
                    uuid = Data(bytes: uuidBytes, count: uuidLength)
                } else {
                    uuid = Data()
                }
                records.append(StoredRecord(id: id, notice: notice, delivered: delivered, uuid: uuid))
            } else if let keys = Self.topLevelKeys(data) {
                Self.log("record \(id) skipped keys=\(keys.joined(separator: ",")) app=\(identifier ?? "")")
            }
        }
        return records
    }

    /// 사본이 중간에 깨져 있으면 이번만 건너뛴다. 기준 번호는 유지해서 다음 읽기에서 다시 본다.
    private func fail(_ db: OpaquePointer) {
        guard access != .watching else { return }
        report(.failed(String(cString: sqlite3_errmsg(db))))
    }

    /// 기록은 바이너리 plist다. `app`은 번들 ID, `req`의 `titl`/`subt`/`body`가 배너 글자다.
    static func decode(_ data: Data, fallbackBundleID: String?) -> SystemNotice? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let request = requestDictionary(plist["req"]) ?? [:]
        let bundleID = string(plist["app"]) ?? string(request["app"]) ?? fallbackBundleID ?? ""
        let title = firstString(request, keys: ["titl", "title", "ttl"]) ?? firstString(plist, keys: ["titl", "title"]) ?? ""
        let subtitle = firstString(request, keys: ["subt", "subtitle", "subTitle"]) ?? ""
        let body = firstString(request, keys: ["body", "message", "bod"]) ?? firstString(plist, keys: ["body"]) ?? ""
        guard !bundleID.isEmpty, !(title.isEmpty && body.isEmpty) else { return nil }
        return SystemNotice(bundleID: bundleID, title: title, subtitle: subtitle, body: body)
    }

    static func topLevelKeys(_ data: Data) -> [String]? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist.keys.sorted()
    }

    private static func requestDictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        guard let data = value as? Data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = string(dictionary[key]), !text.isEmpty { return text }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let targets = [
            URL(fileURLWithPath: "/tmp/mochinotch-notices.log"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Mochinotch/notifications.log")
        ]
        for url in targets {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
