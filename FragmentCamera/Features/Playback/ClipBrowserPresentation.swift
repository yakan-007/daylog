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
    /// 画面左上のスタンプ表記。例: "10.06 TUE" / "18:39" / "渋谷区"
    var stampDateText: String = ""
    var stampTimeText: String = ""
    var placeText: String? = nil
    /// 下のバー用。その日のクリップの長さ（古い順）と、いま再生中の位置。
    var segmentDurations: [TimeInterval] = []
    var currentClipIndex: Int = 0
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

    /// 送れない方向へ引いた時の抵抗。引くほど重くなり、`dimension` を超えない。
    static func rubberBand(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0, offset.isFinite else { return 0 }
        let distance = abs(offset)
        let resisted = (1 - 1 / (distance * 0.55 / dimension + 1)) * dimension
        return offset < 0 ? -resisted : resisted
    }

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
            videoAspectRatio: videoAspectRatio,
            stampDateText: "\(CameraRollStampFormat.date.string(from: item.capturedAt)) \(CameraRollStampFormat.weekday.string(from: item.capturedAt).uppercased())",
            stampTimeText: CameraRollStampFormat.hourMinute.string(from: item.capturedAt),
            placeText: stampContext?.placeName
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 },
            segmentDurations: day.items.map { max($0.duration, 0) },
            currentClipIndex: clipIndex
        )
    }
}

// MARK: - Progress bar layout

/// 再生画面下のバー。クリップごとに区切って並べ、本数が多すぎて区切りが読めなくなったら1本のバーにする。
enum PlaybackProgressLayout {
    static let regularGap: CGFloat = 3
    static let compactGap: CGFloat = 1.5
    /// 区切りとして読める最小の幅。
    static let regularMinimumWidth: CGFloat = 6
    static let compactMinimumWidth: CGFloat = 3

    enum Style: Equatable {
        /// 区切って並べる。`gap` は区切りの隙間。
        case segmented(gap: CGFloat)
        /// 1本のバー（本数が多い日）。
        case continuous
    }

    static func style(count: Int, width: CGFloat) -> Style {
        guard count > 1, width > 0 else { return .continuous }
        if averageWidth(count: count, width: width, gap: regularGap) >= regularMinimumWidth {
            return .segmented(gap: regularGap)
        }
        if averageWidth(count: count, width: width, gap: compactGap) >= compactMinimumWidth {
            return .segmented(gap: compactGap)
        }
        return .continuous
    }

    /// 各区切りの幅。長いクリップほど広いが、短いものも最小幅は確保し、合計は `width` からすき間を引いた値に一致する。
    static func segmentWidths(durations: [TimeInterval], width: CGFloat, gap: CGFloat) -> [CGFloat] {
        let count = durations.count
        guard count > 0 else { return [] }
        let available = max(width - gap * CGFloat(count - 1), 0)
        let minimum = min(2, available / CGFloat(count))
        let flexible = available - minimum * CGFloat(count)
        let safeDurations = durations.map { $0.isFinite ? max($0, 0) : 0 }
        let total = safeDurations.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: available / CGFloat(count), count: count)
        }
        return safeDurations.map { minimum + flexible * CGFloat($0 / total) }
    }

    private static func averageWidth(count: Int, width: CGFloat, gap: CGFloat) -> CGFloat {
        (width - gap * CGFloat(count - 1)) / CGFloat(count)
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
