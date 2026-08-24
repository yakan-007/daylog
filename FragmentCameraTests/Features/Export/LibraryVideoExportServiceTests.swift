import XCTest
@testable import FragmentCamera

final class LibraryVideoExportServiceTests: XCTestCase {
    func testDayAndClipTargetsExposeOnlyTheirOwnPresentationIdentifier() {
        let day = LibraryExportTarget.day(id: "section", dayKey: "2026-08-14")
        let clip = LibraryExportTarget.clip(id: "clip")

        XCTAssertEqual(day.exportingDayKey, "2026-08-14")
        XCTAssertNil(day.exportingClipID)
        XCTAssertNil(clip.exportingDayKey)
        XCTAssertEqual(clip.exportingClipID, "clip")
    }

    func testStampResolutionUsesOnlyThePreparationProgressRange() {
        let halfway = LibraryExportProgressMapper.resolvingStamps(
            completed: 2,
            total: 4
        )
        let finished = LibraryExportProgressMapper.resolvingStamps(
            completed: 4,
            total: 4
        )

        XCTAssertEqual(halfway.fraction, 0.05, accuracy: 0.0001)
        XCTAssertEqual(finished.fraction, 0.1, accuracy: 0.0001)
        XCTAssertEqual(halfway.phase, .resolvingStamps(current: 2, total: 4))
    }

    func testMediaProgressContinuesAfterPreparationAndKeepsItsPhase() {
        let source = DayVideoExportProgress(fraction: 0.5, phase: .merging)
        let mapped = LibraryExportProgressMapper.exporting(source)
        let finished = LibraryExportProgressMapper.exporting(
            DayVideoExportProgress(fraction: 1, phase: .completed)
        )

        XCTAssertEqual(mapped.fraction, 0.55, accuracy: 0.0001)
        XCTAssertEqual(mapped.phase, .merging)
        XCTAssertEqual(finished.fraction, 1, accuracy: 0.0001)
    }
}
