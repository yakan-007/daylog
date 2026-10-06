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

    // MARK: Worldwide date order

    func testDateOrderFollowsRegion() {
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "ja_JP")), .yearMonthDay)
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "zh_CN")), .yearMonthDay)
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "en_US")), .monthDayYear)
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "en_GB")), .dayMonthYear)
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "de_DE")), .dayMonthYear)
        XCTAssertEqual(DateStampDateOrder.regional(locale: Locale(identifier: "pt_BR")), .dayMonthYear)
    }

    func testStampDateUsesTheStoredOrderWithZeroPadding() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9, minute: 3)))

        func dateLine(_ order: DateStampDateOrder) -> String? {
            DateStampFormatter.lines(
                from: date,
                storedFormat: order.rawValue,
                zeroPadded: true,
                timeStyle: .twentyFourHour,
                elements: [.date],
                timeZone: timeZone
            ).first
        }

        XCTAssertEqual(dateLine(.yearMonthDay), "2026.07.05")
        XCTAssertEqual(dateLine(.monthDayYear), "07.05.2026")
        XCTAssertEqual(dateLine(.dayMonthYear), "05.07.2026")
        // 旧形式の保存値は、年・月・日として読む。
        XCTAssertEqual(DateStampFormatter.dateOrder(storedFormat: DateStampFormatter.compactDateTime), .yearMonthDay)
        XCTAssertEqual(DateStampFormatter.dateOrder(storedFormat: "garbage"), .yearMonthDay)
    }

    func testTimeStyleFollowsTheDevicesHourCycle() {
        XCTAssertEqual(DateStampTimeStyle.system(locale: Locale(identifier: "en_US")), .twelveHour)
        XCTAssertEqual(DateStampTimeStyle.system(locale: Locale(identifier: "de_DE")), .twentyFourHour)
        XCTAssertEqual(DateStampTimeStyle.system(locale: Locale(identifier: "ja_JP")), .twentyFourHour)
    }

    // MARK: Nine positions

    func testEveryPositionMapsToItsOwnSpotOnTheGrid() {
        XCTAssertEqual(DateStampPosition.allCases.count, 9)
        let spots = Set(DateStampPosition.allCases.map { $0.row * 3 + $0.column })
        XCTAssertEqual(spots.count, 9, "9か所が重ならない")
        XCTAssertEqual(DateStampPosition.top.blockPosition, .top)
        XCTAssertEqual(DateStampPosition.leading.blockPosition, .leading)
        XCTAssertEqual(DateStampPosition.bottomTrailing.blockPosition, .bottomTrailing)

        let renderSize = CGSize(width: 1_080, height: 1_920)
        let margin = DateStampStyle.margin(for: renderSize)
        let top = DateStampStyle.textFrame(for: renderSize, sizeKey: DateStampStyle.medium, position: .top, lineCount: 2, preferredWidth: 300)
        let leading = DateStampStyle.textFrame(for: renderSize, sizeKey: DateStampStyle.medium, position: .leading, lineCount: 2, preferredWidth: 300)
        let bottom = DateStampStyle.textFrame(for: renderSize, sizeKey: DateStampStyle.medium, position: .bottom, lineCount: 2, preferredWidth: 300)
        let trailing = DateStampStyle.textFrame(for: renderSize, sizeKey: DateStampStyle.medium, position: .trailing, lineCount: 2, preferredWidth: 300)

        XCTAssertEqual(top.midX, renderSize.width / 2, accuracy: 0.5)
        XCTAssertEqual(top.minY, margin, accuracy: 0.5)
        XCTAssertEqual(leading.minX, margin, accuracy: 0.5)
        XCTAssertEqual(leading.midY, renderSize.height / 2, accuracy: 0.5)
        XCTAssertEqual(bottom.maxY, renderSize.height - margin, accuracy: 0.5)
        XCTAssertEqual(trailing.maxX, renderSize.width - margin, accuracy: 0.5)
    }
}
