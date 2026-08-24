import XCTest
@testable import FragmentCamera

final class DayVideoExportPolicyTests: XCTestCase {
    func testWarnsBeforeChunkedBoundary() {
        let assessment = DayVideoExportPolicy.assess(
            clipCount: 60,
            totalDuration: 180
        )

        XCTAssertEqual(assessment.load, .elevated)
        XCTAssertTrue(assessment.requiresConfirmation)
        XCTAssertEqual(assessment.indicatorText, "60本・結合注意")
    }

    func testEightyClipsUseChunkedHeavyAssessment() {
        let assessment = DayVideoExportPolicy.assess(
            clipCount: 80,
            totalDuration: 240
        )

        XCTAssertEqual(assessment.load, .heavy)
        XCTAssertTrue(assessment.confirmationMessage.contains("分割処理"))
        XCTAssertEqual(DayVideoExportPolicy.chunkSize, 24)
        XCTAssertTrue(DayVideoExportPolicy.guidanceText.contains("上限はありません"))
    }

    func testNormalDaysDoNotInterruptExport() {
        let assessment = DayVideoExportPolicy.assess(
            clipCount: 59,
            totalDuration: 177
        )

        XCTAssertEqual(assessment.load, .standard)
        XCTAssertFalse(assessment.requiresConfirmation)
        XCTAssertNil(assessment.indicatorText)
    }

    func testOrdersOldestFirstAndUsesIdentifierAsStableTieBreak() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)

        let order = DayVideoExportPolicy.orderedIndices(
            creationDates: [later, earlier, earlier, nil],
            identifiers: ["later", "b", "a", "missing-date"]
        )

        XCTAssertEqual(order, [3, 2, 1, 0])
    }

    func testRejectsPartialResolvedAssetSet() {
        XCTAssertTrue(DayVideoExportPolicy.hasCompleteAssetSet(expected: 5, actual: 5))
        XCTAssertFalse(DayVideoExportPolicy.hasCompleteAssetSet(expected: 5, actual: 4))
        XCTAssertFalse(DayVideoExportPolicy.hasCompleteAssetSet(expected: 0, actual: 0))
    }

    func testChunkRangesCoverEveryClipExactlyOnce() {
        let ranges = DayVideoExportPolicy.chunkRanges(for: 100)

        XCTAssertEqual(ranges.count, 5)
        XCTAssertEqual(ranges.first, 0..<24)
        XCTAssertEqual(ranges.last, 96..<100)
        XCTAssertEqual(ranges.flatMap(Array.init), Array(0..<100))
    }

    func testHundredFiftyClipRangesLeaveSixInFinalChunk() {
        let ranges = DayVideoExportPolicy.chunkRanges(for: 150)

        XCTAssertEqual(ranges.count, 7)
        XCTAssertEqual(ranges.last, 144..<150)
    }

    func testMixedOrientationsUseDominantDurationInsteadOfSquareCanvas() {
        let size = DayVideoExportPolicy.preferredCanvasSourceSize(
            sizes: [
                CGSize(width: 1_080, height: 1_920),
                CGSize(width: 1_920, height: 1_080),
                CGSize(width: 1_080, height: 1_920)
            ],
            durations: [3, 2, 3]
        )

        XCTAssertEqual(size, CGSize(width: 1_080, height: 1_920))
    }

    func testMixedOrientationTieKeepsFirstClipDirection() {
        let size = DayVideoExportPolicy.preferredCanvasSourceSize(
            sizes: [
                CGSize(width: 1_920, height: 1_080),
                CGSize(width: 1_080, height: 1_920)
            ],
            durations: [3, 3]
        )

        XCTAssertEqual(size, CGSize(width: 1_920, height: 1_080))
    }
}
