import XCTest
@testable import FragmentCamera

final class DateStampStyleTests: XCTestCase {
    func testPortraitVideoFrameExcludesSideBarsInLandscapeContainer() {
        let frame = DateStampStyle.aspectFitFrame(
            contentAspectRatio: 9.0 / 16.0,
            in: CGSize(width: 844, height: 390)
        )

        XCTAssertEqual(frame.height, 390, accuracy: 0.001)
        XCTAssertEqual(frame.width, 219.375, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 422, accuracy: 0.001)
    }

    func testLandscapeVideoFrameExcludesTopAndBottomBarsInPortraitContainer() {
        let frame = DateStampStyle.aspectFitFrame(
            contentAspectRatio: 16.0 / 9.0,
            in: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(frame.height, 219.375, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 422, accuracy: 0.001)
    }

    func testEveryStampPositionFitsInsideLandscapeVideoFrame() {
        let renderSize = CGSize(width: 1_920, height: 1_080)
        let frames = Dictionary(uniqueKeysWithValues: DateStampPosition.allCases.map { position in
            (
                position,
                DateStampStyle.textFrame(
                    for: renderSize,
                    sizeKey: DateStampStyle.medium,
                    position: position,
                    lineCount: 3
                )
            )
        })
        let videoBounds = CGRect(origin: .zero, size: renderSize)

        for position in DateStampPosition.allCases {
            let frame = try! XCTUnwrap(frames[position])
            XCTAssertTrue(
                videoBounds.contains(frame),
                "\(position.rawValue) is outside the landscape video frame: \(frame)"
            )
        }

        let margin = DateStampStyle.margin(for: renderSize)
        XCTAssertEqual(
            try! XCTUnwrap(frames[.topLeading]).minX,
            margin,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try! XCTUnwrap(frames[.topTrailing]).maxX,
            videoBounds.maxX - margin,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            try! XCTUnwrap(frames[.topLeading]).midY,
            try! XCTUnwrap(frames[.bottomLeading]).midY
        )
        XCTAssertEqual(
            try! XCTUnwrap(frames[.center]).midX,
            videoBounds.midX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try! XCTUnwrap(frames[.center]).midY,
            videoBounds.midY,
            accuracy: 0.001
        )
    }
}
