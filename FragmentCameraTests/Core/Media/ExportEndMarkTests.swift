import AVFoundation
import XCTest
@testable import FragmentCamera

final class ExportEndMarkTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1080, height: 1920)

    func testStartsOneAndAHalfSecondsBeforeTheEnd() {
        let mark = ExportEndMark(
            videoDuration: CMTime(seconds: 18, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: nil
        )

        XCTAssertEqual(mark.start.seconds, 16.5, accuracy: 0.001)
    }

    func testShortVideoShowsMarkFromTheStart() {
        let mark = ExportEndMark(
            videoDuration: CMTime(seconds: 1, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: nil
        )

        XCTAssertEqual(mark.start.seconds, 0, accuracy: 0.001)
    }

    func testMovesLeftOnlyWhenStampIsBottomRight() {
        XCTAssertTrue(ExportEndMark(
            videoDuration: CMTime(seconds: 10, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: .bottomTrailing
        ).placesOnLeft)
        XCTAssertFalse(ExportEndMark(
            videoDuration: CMTime(seconds: 10, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: .topTrailing
        ).placesOnLeft)
        XCTAssertFalse(ExportEndMark(
            videoDuration: CMTime(seconds: 10, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: .bottomLeading
        ).placesOnLeft)
    }

    func testLayerSitsInsideTheBottomRightCornerAndStartsHidden() {
        let mark = ExportEndMark(
            videoDuration: CMTime(seconds: 10, preferredTimescale: 600),
            contentFrame: frame,
            lastStampPosition: nil
        )
        let layer = DateStampLayerFactory.makeEndMarkLayer(mark)

        XCTAssertEqual(layer.opacity, 0)
        XCTAssertGreaterThan(layer.frame.minX, frame.midX)
        XCTAssertLessThan(layer.frame.maxX, frame.maxX)
        // Core Animation は左下原点なので、下端に近いほど y が小さい。
        XCTAssertLessThan(layer.frame.minY, frame.height * 0.1)
        XCTAssertNotNil(layer.animation(forKey: "vlogish-end-mark"))
    }
}
