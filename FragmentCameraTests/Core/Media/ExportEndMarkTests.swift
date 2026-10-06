import AVFoundation
import XCTest
@testable import FragmentCamera

final class ExportEndMarkTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1080, height: 1920)

    private func mark(seconds: Double = 10) -> ExportEndMark {
        ExportEndMark(
            videoDuration: CMTime(seconds: seconds, preferredTimescale: 600),
            contentFrame: frame
        )
    }

    func testStartsOneAndAHalfSecondsBeforeTheEnd() {
        XCTAssertEqual(mark(seconds: 18).start.seconds, 16.5, accuracy: 0.001)
    }

    func testShortVideoShowsMarkFromTheStart() {
        XCTAssertEqual(mark(seconds: 1).start.seconds, 0, accuracy: 0.001)
    }

    func testOnlyCountsTextVisibleWhileTheMarkIsShown() {
        let endMark = mark(seconds: 10)

        XCTAssertTrue(endMark.overlapsInTime(start: 7, end: 10))
        XCTAssertFalse(endMark.overlapsInTime(start: 0, end: 8))
    }

    func testDefaultsToBottomRightAndStartsHidden() throws {
        let layer = try XCTUnwrap(DateStampLayerFactory.makeEndMarkLayer(mark()))

        XCTAssertEqual(layer.opacity, 0)
        XCTAssertGreaterThan(layer.frame.minX, frame.midX)
        XCTAssertLessThan(layer.frame.maxX, frame.maxX)
        // Core Animation は左下原点なので、下端に近いほど y が小さい。
        XCTAssertLessThan(layer.frame.minY, frame.height * 0.1)
        XCTAssertNotNil(layer.animation(forKey: "vlogish-end-mark"))
    }

    func testMovesLeftWhenBottomRightIsTaken() throws {
        let bottomRight = CGRect(x: frame.midX, y: 0, width: frame.width / 2, height: 300)
        let layer = try XCTUnwrap(
            DateStampLayerFactory.makeEndMarkLayer(mark(), avoiding: [bottomRight])
        )

        XCTAssertLessThan(layer.frame.maxX, frame.midX)
        XCTAssertLessThan(layer.frame.minY, frame.height * 0.1)
    }

    func testMovesToTopWhenTheBottomIsTaken() throws {
        let bottomBand = CGRect(x: 0, y: 0, width: frame.width, height: 300)
        let layer = try XCTUnwrap(
            DateStampLayerFactory.makeEndMarkLayer(mark(), avoiding: [bottomBand])
        )

        XCTAssertGreaterThan(layer.frame.minY, frame.height * 0.8)
    }

    func testSkipsTheMarkWhenEveryCornerIsTaken() {
        XCTAssertNil(DateStampLayerFactory.makeEndMarkLayer(mark(), avoiding: [frame]))
    }
}
