import AVFoundation

struct AudioTrackInsertion: Equatable, Sendable {
    let sourceRange: CMTimeRange
    let destinationStart: CMTime
}

enum MediaTrackTiming {
    static func usableVideoRange(
        assetDuration: CMTime,
        trackRange: CMTimeRange
    ) -> CMTimeRange? {
        guard assetDuration.isNumeric, assetDuration > .zero,
              trackRange.isValid, !trackRange.isEmpty else {
            return nil
        }
        let assetRange = CMTimeRange(start: .zero, duration: assetDuration)
        let intersection = CMTimeRangeGetIntersection(
            assetRange,
            otherRange: trackRange
        )
        guard intersection.isValid, !intersection.isEmpty,
              intersection.duration.isNumeric,
              intersection.duration > .zero else {
            return nil
        }
        return intersection
    }

    static func audioInsertion(
        audioRange: CMTimeRange,
        videoRange: CMTimeRange,
        destinationCursor: CMTime
    ) -> AudioTrackInsertion? {
        guard audioRange.isValid, !audioRange.isEmpty,
              videoRange.isValid, !videoRange.isEmpty else {
            return nil
        }
        let intersection = CMTimeRangeGetIntersection(
            audioRange,
            otherRange: videoRange
        )
        guard intersection.isValid, !intersection.isEmpty,
              intersection.duration.isNumeric,
              intersection.duration > .zero else {
            return nil
        }
        let offsetFromVideoStart = CMTimeSubtract(
            intersection.start,
            videoRange.start
        )
        return AudioTrackInsertion(
            sourceRange: intersection,
            destinationStart: CMTimeAdd(destinationCursor, offsetFromVideoStart)
        )
    }
}
