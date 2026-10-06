import XCTest
@testable import FragmentCamera

final class ExportPresentationTests: XCTestCase {
    func testInternalPhasesCollapseIntoThreeVisibleStages() {
        XCTAssertEqual(DayVideoExportPhase.locatingAssets(total: 3).stage, .preparing)
        XCTAssertEqual(DayVideoExportPhase.preparing.stage, .preparing)
        XCTAssertEqual(DayVideoExportPhase.resolvingStamps(current: 1, total: 3).stage, .preparing)
        XCTAssertEqual(DayVideoExportPhase.exportingClip.stage, .joining)
        XCTAssertEqual(DayVideoExportPhase.merging.stage, .joining)
        XCTAssertEqual(DayVideoExportPhase.processingChunk(current: 2, total: 4).stage, .joining)
        XCTAssertEqual(DayVideoExportPhase.combiningChunks.stage, .joining)
        XCTAssertEqual(DayVideoExportPhase.finalizing.stage, .finishing)
        XCTAssertEqual(DayVideoExportPhase.completed.stage, .finishing)
        XCTAssertEqual(DayVideoExportStage.allCases.count, 3)
    }

    func testStripKeepsEveryClipWhenFewAndSamplesEvenlyWhenMany() {
        let few = (0..<6).map { "c\($0)" }
        XCTAssertEqual(CameraRollExportSubject.sampled(few, limit: 10), few)

        let many = (0..<100).map { "c\($0)" }
        let sampled = CameraRollExportSubject.sampled(many, limit: 10)
        XCTAssertEqual(sampled.count, 10)
        XCTAssertEqual(sampled.first, "c0", "最初のクリップから始まる")
        XCTAssertEqual(sampled.last, "c99", "最後のクリップで終わる")
        XCTAssertEqual(Set(sampled).count, 10, "同じクリップを重ねない")

        let subject = CameraRollExportSubject(
            origin: .day(id: "2026-10-06"),
            title: "10.06 TUE",
            clipCount: 100,
            durationText: "05:00",
            clipIDs: many
        )
        XCTAssertEqual(subject.previewClipIDs.count, CameraRollExportSubject.maximumPreviewCount)
        XCTAssertEqual(subject.clipCount, 100)
    }
}
