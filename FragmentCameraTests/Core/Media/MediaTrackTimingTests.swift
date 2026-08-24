import AVFoundation
import XCTest
@testable import FragmentCamera

final class MediaTrackTimingTests: XCTestCase {
    func testUsableVideoRangeIntersectsAssetAndTrackTimelines() {
        let result = MediaTrackTiming.usableVideoRange(
            assetDuration: time(3),
            trackRange: CMTimeRange(start: time(0.1), duration: time(2.8))
        )

        XCTAssertEqual(result?.start, time(0.1))
        XCTAssertEqual(result?.duration, time(2.8))
    }

    func testShorterAudioIsInsertedWithoutRequestingMissingTail() {
        let insertion = MediaTrackTiming.audioInsertion(
            audioRange: CMTimeRange(start: time(0.2), duration: time(2.5)),
            videoRange: CMTimeRange(start: time(0.1), duration: time(2.8)),
            destinationCursor: time(5)
        )

        XCTAssertEqual(insertion?.sourceRange.start, time(0.2))
        XCTAssertEqual(insertion?.sourceRange.duration, time(2.5))
        XCTAssertEqual(insertion?.destinationStart, time(5.1))
    }

    func testAudioOutsideVideoRangeIsIgnored() {
        let insertion = MediaTrackTiming.audioInsertion(
            audioRange: CMTimeRange(start: time(4), duration: time(1)),
            videoRange: CMTimeRange(start: .zero, duration: time(3)),
            destinationCursor: .zero
        )

        XCTAssertNil(insertion)
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
