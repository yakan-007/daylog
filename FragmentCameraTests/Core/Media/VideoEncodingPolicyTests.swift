import AVFoundation
import XCTest
@testable import FragmentCamera

final class VideoEncodingPolicyTests: XCTestCase {
    func testStandardModeKeepsSourceSize() {
        let policy = VideoEncodingPolicy(storageMode: .standard)
        let source = CGSize(width: 3840, height: 2160)

        XCTAssertEqual(policy.renderSize(for: source), source)
    }

    func testCompactModeLimitsLandscapeTo720p() {
        let policy = VideoEncodingPolicy(storageMode: .compact)

        XCTAssertEqual(
            policy.renderSize(for: CGSize(width: 3840, height: 2160)),
            CGSize(width: 1280, height: 720)
        )
    }

    func testCompactModeLimitsPortraitWithoutChangingAspectRatio() {
        let policy = VideoEncodingPolicy(storageMode: .compact)

        XCTAssertEqual(
            policy.renderSize(for: CGSize(width: 2160, height: 3840)),
            CGSize(width: 720, height: 1280)
        )
    }

    func testCompactModeDoesNotUpscaleSmallVideos() {
        let policy = VideoEncodingPolicy(storageMode: .compact)
        let source = CGSize(width: 640, height: 360)

        XCTAssertEqual(policy.renderSize(for: source), source)
    }

    func testCompactModePrefersHEVCThenH264CompatiblePreset() {
        let policy = VideoEncodingPolicy(storageMode: .compact)

        XCTAssertEqual(
            policy.exportPresets,
            [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720]
        )
    }
}
