import XCTest
@testable import FragmentCamera

final class VlogClipEditStoreTests: XCTestCase {
    func testEditPersistsAndRequestedOrderIsPreserved() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let first = VlogClipEdit(
            assetLocalIdentifier: "first",
            textOverlays: [VlogTextOverlay(source: .custom("one"))]
        )
        let second = VlogClipEdit(
            assetLocalIdentifier: "second",
            textOverlays: [VlogTextOverlay(source: .place(customName: "海辺"))]
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

    func testCorruptFileIsNotOverwrittenBySave() async throws {
        let fileURL = temporaryFileURL()
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = VlogClipEditStore(fileURL: fileURL)
        let edit = VlogClipEdit(assetLocalIdentifier: "asset-1")

        do {
            try await store.save(edit, clipDuration: 3)
            XCTFail("破損データを上書きしてはいけない")
        } catch {
            XCTAssertTrue(error is VlogClipEditStoreError)
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData)
    }

    func testSavedEditIsNormalizedToClipDuration() async throws {
        let fileURL = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = VlogClipEditStore(fileURL: fileURL)
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            textOverlays: [
                VlogTextOverlay(
                    source: .custom("title"),
                    timeRange: VlogOverlayTimeRange(start: 1, end: 99)
                )
            ]
        )

        try await store.save(edit, clipDuration: 3)
        let loaded = try await store.edit(for: "asset-1")

        XCTAssertEqual(
            loaded?.textOverlays.first?.timeRange,
            VlogOverlayTimeRange(start: 1, end: 3)
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VlogClipEditStoreTests-\(UUID().uuidString).json")
    }
}
