import XCTest
import Photos
@testable import FragmentCamera

final class ClipBrowserPresentationTests: XCTestCase {
    func testPresenterBuildsDisplayStateAndSwipeHints() {
        let item = makeItem(id: "clip-1", hour: 12, minute: 30)
        let day = makeDay(items: [item])

        let state = ClipBrowserPresenter.makeState(
            day: day,
            item: item,
            clipIndex: 0,
            canRetreatClip: false,
            canAdvanceClip: true,
            canRetreatDay: false,
            canAdvanceDay: true,
            isLoading: false,
            didFailToLoad: false
        )

        XCTAssertEqual(state.itemID, "clip-1")
        XCTAssertEqual(state.dateText, "7月15日 火")
        XCTAssertEqual(state.positionText, "1 / 1")
        XCTAssertEqual(state.dayProgress, 0)
        XCTAssertEqual(state.swipeHintText, "左右で同じ日の前後")
        XCTAssertFalse(state.canRetreatClip)
        XCTAssertTrue(state.canAdvanceClip)
        XCTAssertFalse(state.canRetreatDay)
        XCTAssertTrue(state.canAdvanceDay)
    }

    func testPresenterBuildsDurationWeightedDayProgress() {
        let items = [
            makeItem(id: "clip-1", hour: 12, minute: 30),
            makeItem(id: "clip-2", hour: 12, minute: 31),
            makeItem(id: "clip-3", hour: 12, minute: 32)
        ]
        let state = ClipBrowserPresenter.makeState(
            day: makeDay(items: items),
            item: items[1],
            clipIndex: 1,
            canRetreatClip: true,
            canAdvanceClip: true,
            canRetreatDay: false,
            canAdvanceDay: false,
            isLoading: false,
            didFailToLoad: false,
            currentClipProgress: 0.5
        )

        XCTAssertEqual(state.dayProgress, 0.5, accuracy: 0.0001)
    }

    func testSwipePolicyRequiresCommittedMovementOnOneClearAxis() {
        XCTAssertNil(ClipBrowserSwipePolicy.intent(
            translation: CGSize(width: 42, height: 3),
            predictedEndTranslation: CGSize(width: 55, height: 3)
        ))
        XCTAssertNil(ClipBrowserSwipePolicy.intent(
            translation: CGSize(width: 76, height: 68),
            predictedEndTranslation: CGSize(width: 150, height: 140)
        ))
        XCTAssertEqual(
            ClipBrowserSwipePolicy.intent(
                translation: CGSize(width: -72, height: 5),
                predictedEndTranslation: CGSize(width: -80, height: 6)
            ),
            .advanceClip
        )
        XCTAssertNil(ClipBrowserSwipePolicy.intent(
            translation: CGSize(width: 4, height: 70),
            predictedEndTranslation: CGSize(width: 5, height: 82)
        ))
    }

    func testSwipePolicyAllowsAnIntentionalFlickButRejectsPredictionReversal() {
        XCTAssertEqual(
            ClipBrowserSwipePolicy.intent(
                translation: CGSize(width: 25, height: 2),
                predictedEndTranslation: CGSize(width: 130, height: 3)
            ),
            .retreatClip
        )
        XCTAssertNil(ClipBrowserSwipePolicy.intent(
            translation: CGSize(width: 25, height: 2),
            predictedEndTranslation: CGSize(width: -130, height: 3)
        ))
    }

    func testResolvedIndexClampsToAvailableRange() {
        XCTAssertEqual(ClipBrowserNavigator.resolvedIndex(-2, count: 3), 0)
        XCTAssertEqual(ClipBrowserNavigator.resolvedIndex(8, count: 3), 2)
        XCTAssertEqual(ClipBrowserNavigator.resolvedIndex(1, count: 3), 1)
    }

    func testClosestClipUsesTimeOfDayAndEarlierIndexWinsTie() {
        let calendar = utcCalendar
        let items = [
            makeItem(id: "morning", hour: 9, minute: 0),
            makeItem(id: "noon", hour: 12, minute: 0),
            makeItem(id: "evening", hour: 18, minute: 0)
        ]
        let reference = makeDate(hour: 15, minute: 0)

        XCTAssertEqual(
            ClipBrowserNavigator.closestClipIndex(
                to: reference,
                in: makeDay(items: items),
                calendar: calendar
            ),
            1
        )
    }

    func testPlaybackDayAlwaysOrdersClipsOldestFirst() {
        let day = makeDay(items: [
            makeItem(id: "evening", hour: 18, minute: 0),
            makeItem(id: "morning", hour: 8, minute: 0),
            makeItem(id: "noon", hour: 12, minute: 0)
        ])

        XCTAssertEqual(
            day.items.map(\.assetLocalIdentifier),
            ["morning", "noon", "evening"]
        )
    }

    @MainActor
    func testPlaybackRestartsWhenScreenReappears() {
        let item = makeItem(id: "missing-clip", hour: 12, minute: 30)
        let context = LibraryClipPlaybackContext(
            days: [makeDay(items: [item])],
            initialDayIndex: 0,
            initialClipIndex: 0
        )
        let viewModel = LibraryClipBrowserViewModel(
            context: context,
            repository: MissingPlaybackAssetRepository()
        )

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.didFailToLoad)

        viewModel.startPlayback()
        XCTAssertTrue(viewModel.didFailToLoad)

        viewModel.stopPlayback()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.didFailToLoad)

        viewModel.startPlayback()
        XCTAssertTrue(viewModel.didFailToLoad)
    }

    @MainActor
    func testNavigationTransitionSerializesInputAndRecoversAfterLoadFailure() async {
        let items = [
            makeItem(id: "missing-1", hour: 12, minute: 30),
            makeItem(id: "missing-2", hour: 12, minute: 31),
            makeItem(id: "missing-3", hour: 12, minute: 32)
        ]
        let viewModel = LibraryClipBrowserViewModel(
            context: LibraryClipPlaybackContext(
                days: [makeDay(items: items)],
                initialDayIndex: 0,
                initialClipIndex: 0
            ),
            repository: MissingPlaybackAssetRepository()
        )
        viewModel.startPlayback()

        viewModel.advanceClip()
        viewModel.advanceClip()
        XCTAssertTrue(viewModel.isTransitioning)

        try? await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(viewModel.currentClipIndex, 1)
        XCTAssertFalse(viewModel.isTransitioning)
        XCTAssertTrue(viewModel.didFailToLoad)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: hour,
            minute: minute
        ))!
    }

    private func makeItem(id: String, hour: Int, minute: Int) -> PlaybackClipItem {
        PlaybackClipItem(
            assetLocalIdentifier: id,
            capturedAt: makeDate(hour: hour, minute: minute),
            dayKey: "2026-07-15",
            duration: 3,
            displayDateText: "7月15日",
            displayTimeText: String(format: "%02d:%02d", hour, minute)
        )
    }

    private func makeDay(items: [PlaybackClipItem]) -> LibraryClipPlaybackDay {
        LibraryClipPlaybackDay(
            dayKey: "2026-07-15",
            displayDateText: "7月15日",
            weekdayText: "火",
            totalDuration: items.reduce(0) { $0 + $1.duration },
            clipCount: items.count,
            items: items
        )
    }
}

@MainActor
private final class MissingPlaybackAssetRepository: PlaybackAssetRepository {
    func asset(localIdentifier: String) -> PHAsset? { nil }
}
