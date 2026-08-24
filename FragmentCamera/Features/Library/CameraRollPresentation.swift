import Foundation

struct CameraRollScreenState: Equatable {
    var days: [CameraRollDayItem] = []
    var calendarDays: [CameraRollCalendarDayItem] = []
    var isRefreshing = false
    var exportProgress: DayVideoExportProgress? = nil

    var showsInitialLoading: Bool {
        days.isEmpty && isRefreshing
    }

    var showsEmptyState: Bool {
        days.isEmpty && !isRefreshing
    }
}

struct CameraRollCalendarDayItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let clipCount: Int
    let totalDuration: TimeInterval
    let durationText: String
    let previewAssetIdentifier: String
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
    let clips: [CameraRollClipItem]
}

struct CameraRollClipItem: Identifiable, Equatable {
    let id: String
    let timeText: String
    let durationText: String
    let isExporting: Bool
    let exportProgress: Double?
    let canExport: Bool
}

enum CameraRollPresenter {
    static func makeState(
        sections: [DaySection],
        calendarSummaries: [DayCalendarSummary] = [],
        isRefreshing: Bool,
        exportingDayKey: String?,
        exportingClipID: String? = nil,
        exportProgress: DayVideoExportProgress? = nil
    ) -> CameraRollScreenState {
        CameraRollScreenState(
            days: sections.map {
                makeDayItem(
                    section: $0,
                    exportingDayKey: exportingDayKey,
                    exportingClipID: exportingClipID,
                    exportProgress: exportProgress
                )
            },
            calendarDays: calendarSummaries.map { summary in
                CameraRollCalendarDayItem(
                    id: summary.id,
                    date: summary.date,
                    clipCount: summary.clipCount,
                    totalDuration: summary.totalDuration,
                    durationText: DaylogFormatters.durationLabel(summary.totalDuration),
                    previewAssetIdentifier: summary.previewAssetIdentifier
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
        exportProgress: DayVideoExportProgress? = nil
    ) -> CameraRollDayItem {
        let hasActiveExport = exportingDayKey != nil || exportingClipID != nil
        return CameraRollDayItem(
            id: section.id,
            date: section.date,
            totalDuration: section.totalDuration,
            weekdayText: DaylogFormatters.weekdayFormatter
                .string(from: section.date)
                .uppercased(),
            dateText: DaylogFormatters.dayTitleFormatter.string(from: section.date),
            durationText: DaylogFormatters.durationLabel(section.totalDuration),
            summaryText: section.clipCount == 1
                ? L10n.text("1本")
                : L10n.text("%d本", section.clipCount),
            exportAssessment: DayVideoExportPolicy.assess(
                clipCount: section.clipCount,
                totalDuration: section.totalDuration
            ),
            isExporting: exportingDayKey == section.dayKey,
            exportProgress: exportingDayKey == section.dayKey ? exportProgress?.fraction : nil,
            canExport: !hasActiveExport,
            clips: section.chronologicalClips.map { clip in
                CameraRollClipItem(
                    id: clip.assetLocalIdentifier,
                    timeText: DaylogFormatters.feedTimeFormatter
                        .string(from: clip.capturedAt),
                    durationText: DaylogFormatters.durationLabel(clip.duration),
                    isExporting: exportingClipID == clip.assetLocalIdentifier,
                    exportProgress: exportingClipID == clip.assetLocalIdentifier ? exportProgress?.fraction : nil,
                    canExport: !hasActiveExport
                )
            }
        )
    }
}
