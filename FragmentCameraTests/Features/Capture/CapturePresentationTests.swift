import XCTest
@testable import FragmentCamera

final class CapturePresentationTests: XCTestCase {
    func testReadyStateEnablesShutterWithoutStatusMessage() {
        var capture = CaptureFeatureState()
        capture.engine.session = .ready
        capture.selectedDuration = 4

        capture.isGridVisible = true
        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertTrue(state.isReadyToRecord)
        XCTAssertTrue(state.isShutterEnabled)
        XCTAssertTrue(state.isGridVisible)
        XCTAssertEqual(state.selectedDuration, 4)
        XCTAssertNil(state.statusText)
    }

    func testRecordingStateMapsProgressAndClock() {
        var capture = CaptureFeatureState()
        capture.engine.session = .ready
        capture.engine.isRecording = true
        capture.selectedDuration = 3
        capture.recordingProgress = 0.6
        capture.recordingRemaining = 1.2

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.recordingProgress, 0.6)
        // 経過は上部のREC表示に出すので、中央のステータスは空になる。
        XCTAssertNil(state.statusText)
        XCTAssertEqual(state.recordingClockText, "00:01.8 / 00:03")
        XCTAssertTrue(state.isShutterEnabled)
    }

    func testIdleStateHasNoRecordingClock() {
        var capture = CaptureFeatureState()
        capture.engine.session = .ready

        XCTAssertNil(CapturePresenter.makeState(capture: capture).recordingClockText)
    }

    func testRecordingClockClampsOutOfRangeValues() {
        XCTAssertEqual(CaptureRecordingClock.text(remaining: 5, duration: 5), "00:00.0 / 00:05")
        XCTAssertEqual(CaptureRecordingClock.text(remaining: -1, duration: 2), "00:02.0 / 00:02")
        XCTAssertEqual(CaptureRecordingClock.text(remaining: 9, duration: 1), "00:00.0 / 00:01")
        XCTAssertEqual(CaptureRecordingClock.text(remaining: .nan, duration: 3), "00:00.0 / 00:03")
    }

    func testTodayTimelineOnlyCountsClipsOnTheGivenDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6)))
        let sixAM = day.addingTimeInterval(6 * 3_600)
        let noon = day.addingTimeInterval(12 * 3_600)
        let yesterdayNight = day.addingTimeInterval(-1 * 3_600)
        let timeline = CaptureTodayTimeline(clipDates: [noon, yesterdayNight, sixAM])

        XCTAssertEqual(timeline.clipCount(on: noon, calendar: calendar), 2)
        XCTAssertEqual(timeline.clipFractions(on: noon, calendar: calendar), [0.25, 0.5])
        // 日付が変わった直後は、前日の記録を今日として数えない。
        let tomorrow = day.addingTimeInterval(24 * 3_600 + 60)
        XCTAssertEqual(timeline.clipCount(on: tomorrow, calendar: calendar), 0)
        XCTAssertEqual(CaptureTodayTimeline.nowFraction(day.addingTimeInterval(18 * 3_600), calendar: calendar), 0.75)
    }

    func testSavingStatePreventsStartingAnotherRecording() {
        var capture = CaptureFeatureState()
        capture.engine.session = .ready
        capture.engine.savePhase = .processing

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertFalse(state.isReadyToRecord)
        XCTAssertFalse(state.isShutterEnabled)
        XCTAssertEqual(state.statusText, "動画を保存中")
    }

    func testBlockedStateDisplaysPermissionGuidance() {
        var capture = CaptureFeatureState()
        capture.engine.session = .blocked
        capture.engine.permissionIssue = CameraPermissionIssue(
            title: "アクセスが必要です",
            message: "設定から許可してください"
        )

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertFalse(state.isReadyToRecord)
        XCTAssertFalse(state.isShutterEnabled)
        XCTAssertEqual(state.statusText, "権限を確認してください")
        XCTAssertEqual(state.permissionMessage, "設定から許可してください")
    }

    func testZoomButtonsOnlyContainSupportedFactors() {
        var capture = CaptureFeatureState()
        capture.zoomFactor = 2
        capture.zoomOptions = [
            CameraZoomOption(deviceFactor: 1, displayFactor: 0.5),
            CameraZoomOption(deviceFactor: 2, displayFactor: 1)
        ]

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertEqual(state.zoomOptions.map(\.title), ["0.5×", "1×"])
        XCTAssertEqual(state.zoomFactor, 2)
    }

    func testTripleCameraZoomPolicyUsesUserFacingFactors() {
        let options = CameraZoomPolicy.options(
            minimumDeviceFactor: 1,
            maximumDeviceFactor: 10,
            displayMultiplier: 0.5,
            nativeDeviceFactors: [1, 2, 4, 10]
        )

        XCTAssertEqual(options.map(\.displayFactor), [0.5, 1, 2, 5])
        XCTAssertEqual(options.map(\.deviceFactor), [1, 2, 4, 10])
        XCTAssertEqual(
            CameraZoomPolicy.defaultDeviceFactor(
                minimumDeviceFactor: 1,
                maximumDeviceFactor: 10,
                displayMultiplier: 0.5
            ),
            2
        )
    }

    func testSingleWideCameraOnlyShowsNativeQualityFactors() {
        let options = CameraZoomPolicy.options(
            minimumDeviceFactor: 1,
            maximumDeviceFactor: 10,
            displayMultiplier: 1,
            nativeDeviceFactors: [1, 2]
        )

        XCTAssertEqual(options.map(\.title), ["1×", "2×"])
    }

    func testExposureAndLockStateArePresented() {
        var capture = CaptureFeatureState()
        capture.exposureBias = 0.7
        capture.exposureBiasRange = -2...2
        capture.isFocusAndExposureLocked = true

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertEqual(state.exposureBias, 0.7)
        XCTAssertEqual(state.exposureBiasRange, -2...2)
        XCTAssertTrue(state.isFocusAndExposureLocked)
    }
}
