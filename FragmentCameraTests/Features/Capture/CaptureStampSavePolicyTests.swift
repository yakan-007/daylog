import XCTest
@testable import FragmentCamera

final class CaptureStampSavePolicyTests: XCTestCase {
    func testOverlayModeNeverRendersOrCreatesPhotoKitEdit() {
        let decision = CaptureStampSavePolicy.decision(
            requestedMode: .playbackOverlay,
            stampEnabled: true,
            processedStampApplied: false
        )

        XCTAssertFalse(decision.shouldRenderDuringCapture)
        XCTAssertFalse(decision.shouldSaveAsPhotoKitEdit)
        XCTAssertEqual(decision.storedRenderingMode, .playbackOverlay)
    }

    func testSuccessfulCaptureBurnStaysBurned() {
        let decision = CaptureStampSavePolicy.decision(
            requestedMode: .burnOnCapture,
            stampEnabled: true,
            processedStampApplied: true
        )

        XCTAssertTrue(decision.shouldRenderDuringCapture)
        XCTAssertTrue(decision.shouldSaveAsPhotoKitEdit)
        XCTAssertEqual(decision.storedRenderingMode, .burnOnCapture)
    }

    func testFailedCaptureBurnFallsBackToPlaybackOverlay() {
        let decision = CaptureStampSavePolicy.decision(
            requestedMode: .burnOnCapture,
            stampEnabled: true,
            processedStampApplied: false
        )

        XCTAssertTrue(decision.shouldRenderDuringCapture)
        XCTAssertFalse(decision.shouldSaveAsPhotoKitEdit)
        XCTAssertEqual(decision.storedRenderingMode, .playbackOverlay)
    }
}
