import XCTest
@testable import FragmentCamera

final class CameraRollTimelinePresenterTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func clip(_ id: String, hour: Int) -> CameraRollClipItem {
        CameraRollClipItem(
            id: id,
            timeText: String(format: "%02d:00", hour),
            durationText: "0:03",
            isExporting: false,
            exportProgress: nil,
            canExport: true,
            dayFraction: Double(hour) / 24,
            hour: hour
        )
    }

    // MARK: Timeline

    func testEmptyHoursBetweenClipsBecomeOneGapRow() {
        let rows = CameraRollTimelinePresenter.rows(for: [
            clip("a", hour: 7),
            clip("b", hour: 12),
            clip("c", hour: 12),
            clip("d", hour: 14)
        ])

        XCTAssertEqual(rows.map(\.id), ["a", "gap-8-11", "b", "c", "gap-13-13", "d"])
        guard case .clip(_, let secondHourLabel) = rows[3] else {
            return XCTFail("同じ時間の2本目はクリップ行のはず")
        }
        XCTAssertNil(secondHourLabel, "同じ時間の2本目には時刻ラベルを出さない")
    }

    func testTodayEndsWithNowRowAfterTrailingGap() throws {
        let now = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 21, minute: 12)))

        let rows = CameraRollTimelinePresenter.rows(
            for: [clip("a", hour: 18)],
            now: now,
            calendar: utc
        )

        XCTAssertEqual(rows.map(\.id), ["a", "gap-19-20", "now"])
    }

    func testNowRowIsSkippedWhenTheClockIsBehindTheLastClip() throws {
        let now = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9)))

        let rows = CameraRollTimelinePresenter.rows(for: [clip("a", hour: 18)], now: now, calendar: utc)

        XCTAssertEqual(rows.map(\.id), ["a"])
    }

    // MARK: Time axis

    func testTimeAxisClampsToTheDay() {
        XCTAssertEqual(CameraRollTimeAxis.fraction(forDayOffset: -10), 0)
        XCTAssertEqual(CameraRollTimeAxis.fraction(forDayOffset: 43_200), 0.5)
        XCTAssertEqual(CameraRollTimeAxis.fraction(forDayOffset: 90_000), 1)
        XCTAssertEqual(CameraRollTimeAxis.hour(forDayOffset: 86_399), 23)
        XCTAssertEqual(CameraRollTimeAxis.fraction(forDayOffset: .nan), 0)
    }

    // MARK: Feed
    // 日付スタンプの表記は端末のタイムゾーンで描くため、フィードは端末のカレンダーで組み立てる。

    private func day(year: Int = 2026, month: Int = 10, _ day: Int) throws -> CameraRollDayItem {
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
        let section = DaySection(
            dayKey: dayKey,
            date: calendar.startOfDay(for: date),
            clipCount: 1,
            totalDuration: 3,
            clips: [ClipSummary(assetLocalIdentifier: dayKey, capturedAt: date, dayKey: dayKey, duration: 3)]
        )
        return CameraRollPresenter.makeDayItem(section: section, exportingDayKey: nil, calendar: calendar)
    }

    func testFeedInsertsCollapsedNoRecordRows() throws {
        let days = [try day(4), try day(3), try day(month: 9, 30)]

        let entries = CameraRollFeedPresenter.entries(for: days, calendar: .current)

        XCTAssertEqual(entries.map(\.id), ["2026-10-04", "2026-10-03", "gap-2026-10-03", "2026-09-30"])
        guard case .noRecord(_, let label) = entries[2] else {
            return XCTFail("記録なしの行のはず")
        }
        XCTAssertEqual(label, "10.02–10.01")
    }

    func testConsecutiveDaysHaveNoGapRow() throws {
        let entries = CameraRollFeedPresenter.entries(for: [try day(4), try day(3)], calendar: .current)
        XCTAssertEqual(entries.map(\.id), ["2026-10-04", "2026-10-03"])
    }

    func testFeedAddsLeadingGapBetweenTodayAndTheLatestRecording() throws {
        let latest = try day(2)
        let today = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9)))

        let entries = CameraRollFeedPresenter.entries(for: [latest], leadingFrom: today, calendar: .current)

        XCTAssertEqual(entries.map(\.id), ["gap-leading", "2026-10-02"])
        guard case .noRecord(_, let label) = entries[0] else {
            return XCTFail("記録なしの行のはず")
        }
        XCTAssertEqual(label, "10.04–10.03")
    }

    func testDayStampUsesFixedEnglishFormat() throws {
        let item = try day(4)
        XCTAssertEqual(item.stampDateText, "10.04")
        XCTAssertEqual(item.stampWeekdayText, "SUN")
    }
}
