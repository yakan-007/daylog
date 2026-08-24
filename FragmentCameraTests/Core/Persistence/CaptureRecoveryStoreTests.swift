import XCTest
@testable import FragmentCamera

final class CaptureRecoveryStoreTests: XCTestCase {
    func testStagesCaptureOutsideTemporarySourceAndRestoresItAfterReload() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureRecoveryStoreTests-\(UUID().uuidString)")
        let sourceRoot = testRoot.appendingPathComponent("Source", isDirectory: true)
        let recoveryRoot = testRoot.appendingPathComponent("Recovery", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        let sourceURL = sourceRoot.appendingPathComponent("capture.mov")
        try Data([0x01, 0x02]).write(to: sourceURL)
        let capturedAt = Date(timeIntervalSince1970: 1_000)

        let store = CaptureRecoveryStore(rootURL: recoveryRoot)
        let staged = try store.stageCapture(at: sourceURL, capturedAt: capturedAt)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertEqual(staged.capturedAt, capturedAt)

        let reloaded = CaptureRecoveryStore(rootURL: recoveryRoot)
            .recoverableCaptures()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.id, staged.id)
        XCTAssertEqual(reloaded.first?.url, staged.url)
        XCTAssertEqual(reloaded.first?.capturedAt, capturedAt)
    }

    func testListsNewestFirstAndDiscardRemovesOnlySelectedCapture() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureRecoveryStoreTests-\(UUID().uuidString)")
        let sourceRoot = testRoot.appendingPathComponent("Source", isDirectory: true)
        let recoveryRoot = testRoot.appendingPathComponent("Recovery", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        let olderSource = sourceRoot.appendingPathComponent("older.mov")
        let newerSource = sourceRoot.appendingPathComponent("newer.mov")
        try Data([0x01]).write(to: olderSource)
        try Data([0x02]).write(to: newerSource)
        let store = CaptureRecoveryStore(rootURL: recoveryRoot)
        let older = try store.stageCapture(
            at: olderSource,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = try store.stageCapture(
            at: newerSource,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(store.recoverableCaptures().map(\.id), [newer.id, older.id])

        store.discard(newer)

        XCTAssertFalse(FileManager.default.fileExists(atPath: newer.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.url.path))
        XCTAssertEqual(store.recoverableCaptures().map(\.id), [older.id])
    }
}
