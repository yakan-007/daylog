import XCTest
@testable import FragmentCamera

final class VlogClipEditTests: XCTestCase {
    func testCodableRoundTripPreservesTheBlock() throws {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(
                showsDate: true,
                showsTime: true,
                showsPlace: true,
                placeName: "近所のカフェ",
                caption: "夏休み\n最高 🎉",
                zeroPadded: true,
                timeStyle: .twelveHour,
                anchor: VlogNormalizedPoint(x: 0.2, y: 0.8),
                style: .band,
                scale: 1.4
            ),
            sourceTimeZoneIdentifier: "Asia/Tokyo",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder().encode(edit)
        let decoded = try JSONDecoder().decode(VlogClipEdit.self, from: data)

        XCTAssertEqual(decoded, edit)
    }

    func testNormalizationClampsPositionAndScaleWithoutChangingText() {
        let edit = VlogClipEdit(
            assetLocalIdentifier: "asset-1",
            block: VlogStampBlock(
                caption: "  keep spacing  ",
                anchor: VlogNormalizedPoint(x: -4, y: 8),
                scale: 9
            )
        )

        let block = edit.normalized(for: 5).block

        XCTAssertEqual(block.caption, "  keep spacing  ")
        XCTAssertEqual(block.anchor, VlogNormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(block.scale, VlogStampBlock.scaleRange.upperBound)
    }

    func testEmptinessIgnoresBlankCaptionAndPlace() {
        XCTAssertTrue(VlogStampBlock(showsPlace: true, placeName: "  ", caption: " \n ").isEmpty)
        XCTAssertFalse(VlogStampBlock(showsDate: true).isEmpty)
        XCTAssertFalse(VlogStampBlock(caption: "ひとこと").isEmpty)
        XCTAssertFalse(VlogStampBlock(showsPlace: true, placeName: "渋谷区").isEmpty)
    }

    func testAlignmentFollowsTheSideItIsPlacedOn() {
        XCTAssertEqual(VlogStampBlock(anchor: VlogNormalizedPoint(x: 0, y: 0)).alignment, .leading)
        XCTAssertEqual(VlogStampBlock(anchor: .center).alignment, .center)
        XCTAssertEqual(VlogStampBlock(anchor: VlogNormalizedPoint(x: 1, y: 1)).alignment, .trailing)
    }

    func testOlderSavedBlocksWithoutNewFieldsStillDecode() throws {
        let json = """
        {"showsDate":true,"showsTime":false,"showsPlace":false,"placeName":"","caption":"hi",
         "dateFormat":"y.M.d H:mm","zeroPadded":false,"timeStyle":"twentyFourHour",
         "anchor":{"x":0.5,"y":0.5},"style":"simple","scale":1}
        """
        let block = try JSONDecoder().decode(VlogStampBlock.self, from: Data(json.utf8))

        XCTAssertEqual(block.caption, "hi")
        XCTAssertEqual(block.captionPlacement, .below)
        XCTAssertFalse(block.fadesOut)
    }

    func testBlockPositionsCoverNineSpotsAndMatchOnlyExactAnchors() {
        XCTAssertEqual(VlogBlockPosition.allCases.count, 9)
        XCTAssertEqual(VlogBlockPosition.topLeading.anchor, VlogNormalizedPoint(x: 0, y: 0))
        XCTAssertEqual(VlogBlockPosition.top.anchor, VlogNormalizedPoint(x: 0.5, y: 0))
        XCTAssertEqual(VlogBlockPosition.trailing.anchor, VlogNormalizedPoint(x: 1, y: 0.5))
        XCTAssertEqual(VlogBlockPosition.bottomTrailing.anchor, VlogNormalizedPoint(x: 1, y: 1))

        for position in VlogBlockPosition.allCases {
            XCTAssertEqual(VlogBlockPosition.matching(position.anchor), position)
        }
        // 手で動かした位置は、どの9か所にも当たらない。
        XCTAssertNil(VlogBlockPosition.matching(VlogNormalizedPoint(x: 0.42, y: 0.31)))
    }

    func testBlockPositionAlignmentFollowsColumn() {
        var block = VlogStampBlock()
        block.anchor = VlogBlockPosition.leading.anchor
        XCTAssertEqual(block.alignment, .leading)
        block.anchor = VlogBlockPosition.bottom.anchor
        XCTAssertEqual(block.alignment, .center)
        block.anchor = VlogBlockPosition.topTrailing.anchor
        XCTAssertEqual(block.alignment, .trailing)
    }
}
