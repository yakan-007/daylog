import XCTest
@testable import FragmentCamera

final class CameraRollPresentationTests: XCTestCase {
    func testEmptyAndLoadingStatesAreMutuallyExclusive() {
        let empty = CameraRollPresenter.makeState(
            sections: [],
            isRefreshing: false,
            exportingDayKey: nil
        )
        let loading = CameraRollPresenter.makeState(
            sections: [],
            isRefreshing: true,
            exportingDayKey: nil
        )

        XCTAssertTrue(empty.showsEmptyState)
        XCTAssertFalse(empty.showsInitialLoading)
        XCTAssertFalse(loading.showsEmptyState)
        XCTAssertTrue(loading.showsInitialLoading)
    }

    func testPresenterBuildsDisplayOnlyDayAndClipItems() {
        let capturedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let clips = (0..<3).map { index in
            ClipSummary(
                assetLocalIdentifier: "clip-\(index)",
                capturedAt: capturedAt.addingTimeInterval(TimeInterval(index)),
                dayKey: "2024-07-03",
                duration: TimeInterval(index + 1)
            )
        }
        let section = DaySection(
            dayKey: "2024-07-03",
            date: capturedAt,
            clipCount: clips.count,
            totalDuration: 6,
            clips: clips
        )

        let state = CameraRollPresenter.makeState(
            sections: [section],
            isRefreshing: false,
            exportingDayKey: section.dayKey
        )

        XCTAssertEqual(state.days.count, 1)
        XCTAssertEqual(state.days[0].id, section.id)
        XCTAssertEqual(state.days[0].date, section.date)
        XCTAssertEqual(state.days[0].totalDuration, 6)
        XCTAssertEqual(state.days[0].summaryText, "3本")
        XCTAssertEqual(state.days[0].durationText, "0:06")
        XCTAssertEqual(state.days[0].exportAssessment.load, .standard)
        XCTAssertTrue(state.days[0].isExporting)
        XCTAssertFalse(state.days[0].canExport)
        XCTAssertEqual(state.days[0].clips.map(\.id), clips.map(\.assetLocalIdentifier))
    }

    func testSingleClipUsesSingularSummary() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let clip = ClipSummary(
            assetLocalIdentifier: "single",
            capturedAt: date,
            dayKey: "2024-07-03",
            duration: 3
        )
        let section = DaySection(
            dayKey: "2024-07-03",
            date: date,
            clipCount: 1,
            totalDuration: 3,
            clips: [clip]
        )

        let state = CameraRollPresenter.makeState(
            sections: [section],
            isRefreshing: false,
            exportingDayKey: nil
        )

        XCTAssertEqual(state.days[0].summaryText, "1本")
        XCTAssertTrue(state.days[0].canExport)
    }

    func testPresenterBuildsCompleteCalendarAndChronologicalClipOrder() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let later = ClipSummary(
            assetLocalIdentifier: "later",
            capturedAt: date.addingTimeInterval(60),
            dayKey: "2024-07-03",
            duration: 4
        )
        let earlier = ClipSummary(
            assetLocalIdentifier: "earlier",
            capturedAt: date,
            dayKey: "2024-07-03",
            duration: 3
        )
        let section = DaySection(
            dayKey: "2024-07-03",
            date: date,
            clipCount: 2,
            totalDuration: 7,
            clips: [later, earlier]
        )
        let summary = DayCalendarSummary(
            dayKey: section.dayKey,
            date: date,
            clipCount: 2,
            totalDuration: 7,
            previewAssetIdentifier: earlier.assetLocalIdentifier
        )

        let state = CameraRollPresenter.makeState(
            sections: [section],
            calendarSummaries: [summary],
            isRefreshing: false,
            exportingDayKey: nil
        )

        XCTAssertEqual(state.days[0].clips.map(\.id), ["earlier", "later"])
        XCTAssertEqual(state.calendarDays.map(\.id), [section.id])
        XCTAssertEqual(state.calendarDays[0].clipCount, 2)
        XCTAssertEqual(state.calendarDays[0].totalDuration, 7)
        XCTAssertEqual(state.calendarDays[0].previewAssetIdentifier, "earlier")
    }

    func testCalendarPresenterBuildsPaddedMonthAndSummary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1
        )))
        let recordedDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 23
        )))
        let day = CameraRollCalendarDayItem(
            id: "2026-08-23",
            date: recordedDate,
            clipCount: 4,
            totalDuration: 14,
            durationText: "0:14",
            previewAssetIdentifier: "preview"
        )

        let presentation = CameraRollCalendarPresenter.makeMonth(
            containing: month,
            days: [day],
            calendar: calendar
        )

        XCTAssertEqual(presentation.cells.count, 42)
        XCTAssertEqual(presentation.cells.prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(presentation.recordedDayCount, 1)
        XCTAssertEqual(presentation.clipCount, 4)
        XCTAssertEqual(presentation.totalDuration, 14)
        XCTAssertEqual(
            presentation.recordedDay(on: recordedDate, calendar: calendar)?.id,
            day.id
        )
    }

    func testCalendarPresenterMovesByWholeMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let january = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 15
        )))

        let february = try XCTUnwrap(CameraRollCalendarPresenter.month(
            offsetBy: 1,
            from: january,
            calendar: calendar
        ))
        let components = calendar.dateComponents([.year, .month, .day], from: february)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 1)
    }

    func testClipExportStateDisablesOtherExports() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let clips = (0..<2).map { index in
            ClipSummary(
                assetLocalIdentifier: "clip-\(index)",
                capturedAt: date.addingTimeInterval(TimeInterval(index)),
                dayKey: "2024-07-03",
                duration: 3
            )
        }
        let section = DaySection(
            dayKey: "2024-07-03",
            date: date,
            clipCount: clips.count,
            totalDuration: 6,
            clips: clips
        )

        let state = CameraRollPresenter.makeState(
            sections: [section],
            isRefreshing: false,
            exportingDayKey: nil,
            exportingClipID: "clip-1",
            exportProgress: DayVideoExportProgress(
                fraction: 0.4,
                phase: .exportingClip
            )
        )

        XCTAssertFalse(state.days[0].canExport)
        XCTAssertFalse(state.days[0].clips[0].canExport)
        XCTAssertTrue(state.days[0].clips[1].isExporting)
        XCTAssertEqual(state.days[0].clips[1].exportProgress, 0.4)
        XCTAssertEqual(state.exportProgress?.phase, .exportingClip)
    }

    func testChunkedExportStatusIsExposedForPersistentProgressPanel() {
        let progress = DayVideoExportProgress(
            fraction: 0.32,
            phase: .processingChunk(current: 2, total: 5)
        )

        let state = CameraRollPresenter.makeState(
            sections: [],
            isRefreshing: false,
            exportingDayKey: "2026-08-13",
            exportProgress: progress
        )

        XCTAssertEqual(state.exportProgress, progress)
        XCTAssertEqual(progress.percentage, 32)
        XCTAssertEqual(progress.phase.title, "分割動画を作成中（2/5）")
    }

    func testAssetLookupStatusMakesPreExportWorkVisible() {
        let progress = DayVideoExportProgress(
            fraction: 0,
            phase: .locatingAssets(total: 87)
        )

        XCTAssertEqual(progress.percentage, 0)
        XCTAssertEqual(progress.phase.title, "87本の動画を確認中")
        XCTAssertTrue(progress.phase.detail.contains("まとめて読み込んでいます"))
    }

    func testStampResolutionStatusShowsActualPreparationProgress() {
        let progress = DayVideoExportProgress(
            fraction: 0.05,
            phase: .resolvingStamps(current: 44, total: 87)
        )

        XCTAssertEqual(progress.percentage, 5)
        XCTAssertEqual(progress.phase.title, "スタンプを確認中（44/87）")
        XCTAssertTrue(progress.phase.detail.contains("地名"))
    }

    func testYearMonthFormattersUseJapanese() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 1
        )))

        XCTAssertEqual(VlogishFormatters.monthTitleFormatter.string(from: date), "8月")
        XCTAssertEqual(VlogishFormatters.yearTitleFormatter.string(from: date), "2026年")
        XCTAssertEqual(VlogishFormatters.yearMonthTitleFormatter.string(from: date), "2026年8月")
    }
}
