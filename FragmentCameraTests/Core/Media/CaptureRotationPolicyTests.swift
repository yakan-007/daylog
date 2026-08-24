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

    func testLandscapeKeepsNearestLandscapeAngle() {
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 2, mode: .landscape),
            0
        )
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 179, mode: .landscape),
            180
        )
    }

    func testModeChangeChoosesClosestAllowedQuarterTurn() {
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: 90, mode: .landscape),
            0
        )
        XCTAssertEqual(
            CaptureRotationPolicy.angle(closestTo: -90, mode: .portrait),
            270
        )
    }
}
