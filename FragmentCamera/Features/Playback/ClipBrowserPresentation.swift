import Foundation
import CoreGraphics

struct ClipBrowserScreenState: Equatable {
    let itemID: String
    let dateText: String
    let timeText: String
    let positionText: String
    let dayProgress: Double
    let clipProgress: Double
    let clipDuration: TimeInterval
    let isPaused: Bool
    let swipeHintText: String
    let isLoading: Bool
    let didFailToLoad: Bool
    let isTransitioning: Bool
    let canRetreatClip: Bool
    let canAdvanceClip: Bool
    let canRetreatDay: Bool
    let canAdvanceDay: Bool
    let stampContext: VideoPostProcessContext?
    let textOverlays: [VlogResolvedTextOverlay]
    let videoAspectRatio: CGFloat
}

enum ClipBrowserSwipeAxis: Equatable {
    case horizontal
    case vertical
}

enum ClipBrowserNavigationIntent: Equatable {
    case advanceClip
    case retreatClip
    case advanceDay
    case retreatDay
}

enum ClipBrowserSwipePolicy {
    /// 意図しない斜め操作をページ送りとして扱わないための軸比率。
    private static let axisDominanceRatio: CGFloat = 1.25
    private static let activationDistance: CGFloat = 10
    private static let commitDistance: CGFloat = 64
    private static let minimumFlickDistance: CGFloat = 18
    private static let projectedCommitDistance: CGFloat = 108

    static func dominantAxis(for translation: CGSize) -> ClipBrowserSwipeAxis? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= activationDistance else { return nil }
        if horizontal >= vertical * axisDominanceRatio {
            return .horizontal
        }
        if vertical >= horizontal * axisDominanceRatio {
            return .vertical
        }
        return nil
    }

    static func intent(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> ClipBrowserNavigationIntent? {
        guard let axis = dominantAxis(for: translation) else { return nil }
        let travelled: CGFloat
        let projected: CGFloat
        switch axis {
        case .horizontal:
            travelled = translation.width
            projected = predictedEndTranslation.width
        case .vertical:
            travelled = translation.height
            projected = predictedEndTranslation.height
        }

        let committedByDistance = abs(travelled) >= commitDistance
        let committedByFlick = abs(travelled) >= minimumFlickDistance
            && abs(projected) >= projectedCommitDistance
            && travelled.sign == projected.sign
        guard committedByDistance || committedByFlick else { return nil }

        switch (axis, travelled < 0) {
        case (.horizontal, true): return .advanceClip
        case (.horizontal, false): return .retreatClip
        case (.vertical, true), (.vertical, false): return nil
        }
    }
}

enum ClipBrowserPresenter {
    static func makeState(
        day: LibraryClipPlaybackDay,
        item: PlaybackClipItem,
        clipIndex: Int,
        canRetreatClip: Bool,
        canAdvanceClip: Bool,
        canRetreatDay: Bool,
        canAdvanceDay: Bool,
        isLoading: Bool,
        didFailToLoad: Bool,
        isTransitioning: Bool = false,
        currentClipProgress: Double = 0,
        isPaused: Bool = false,
        stampContext: VideoPostProcessContext? = nil,
        textOverlays: [VlogResolvedTextOverlay] = [],
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> ClipBrowserScreenState {
        let elapsedBeforeCurrentClip = day.items
            .prefix(clipIndex)
            .reduce(0) { $0 + max($1.duration, 0) }
        let resolvedTotalDuration = max(
            day.totalDuration,
            day.items.reduce(0) { $0 + max($1.duration, 0) }
        )
        let boundedClipProgress = min(max(currentClipProgress, 0), 1)
        let elapsedDuration = elapsedBeforeCurrentClip
            + (max(item.duration, 0) * boundedClipProgress)
        let dayProgress = resolvedTotalDuration > 0
            ? min(max(elapsedDuration / resolvedTotalDuration, 0), 1)
            : 0

        return ClipBrowserScreenState(
            itemID: item.id,
            dateText: "\(day.displayDateText) \(day.weekdayText)",
            timeText: item.displayTimeText,
            positionText: "\(clipIndex + 1) / \(day.clipCount)",
            dayProgress: dayProgress,
            clipProgress: boundedClipProgress,
            clipDuration: max(item.duration, 0),
            isPaused: isPaused,
            swipeHintText: canRetreatClip || canAdvanceClip
                ? L10n.text("左右で同じ日の前後")
                : L10n.text("この日の動画はここまで"),
            isLoading: isLoading,
            didFailToLoad: didFailToLoad,
            isTransitioning: isTransitioning,
            canRetreatClip: canRetreatClip,
            canAdvanceClip: canAdvanceClip,
            canRetreatDay: canRetreatDay,
            canAdvanceDay: canAdvanceDay,
            stampContext: stampContext,
            textOverlays: textOverlays,
            videoAspectRatio: videoAspectRatio
        )
    }
}

enum ClipBrowserNavigator {
    static func resolvedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    static func resolvedClipIndex(_ clipIndex: Int, in day: LibraryClipPlaybackDay) -> Int {
        resolvedIndex(clipIndex, count: day.items.count)
    }

    static func closestClipIndex(
        to referenceDate: Date,
        in day: LibraryClipPlaybackDay,
        calendar: Calendar = .current
    ) -> Int {
        guard !day.items.isEmpty else { return 0 }
        let referenceSeconds = secondsSinceStartOfDay(referenceDate, calendar: calendar)
        let bestMatch = day.items.enumerated().min { lhs, rhs in
            let lhsDistance = abs(secondsSinceStartOfDay(lhs.element.capturedAt, calendar: calendar) - referenceSeconds)
            let rhsDistance = abs(secondsSinceStartOfDay(rhs.element.capturedAt, calendar: calendar) - referenceSeconds)
            return lhsDistance == rhsDistance ? lhs.offset < rhs.offset : lhsDistance < rhsDistance
        }
        return bestMatch?.offset ?? 0
    }

    private static func secondsSinceStartOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return ((components.hour ?? 0) * 3_600)
            + ((components.minute ?? 0) * 60)
            + (components.second ?? 0)
    }
}
