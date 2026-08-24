import XCTest
@testable import FragmentCamera

final class TemporaryFileStoreTests: XCTestCase {
    func testCreatesFilesInsideDedicatedDirectoryAndRemovesThem() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryFileStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = TemporaryFileStore(rootURL: rootURL)

        let url = try store.makeURL(prefix: "capture", pathExtension: "mp4")
        try Data([0x01]).write(to: url)

        XCTAssertEqual(
            url.deletingLastPathComponent().standardizedFileURL.path,
            rootURL.standardizedFileURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        store.removeIfExists(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemovesOnlyExpiredFilesDuringCleanup() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryFileStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let now = Date(timeIntervalSince1970: 10_000)
        let store = TemporaryFileStore(rootURL: rootURL, now: { now })
        let expiredURL = try store.makeURL(prefix: "expired", pathExtension: "mp4")
        let recentURL = try store.makeURL(prefix: "recent", pathExtension: "mp4")
        try Data([0x01]).write(to: expiredURL)
        try Data([0x02]).write(to: recentURL)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-200)],
            ofItemAtPath: expiredURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10)],
            ofItemAtPath: recentURL.path
        )

        store.removeFilesOlderThan(100)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }
}
