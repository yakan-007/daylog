import XCTest
@testable import FragmentCamera

final class VlogClipEditStoreTests: XCTestCase {
    func testEditPersistsAndRequestedOrderIsPreserved() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let first = VlogClipEdit(
            assetLocalIdentifier: "first",
            block: VlogStampBlock(caption: "one")
        )
        let second = VlogClipEdit(
            assetLocalIdentifier: "second",
            block: VlogStampBlock(showsPlace: true, placeName: "海辺")
        )
        let writer = VlogClipEditStore(fileURL: fileURL)
        try await writer.save(first, clipDuration: 5)
        try await writer.save(second, clipDuration: 4)

        let reader = VlogClipEditStore(fileURL: fileURL)
        let loaded = try await reader.edits(
            for: ["second", "missing", "first"]
        )

        XCTAssertEqual(loaded[0]?.assetLocalIdentifier, "second")
        XCTAssertNil(loaded[1])
        XCTAssertEqual(loaded[2]?.assetLocalIdentifier, "first")
    }

    func testCorruptFileIsMovedAsideAndEditingKeepsWorking() async throws {
        let fileURL = temporaryFileURL()
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: fileURL)
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in leftovers where name.hasPrefix(baseName) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
        let store = VlogClipEditStore(fileURL: fileURL)

        try await store.save(
            VlogClipEdit(
                assetLocalIdentifier: "asset-1",
                block: VlogStampBlock(caption: "new")
            ),
            clipDuration: 3
        )

        // 元の壊れたデータは上書きせず、別名で残っている。
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let backupName = try XCTUnwrap(names.first { $0.hasPrefix(baseName + ".unreadable-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backupName)), corruptData)
        // 新しい編集は保存できている。
        let reloaded = try await VlogClipEditStore(fileURL: fileURL).edit(for: "asset-1")
        XCTAssertEqual(reloaded?.block.caption, "new")
    }

    func testSavedEditIsNormalized() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = VlogClipEditStore(fileURL: fileURL)
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(caption: "title", anchor: VlogNormalizedPoint(x: 2, y: -1), scale: 0.1)
        )

        try await store.save(edit, clipDuration: 3)
        let loaded = try await store.edit(for: "asset-1")

        XCTAssertEqual(loaded?.block.anchor, VlogNormalizedPoint(x: 1, y: 0))
        XCTAssertEqual(loaded?.block.scale, VlogStampBlock.scaleRange.lowerBound)
    }

    func testOutdatedFormatIsDiscardedAndReplacedOnSave() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data(#"{"version":1,"edits":[{"legacy":true}]}"#.utf8).write(to: fileURL)
        let store = VlogClipEditStore(fileURL: fileURL)

        let before = try await store.edit(for: "asset-1")
        XCTAssertNil(before)

        try await store.save(
            VlogClipEdit(
                assetLocalIdentifier: "asset-1",
                block: VlogStampBlock(caption: "new")
            ),
            clipDuration: 3
        )
        let reloaded = try await VlogClipEditStore(fileURL: fileURL).edit(for: "asset-1")
        XCTAssertEqual(reloaded?.block.caption, "new")
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VlogClipEditStoreTests-\(UUID().uuidString).json")
    }
}
