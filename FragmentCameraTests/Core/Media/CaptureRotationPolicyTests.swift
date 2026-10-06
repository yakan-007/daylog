import XCTest
@testable import FragmentCamera

final class CaptureRotationPolicyTests: XCTestCase {
    func testPortraitKeepsNearestPortraitAngle() {
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 92, mode: .portrait),
            90
        )
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 268, mode: .portrait),
            270
        )
    }

    func testLandscapeHorizonSnapsToTheClosestPortraitAngle() {
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 10, mode: .portrait),
            90
        )
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: -90, mode: .portrait),
            270
        )
    }

    func testCaptureIsAlwaysPortrait() {
        XCTAssertEqual(CaptureOrientationMode.current, .portrait)
    }
}
