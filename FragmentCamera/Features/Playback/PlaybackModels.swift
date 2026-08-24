import Foundation

enum ClipPlaybackMode: String, Hashable, Sendable {
    case browse
    case continuousDay
}

struct PlaybackRoute: Identifiable {
    let context: LibraryClipPlaybackContext

    var id: String { context.id }
}

struct PlaybackClipItem: Identifiable, Hashable, Sendable {
    let assetLocalIdentifier: String
    let capturedAt: Date
    let dayKey: String
    let duration: TimeInterval
    let displayDateText: String
    let displayTimeText: String

    var id: String { assetLocalIdentifier }

    init(
        assetLocalIdentifier: String,
        capturedAt: Date,
        dayKey: String,
        duration: TimeInterval,
        displayDateText: String,
        displayTimeText: String
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.capturedAt = capturedAt
        self.dayKey = dayKey
        self.duration = duration
        self.displayDateText = displayDateText
        self.displayTimeText = displayTimeText
    }

    init(clip: ClipSummary) {
        self.init(
            assetLocalIdentifier: clip.assetLocalIdentifier,
            capturedAt: clip.capturedAt,
            dayKey: clip.dayKey,
            duration: clip.duration,
            displayDateText: DaylogFormatters.feedDateFormatter.string(from: clip.capturedAt),
            displayTimeText: DaylogFormatters.feedTimeFormatter.string(from: clip.capturedAt)
        )
    }
}

struct LibraryClipPlaybackDay: Identifiable, Hashable, Sendable {
    let dayKey: String
    let displayDateText: String
    let weekdayText: String
    let totalDuration: TimeInterval
    let clipCount: Int
    let items: [PlaybackClipItem]

    var id: String { dayKey }

    init(
        dayKey: String,
        displayDateText: String,
        weekdayText: String,
        totalDuration: TimeInterval,
        clipCount: Int,
        items: [PlaybackClipItem]
    ) {
        self.dayKey = dayKey
        self.displayDateText = displayDateText
        self.weekdayText = weekdayText
        self.totalDuration = totalDuration
        self.clipCount = clipCount
        self.items = items.sorted { left, right in
            if left.capturedAt != right.capturedAt {
                return left.capturedAt < right.capturedAt
            }
            return left.assetLocalIdentifier < right.assetLocalIdentifier
        }
    }
}

struct LibraryClipPlaybackContext: Identifiable, Hashable, Sendable {
    let days: [LibraryClipPlaybackDay]
    let initialDayIndex: Int
    let initialClipIndex: Int
    let mode: ClipPlaybackMode

    init(
        days: [LibraryClipPlaybackDay],
        initialDayIndex: Int,
        initialClipIndex: Int,
        mode: ClipPlaybackMode = .browse
    ) {
        self.days = days
        self.initialDayIndex = initialDayIndex
        self.initialClipIndex = initialClipIndex
        self.mode = mode
    }

    var id: String {
        let joined = days.map(\.dayKey).joined(separator: ",")
        return "\(mode.rawValue)|\(initialDayIndex)|\(initialClipIndex)|\(joined)"
    }
}
