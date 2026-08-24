import XCTest
@testable import FragmentCamera

final class DateStampFormatterTests: XCTestCase {
    func testTwelveHourStyleShowsDateTimeAndPlaceOnSeparateLines() throws {
        let date = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 11, hour: 6, minute: 39)
            )
        )

        XCTAssertEqual(
            DateStampFormatter.lines(
                from: date,
                storedFormat: DateStampFormatter.compactDateTime,
                zeroPadded: false,
                timeStyle: .twelveHour,
                elements: [.date, .time, .place],
                placeName: "渋谷区"
            ),
            ["2026.8.11", "6:39 AM", "渋谷区"]
        )
    }

    func testTwentyFourHourStyleShowsDateAndTimeOnSeparateLines() throws {
        let date = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 11, hour: 18, minute: 5)
            )
        )

        XCTAssertEqual(
            DateStampFormatter.lines(
                from: date,
                storedFormat: DateStampFormatter.compactDateTime,
                zeroPadded: true,
                timeStyle: .twentyFourHour,
                elements: [.date, .time]
            ),
            ["2026.08.11", "18:05"]
        )
    }

    func testTimeStyleDoesNotDependOnStampPosition() throws {
        let date = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 11, hour: 18, minute: 5)
            )
        )

        let twelveHour = DateStampFormatter.lines(
            from: date,
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twelveHour,
            elements: [.time]
        )
        let twentyFourHour = DateStampFormatter.lines(
            from: date,
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twentyFourHour,
            elements: [.time]
        )

        XCTAssertEqual(twelveHour, ["6:05 PM"])
        XCTAssertEqual(twentyFourHour, ["18:05"])
    }

    func testOnlySelectedElementsAreRendered() {
        let lines = DateStampFormatter.lines(
            from: Date(timeIntervalSince1970: 0),
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twentyFourHour,
            elements: [.place],
            placeName: "東京"
        )

        XCTAssertEqual(lines, ["東京"])
    }

    func testUnavailablePlaceFallsBackToTimeInsteadOfBlankStamp() {
        let lines = DateStampFormatter.lines(
            from: Date(timeIntervalSince1970: 1_767_225_600),
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twelveHour,
            elements: [.place],
            placeName: nil,
            timeZone: TimeZone(identifier: "Asia/Tokyo")
        )

        XCTAssertEqual(lines, ["9:00 AM"])
    }

    func testUnknownPositionFallsBackToTopTrailing() {
        XCTAssertEqual(DateStampPosition.normalized("unknown"), .topTrailing)
    }

    func testStoredCaptureTimeZoneKeepsOriginalClockTime() {
        let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
        let tokyo = DateStampFormatter.lines(
            from: date,
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twelveHour,
            elements: [.time],
            timeZone: TimeZone(identifier: "Asia/Tokyo")
        )
        let losAngeles = DateStampFormatter.lines(
            from: date,
            storedFormat: DateStampFormatter.compactDateTime,
            zeroPadded: false,
            timeStyle: .twelveHour,
            elements: [.time],
            timeZone: TimeZone(identifier: "America/Los_Angeles")
        )

        XCTAssertEqual(tokyo, ["9:00 AM"])
        XCTAssertEqual(losAngeles, ["4:00 PM"])
    }

    func testCenterFrameUsesVideoCenterForMultipleLines() {
        let renderSize = CGSize(width: 1_080, height: 1_920)
        let frame = DateStampStyle.textFrame(
            for: renderSize,
            sizeKey: DateStampStyle.medium,
            position: .center,
            lineCount: 3
        )

        XCTAssertEqual(frame.midY, renderSize.height / 2, accuracy: 0.001)
    }

    func testBottomFrameStaysInsideSafeMargin() {
        let renderSize = CGSize(width: 1_080, height: 1_920)
        let frame = DateStampStyle.textFrame(
            for: renderSize,
            sizeKey: DateStampStyle.medium,
            position: .bottomTrailing,
            lineCount: 2
        )

        XCTAssertLessThan(frame.maxY, renderSize.height)
        XCTAssertGreaterThan(frame.minX, 0)
    }
}
