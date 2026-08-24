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

    func testRecordingStateMapsProgressAndRemainingTime() {
        var capture = CaptureFeatureState()
        capture.engine.session = .ready
        capture.engine.isRecording = true
        capture.recordingProgress = 0.5
        capture.recordingRemaining = 1.25

        let state = CapturePresenter.makeState(capture: capture)

        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.recordingProgress, 0.5)
        XCTAssertEqual(state.statusText, "残り 1.2 秒")
        XCTAssertTrue(state.isShutterEnabled)
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
