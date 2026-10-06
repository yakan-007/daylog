import Foundation

// MARK: - Screen state

struct CameraRollScreenState: Equatable {
    var days: [CameraRollDayItem] = []
    var calendarDays: [CameraRollCalendarDayItem] = []
    var isRefreshing = false
    var exportProgress: DayVideoExportProgress? = nil
    /// 書き出し中の対象（カードの見出しとクリップの帯に使う）。
    var exportSubject: CameraRollExportSubject? = nil
    /// 書き出しが終わって、共有を待っている動画。
    var exportCompletion: CameraRollExportCompletion? = nil

    var showsInitialLoading: Bool {
        days.isEmpty && isRefreshing
    }

    var showsEmptyState: Bool {
        days.isEmpty && !isRefreshing
    }
}

/// 書き出しの対象（1日、または1本）の要約。
struct CameraRollExportSubject: Equatable {
    enum Origin: Equatable {
        case day(id: String)
        case clip(id: String)
    }

    /// 帯に並べるクリップの最大数。多い日は間引いて、端から端まで均等に選ぶ。
    static let maximumPreviewCount = 10

    let origin: Origin
    let title: String
    let clipCount: Int
    let durationText: String
    let previewClipIDs: [String]

    init(origin: Origin, title: String, clipCount: Int, durationText: String, clipIDs: [String]) {
        self.origin = origin
        self.title = title
        self.clipCount = clipCount
        self.durationText = durationText
        self.previewClipIDs = Self.sampled(clipIDs, limit: Self.maximumPreviewCount)
    }

    static func sampled(_ ids: [String], limit: Int) -> [String] {
        guard ids.count > limit, limit > 1 else { return Array(ids.prefix(max(limit, 0))) }
        let step = Double(ids.count - 1) / Double(limit - 1)
        return (0..<limit).map { ids[Int((Double($0) * step).rounded())] }
    }
}

struct CameraRollExportCompletion: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let subject: CameraRollExportSubject
}

struct CameraRollCalendarDayItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let clipCount: Int
    let totalDuration: TimeInterval
    let durationText: String
    let previewAssetIdentifier: String
    /// 0時=0, 24時=1 の位置。昇順。
    var clipFractions: [Double] = []
}

struct CameraRollDayItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let totalDuration: TimeInterval
    let weekdayText: String
    let dateText: String
    let durationText: String
    let summaryText: String
    let exportAssessment: DayVideoExportAssessment
    let isExporting: Bool
    let exportProgress: Double?
    let canExport: Bool
    /// 撮影順（古い→新しい）。
    let clips: [CameraRollClipItem]
    /// "10.04" のような日付スタンプ表記。
    var stampDateText: String = ""
    /// "SUN" のような英字の曜日スタンプ表記。
    var stampWeekdayText: String = ""
    var isToday: Bool = false

    var clipCount: Int { clips.count }
}

struct CameraRollClipItem: Identifiable, Equatable {
    let id: String
    let timeText: String
    let durationText: String
    let isExporting: Bool
    let exportProgress: Double?
    let canExport: Bool
    /// 0時=0, 24時=1 の位置。
    var dayFraction: Double = 0
    /// 0〜23。
    var hour: Int = 0
}

// MARK: - Presenter

enum CameraRollPresenter {
    static func makeState(
        sections: [DaySection],
        calendarSummaries: [DayCalendarSummary] = [],
        isRefreshing: Bool,
        exportingDayKey: String?,
        exportingClipID: String? = nil,
        exportProgress: DayVideoExportProgress? = nil,
        calendar: Calendar = .current
    ) -> CameraRollScreenState {
        CameraRollScreenState(
            days: sections
                .sorted { $0.date > $1.date }
                .map {
                    makeDayItem(
                        section: $0,
                        exportingDayKey: exportingDayKey,
                        exportingClipID: exportingClipID,
                        exportProgress: exportProgress,
                        calendar: calendar
                    )
                },
            calendarDays: calendarSummaries.map { summary in
                CameraRollCalendarDayItem(
                    id: summary.id,
                    date: summary.date,
                    clipCount: summary.clipCount,
                    totalDuration: summary.totalDuration,
                    durationText: VlogishFormatters.durationLabel(summary.totalDuration),
                    previewAssetIdentifier: summary.previewAssetIdentifier,
                    clipFractions: summary.clipDayOffsets
                        .map { CameraRollTimeAxis.fraction(forDayOffset: $0) }
                        .sorted()
                )
            },
            isRefreshing: isRefreshing,
            exportProgress: exportProgress
        )
    }

    static func makeDayItem(
        section: DaySection,
        exportingDayKey: String?,
        exportingClipID: String? = nil,
        exportProgress: DayVideoExportProgress? = nil,
        calendar: Calendar = .current
    ) -> CameraRollDayItem {
        let hasActiveExport = exportingDayKey != nil || exportingClipID != nil
        let clipCount = section.clips.count
        return CameraRollDayItem(
            id: section.id,
            date: section.date,
            totalDuration: section.totalDuration,
            weekdayText: VlogishFormatters.weekdayFormatter
                .string(from: section.date)
                .uppercased(),
            dateText: VlogishFormatters.dayTitleFormatter.string(from: section.date),
            durationText: VlogishFormatters.durationLabel(section.totalDuration),
            summaryText: clipCount == 1
                ? L10n.text("1本")
                : L10n.text("%d本", clipCount),
            exportAssessment: DayVideoExportPolicy.assess(
                clipCount: clipCount,
                totalDuration: section.totalDuration
            ),
            isExporting: exportingDayKey == section.dayKey,
            exportProgress: exportingDayKey == section.dayKey ? exportProgress?.fraction : nil,
            canExport: !hasActiveExport,
            clips: section.chronologicalClips.map { clip in
                let offset = clip.capturedAt.timeIntervalSince(calendar.startOfDay(for: clip.capturedAt))
                return CameraRollClipItem(
                    id: clip.assetLocalIdentifier,
                    // 時間軸（0〜24）と同じ物差しで読めるよう、24時間表記に固定する。
                    timeText: CameraRollStampFormat.hourMinute.string(from: clip.capturedAt),
                    durationText: VlogishFormatters.durationLabel(clip.duration),
                    isExporting: exportingClipID == clip.assetLocalIdentifier,
                    exportProgress: exportingClipID == clip.assetLocalIdentifier ? exportProgress?.fraction : nil,
                    canExport: !hasActiveExport,
                    dayFraction: CameraRollTimeAxis.fraction(forDayOffset: offset),
                    hour: CameraRollTimeAxis.hour(forDayOffset: offset)
                )
            },
            stampDateText: CameraRollStampFormat.date.string(from: section.date),
            stampWeekdayText: CameraRollStampFormat.weekday.string(from: section.date).uppercased(),
            isToday: calendar.isDateInToday(section.date)
        )
    }
}

// MARK: - Time axis

/// 1日を 0時→24時 の一本の線として扱うための計算。
enum CameraRollTimeAxis {
    static let secondsPerDay: TimeInterval = 86_400

    static func fraction(forDayOffset offset: TimeInterval) -> Double {
        guard offset.isFinite else { return 0 }
        return min(max(offset / secondsPerDay, 0), 1)
    }

    static func hour(forDayOffset offset: TimeInterval) -> Int {
        guard offset.isFinite else { return 0 }
        return min(max(Int(offset / 3_600), 0), 23)
    }

    static func fraction(of date: Date, calendar: Calendar = .current) -> Double {
        fraction(forDayOffset: date.timeIntervalSince(calendar.startOfDay(for: date)))
    }
}

/// 日付スタンプ風の固定表記。言語設定に左右されない。
enum CameraRollStampFormat {
    /// "10.06" のような月日。並びは日付スタンプの設定（既定は地域）に合わせる（日 月の地域では "06.10"）。
    static var date: DateFormatter {
        VlogishSettingsStore().stampDateOrder == .dayMonthYear ? dayMonth : monthDay
    }
    private static let monthDay: DateFormatter = make(DateStampDateOrder.monthDayYear.monthDayPattern)
    private static let dayMonth: DateFormatter = make(DateStampDateOrder.dayMonthYear.monthDayPattern)
    static let weekday: DateFormatter = make("EEE")
    static let month: DateFormatter = make("MM")
    static let monthName: DateFormatter = make("MMMM")
    static let year: DateFormatter = make("yyyy")
    static let hourMinute: DateFormatter = make("HH:mm")

    /// 本数のスタンプ表記（"1 CLIP" / "6 CLIPS"）。日付と同じく言語によらない英字で出す。
    static func clips(_ count: Int) -> String {
        count == 1 ? "1 CLIP" : "\(count) CLIPS"
    }

    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Feed

enum CameraRollFeedEntry: Identifiable, Equatable {
    case day(CameraRollDayItem)
    /// 記録が無かった日（連続する場合はまとめる）。
    case noRecord(id: String, label: String)

    var id: String {
        switch self {
        case .day(let item): return item.id
        case .noRecord(let id, _): return id
        }
    }
}

enum CameraRollFeedPresenter {
    /// `days` は新しい順。読み込み済みの範囲内で、記録が無い日を行として差し込む。
    /// `leadingFrom` を渡すと、その日（今日）と最初の記録日のあいだの空白も先頭に入れる。
    static func entries(
        for days: [CameraRollDayItem],
        leadingFrom today: Date? = nil,
        calendar: Calendar = .current
    ) -> [CameraRollFeedEntry] {
        var result: [CameraRollFeedEntry] = []
        result.reserveCapacity(days.count * 2 + 1)

        if let today, let first = days.first,
           let label = missingLabel(newer: today, older: first.date, calendar: calendar) {
            result.append(.noRecord(id: "gap-leading", label: label))
        }

        for (index, day) in days.enumerated() {
            result.append(.day(day))
            guard index + 1 < days.count else { continue }

            let older = days[index + 1]
            if let label = missingLabel(newer: day.date, older: older.date, calendar: calendar) {
                result.append(.noRecord(id: "gap-\(day.id)", label: label))
            }
        }
        return result
    }

    /// 2つの日のあいだ（両端を含まない）に記録の無い日があれば、その範囲の表記を返す。
    private static func missingLabel(
        newer: Date,
        older: Date,
        calendar: Calendar
    ) -> String? {
        let newerStart = calendar.startOfDay(for: newer)
        let olderStart = calendar.startOfDay(for: older)
        let distance = calendar.dateComponents([.day], from: olderStart, to: newerStart).day ?? 0
        let missing = distance - 1
        guard missing > 0,
              let firstMissing = calendar.date(byAdding: .day, value: -1, to: newerStart),
              let lastMissing = calendar.date(byAdding: .day, value: 1, to: olderStart) else {
            return nil
        }
        if missing == 1 {
            return CameraRollStampFormat.date.string(from: firstMissing)
        }
        return "\(CameraRollStampFormat.date.string(from: firstMissing))–\(CameraRollStampFormat.date.string(from: lastMissing))"
    }
}

// MARK: - Day timeline

enum CameraRollTimelineRow: Identifiable, Equatable {
    case clip(CameraRollClipItem, hourLabel: String?)
    case gap(id: String, hourLabel: String, text: String)
    case now(id: String, hourLabel: String, timeText: String)

    var id: String {
        switch self {
        case .clip(let clip, _): return clip.id
        case .gap(let id, _, _): return id
        case .now(let id, _, _): return id
        }
    }
}

enum CameraRollTimelinePresenter {
    /// `clips` は撮影順。`now` を渡すと（今日の場合）末尾に「いま」の行を置く。
    static func rows(
        for clips: [CameraRollClipItem],
        now: Date? = nil,
        calendar: Calendar = .current
    ) -> [CameraRollTimelineRow] {
        var rows: [CameraRollTimelineRow] = []
        var previousHour: Int?

        for clip in clips {
            if let previousHour {
                appendGap(from: previousHour, to: clip.hour, into: &rows)
            }
            let showsHour = previousHour != clip.hour
            rows.append(.clip(clip, hourLabel: showsHour ? hourText(clip.hour) : nil))
            previousHour = clip.hour
        }

        if let now, let lastHour = previousHour {
            let nowHour = calendar.component(.hour, from: now)
            if nowHour >= lastHour {
                appendGap(from: lastHour, to: nowHour, into: &rows)
                rows.append(.now(
                    id: "now",
                    hourLabel: hourText(nowHour),
                    timeText: CameraRollStampFormat.hourMinute.string(from: now)
                ))
            }
        }
        return rows
    }

    private static func appendGap(
        from previousHour: Int,
        to nextHour: Int,
        into rows: inout [CameraRollTimelineRow]
    ) {
        let emptyHours = nextHour - previousHour - 1
        guard emptyHours > 0 else { return }
        let first = previousHour + 1
        let last = nextHour - 1
        let range = emptyHours == 1 ? hourText(first) : "\(hourText(first))–\(hourText(last))"
        rows.append(.gap(
            id: "gap-\(first)-\(last)",
            hourLabel: hourText(first),
            text: L10n.text("%@  空白 %dh", range, emptyHours)
        ))
    }

    static func hourText(_ hour: Int) -> String {
        String(format: "%02d", min(max(hour, 0), 24))
    }
}
