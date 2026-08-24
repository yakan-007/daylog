import XCTest
@testable import FragmentCamera

final class VideoStampRecipeStoreTests: XCTestCase {
    func testRecipePersistsAndKeepsRequestedOrder() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoStampRecipeStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = makeRecipe(identifier: "first", mode: .playbackOverlay)
        let second = makeRecipe(
            identifier: "second",
            mode: .burnOnCapture,
            visibilityOverride: VideoStampVisibilityOverride(
                hidesStamp: false,
                hiddenElements: [.place]
            )
        )
        let writer = VideoStampRecipeStore(fileURL: fileURL)
        try await writer.save([first, second])

        let reader = VideoStampRecipeStore(fileURL: fileURL)
        let loaded = await reader.recipes(for: ["second", "missing", "first"])

        XCTAssertEqual(loaded[0], second)
        XCTAssertNil(loaded[1])
        XCTAssertEqual(loaded[2], first)
    }

    private func makeRecipe(
        identifier: String,
        mode: StampRenderingMode,
        visibilityOverride: VideoStampVisibilityOverride? = nil
    ) -> VideoStampRecipe {
        VideoStampRecipe(
            assetLocalIdentifier: identifier,
            context: VideoPostProcessContext(
                stampEnabled: true,
                stampDate: Date(timeIntervalSince1970: 1_700_000_000),
                format: DateStampFormatter.compactDateTime,
                zeroPadded: false,
                timeStyle: .twentyFourHour,
                sizeKey: DateStampStyle.medium,
                position: .center,
                elements: [.date, .time],
                fadesOut: true,
                placeName: nil,
                timeZoneIdentifier: "Asia/Tokyo",
                storageMode: .standard
            ),
            renderingMode: mode,
            visibilityOverride: visibilityOverride
        )
    }
}
