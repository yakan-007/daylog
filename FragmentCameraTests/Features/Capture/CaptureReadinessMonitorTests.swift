import XCTest
@testable import FragmentCamera

final class CaptureReadinessMonitorTests: XCTestCase {
    func testBecomesReadyAfterRequiredStableFrames() {
        let start = Date(timeIntervalSince1970: 1_000)
        let monitor = CaptureReadinessMonitor(
            policy: CaptureReadinessPolicy(
                minimumFrameCount: 3,
                minimumStableFrameCount: 2,
                timeout: 10,
                minimumFrameCountForTimeout: 2
            ),
            now: start
        )

        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start), .waiting)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: true, at: start), .waiting)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start), .waiting)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start), .ready)
    }

    func testTimesOutAfterEnoughFrames() {
        let start = Date(timeIntervalSince1970: 1_000)
        let monitor = CaptureReadinessMonitor(
            policy: CaptureReadinessPolicy(
                minimumFrameCount: 10,
                minimumStableFrameCount: 10,
                timeout: 1,
                minimumFrameCountForTimeout: 2
            ),
            now: start
        )

        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: true, at: start), .waiting)
        XCTAssertEqual(
            monitor.observeFrame(isDeviceAdjusting: true, at: start.addingTimeInterval(1)),
            .timedOut
        )
    }

    func testResetStartsAFreshWarmupWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        let monitor = CaptureReadinessMonitor(
            policy: CaptureReadinessPolicy(
                minimumFrameCount: 2,
                minimumStableFrameCount: 2,
                timeout: 10,
                minimumFrameCountForTimeout: 2
            ),
            now: start
        )

        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start), .waiting)
        monitor.reset(at: start.addingTimeInterval(1))
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start.addingTimeInterval(1)), .waiting)
    }

    func testDecisionIsReportedOnlyOnceUntilReset() {
        let start = Date(timeIntervalSince1970: 1_000)
        let monitor = CaptureReadinessMonitor(
            policy: CaptureReadinessPolicy(
                minimumFrameCount: 10,
                minimumStableFrameCount: 10,
                timeout: 1,
                minimumFrameCountForTimeout: 2
            ),
            now: start
        )

        _ = monitor.observeFrame(isDeviceAdjusting: true, at: start)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: true, at: start.addingTimeInterval(1)), .timedOut)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: true, at: start.addingTimeInterval(2)), .settled)
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: false, at: start.addingTimeInterval(3)), .settled)

        monitor.reset(at: start.addingTimeInterval(4))
        XCTAssertEqual(monitor.observeFrame(isDeviceAdjusting: true, at: start.addingTimeInterval(4)), .waiting)
    }
}
