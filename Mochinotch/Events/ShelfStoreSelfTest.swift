import Foundation

/// `Mochinotch --self-test` 에서 맡기기 경로 저장을 확인한다.
enum ShelfStoreSelfTest {
    static func run() -> Int32 {
        let suiteName = "dev.sleeeppy.mochinotch.shelf-self-test"
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        suite.removePersistentDomain(forName: suiteName)
        let root = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.sleeeppy.mochinotch/ShelfSelfTest/\(UUID().uuidString)", isDirectory: true)
        let previousDirectory = ShelfStore.directory
        let previousDefaults = ShelfStore.defaults
        ShelfStore.directory = root.appendingPathComponent("Shelf", isDirectory: true)
        ShelfStore.defaults = suite
        defer {
            ShelfStore.directory = previousDirectory
            ShelfStore.defaults = previousDefaults
            try? FileManager.default.removeItem(at: root)
            suite.removePersistentDomain(forName: suiteName)
        }

        let tests: [(String, () throws -> Void)] = [
            ("바탕화면 파일은 임시 파일이 아니다", testDesktopIsStable),
            ("임시 폴더와 캡처 자리는 임시 파일이다", testScratchIsTemporary),
            ("이름만 같은 사용자 폴더는 임시 파일이 아니다", testLookalikeIsStable),
            ("제자리 파일은 경로만 남긴다", testAdoptKeepsStablePath),
            ("임시 파일은 노치 폴더로 복사한다", testAdoptCopiesTemporary),
            ("같은 이름은 번호를 붙여 복사한다", testAdoptRenamesCollision),
            ("임시 링크는 원본이 임시일 때만 복사한다", testAdoptFollowsSymlink),
            ("없어진 경로는 다시 켤 때 빠진다", testRetainedDropsMissing),
            ("노치 폴더 밖의 파일은 지우지 않는다", testSweepStaysInside)
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
            print("맡기기 \(tests.count)개 모두 통과")
            return 0
        }
        print("맡기기 \(tests.count)개 중 \(failed)개 실패")
        return 1
    }

    private static func testDesktopIsStable() throws {
        let desktop = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/사진.png")
        try expect(!ShelfStore.isTemporary(desktop), "바탕화면 파일을 임시로 봤다")
        let downloads = URL(fileURLWithPath: "/Volumes/외장/자료.zip")
        try expect(!ShelfStore.isTemporary(downloads), "외장 디스크 파일을 임시로 봤다")
    }

    private static func testScratchIsTemporary() throws {
        let captured = URL(fileURLWithPath: "/private/var/folders/ab/cd/T/com.apple.screencapture/TemporaryItems/Shot.png")
        try expect(ShelfStore.isTemporary(captured), "캡처 임시 파일을 못 알아봤다")
        let cache = URL(fileURLWithPath: "/private/var/folders/ab/cd/C/com.apple.screencapture/Shot.png")
        try expect(ShelfStore.isTemporary(cache), "var/folders 캐시를 제자리 파일로 봤다")
        let container = URL(fileURLWithPath: "/Users/me/Library/Containers/com.apple.screencaptureui/Data/tmp/Shot.png")
        try expect(ShelfStore.isTemporary(container), "컨테이너 임시 파일을 못 알아봤다")
        let live = FileManager.default.temporaryDirectory.appendingPathComponent("mochinotch-shelf-\(UUID().uuidString).png")
        try expect(ShelfStore.isTemporary(live), "사용자 임시 폴더를 못 알아봤다")
        try expect(ShelfStore.isTemporary(URL(fileURLWithPath: "/tmp/Shot.png")), "/tmp를 못 알아봤다")
    }

    private static func testLookalikeIsStable() throws {
        let named = URL(fileURLWithPath: "/Users/me/Desktop/var/folders/사진.png")
        try expect(!ShelfStore.isTemporary(named), "바탕화면 하위 폴더를 임시로 봤다")
        let tmpName = URL(fileURLWithPath: "/Users/me/Documents/tmp/메모.txt")
        try expect(!ShelfStore.isTemporary(tmpName), "문서 폴더의 tmp를 임시로 봤다")
    }

    private static func testAdoptKeepsStablePath() throws {
        let folder = try makeFolder("Stable")
        let file = folder.appendingPathComponent("바다.jpg")
        try Data("beach".utf8).write(to: file)
        let kept = try adopted(file)
        try expect(ShelfStore.identity(kept) == ShelfStore.identity(file), "제자리 파일을 복사했다")
        try expect(!ShelfStore.isInsideShelf(kept), "제자리 파일이 노치 폴더에 있다")
    }

    private static func testAdoptCopiesTemporary() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("산-\(UUID().uuidString).jpg")
        try Data("cliff".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let kept = try adopted(file)
        try expect(ShelfStore.isInsideShelf(kept), "복사본이 노치 폴더 밖에 있다")
        try expect(FileManager.default.fileExists(atPath: file.path), "원본 임시 파일까지 지웠다")
        try expect(try Data(contentsOf: kept) == Data("cliff".utf8), "복사본 내용이 다르다")
        let again = try adopted(kept)
        try expect(ShelfStore.identity(again) == ShelfStore.identity(kept), "노치 폴더 파일을 한 번 더 복사했다")
    }

    private static func testAdoptRenamesCollision() throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent("같은이름-\(UUID().uuidString).txt")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(first.lastPathComponent)
        try Data("one".utf8).write(to: first)
        let kept = try adopted(first)
        try? FileManager.default.removeItem(at: first)
        try Data("two".utf8).write(to: second)
        defer { try? FileManager.default.removeItem(at: second) }
        let next = try adopted(second)
        try expect(kept.lastPathComponent != next.lastPathComponent, "같은 이름으로 덮어썼다")
        try expect(next.lastPathComponent.contains(" 2."), "두 번째 복사본 이름에 번호가 없다")
        try expect(try Data(contentsOf: kept) == Data("one".utf8), "첫 복사본이 바뀌었다")
        try expect(try Data(contentsOf: next) == Data("two".utf8), "둘째 복사본 내용이 다르다")
    }

    private static func testAdoptFollowsSymlink() throws {
        let folder = try makeFolder("Links")
        let stable = folder.appendingPathComponent("원본.txt")
        try Data("stay".utf8).write(to: stable)
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("link-\(UUID().uuidString).txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: stable)
        defer { try? FileManager.default.removeItem(at: link) }
        let kept = try adopted(link)
        try expect(ShelfStore.identity(kept) == ShelfStore.identity(stable), "임시 링크의 제자리 원본을 복사했다")

        let fleeting = FileManager.default.temporaryDirectory.appendingPathComponent("fleeting-\(UUID().uuidString).txt")
        try Data("gone".utf8).write(to: fleeting)
        defer { try? FileManager.default.removeItem(at: fleeting) }
        let stableLink = folder.appendingPathComponent("가리킴.txt")
        try FileManager.default.createSymbolicLink(at: stableLink, withDestinationURL: fleeting)
        let copied = try adopted(stableLink)
        try expect(ShelfStore.isInsideShelf(copied), "임시 원본을 가리키는 링크를 경로만 남겼다")
        try expect(try Data(contentsOf: copied) == Data("gone".utf8), "링크가 가리키던 내용을 복사하지 않았다")
    }

    private static func testRetainedDropsMissing() throws {
        let folder = try makeFolder("Remembered")
        let file = folder.appendingPathComponent("남아있음.txt")
        try Data("yes".utf8).write(to: file)
        ShelfStore.save([file.path, folder.appendingPathComponent("없어짐.txt").path])
        let kept = ShelfStore.retained().map(\.path)
        try expect(kept == [file.standardizedFileURL.path], "없어진 경로가 남아 있거나 순서가 바뀌었다")
    }

    private static func testSweepStaysInside() throws {
        let folder = try makeFolder("Outside")
        let outside = folder.appendingPathComponent("그대로.txt")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: ShelfStore.directory, withIntermediateDirectories: true)
        let orphan = ShelfStore.directory.appendingPathComponent("고아.txt")
        let owned = ShelfStore.directory.appendingPathComponent("복사본.txt")
        try Data("orphan".utf8).write(to: orphan)
        try Data("owned".utf8).write(to: owned)
        ShelfStore.sweep(keeping: [owned, outside])
        try expect(FileManager.default.fileExists(atPath: outside.path), "노치 폴더 밖 파일을 지웠다")
        try expect(FileManager.default.fileExists(atPath: owned.path), "맡아 둔 복사본을 지웠다")
        try expect(!FileManager.default.fileExists(atPath: orphan.path), "빠진 복사본이 노치 폴더에 남았다")
    }

    private static func makeFolder(_ name: String) throws -> URL {
        let folder = ShelfStore.directory
            .deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func adopted(_ url: URL) throws -> URL {
        guard let kept = ShelfStore.adopt(url) else { throw ShelfStoreTestFailure("파일을 맡기지 못했다") }
        return kept
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw ShelfStoreTestFailure(message) }
    }
}

private struct ShelfStoreTestFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
