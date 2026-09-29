import Foundation

struct VlogClipSourceMetadata: Equatable, Sendable {
    let capturedAt: Date
    let capturedPlaceName: String?
    let timeZoneIdentifier: String

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    }
}

struct VlogResolvedTextOverlay: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let anchor: VlogNormalizedPoint
    let style: VlogTextStyle
    let timeRange: VlogOverlayTimeRange
}

/// プレビューと書き出しが共通で使う、編集レシピから表示文字への変換。
enum VlogTextOverlayResolver {
    static func resolve(
        edit: VlogClipEdit,
        metadata: VlogClipSourceMetadata,
        clipDuration: TimeInterval,
        locale: Locale = .autoupdatingCurrent
    ) -> [VlogResolvedTextOverlay] {
        edit.normalized(for: clipDuration).textOverlays.compactMap { overlay in
            guard let text = text(
                for: overlay.source,
                metadata: metadata,
                locale: locale
            ), !text.isEmpty else {
                return nil
            }
            return VlogResolvedTextOverlay(
                id: overlay.id,
                text: text,
                anchor: overlay.anchor,
                style: overlay.style,
                timeRange: overlay.timeRange
            )
        }
    }

    private static func text(
        for source: VlogTextSource,
        metadata: VlogClipSourceMetadata,
        locale: Locale
    ) -> String? {
        switch source {
        case .custom(let text):
            return text
        case .capturedDate(let format):
            return formatDate(
                metadata.capturedAt,
                format: format,
                locale: locale,
                timeZone: metadata.timeZone
            )
        case .capturedTime(let format):
            return formatTime(
                metadata.capturedAt,
                format: format,
                locale: locale,
                timeZone: metadata.timeZone
            )
        case .place:
            return source.resolvedPlaceName(
                capturedPlaceName: metadata.capturedPlaceName
            )
        }
    }

    private static func formatDate(
        _ date: Date,
        format: VlogDateFormat,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch format {
        case .numeric:
            formatter.setLocalizedDateFormatFromTemplate("yMd")
        case .abbreviated:
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        case .full:
            formatter.setLocalizedDateFormatFromTemplate("yMMMMEEEEd")
        }
        return formatter.string(from: date)
    }

    private static func formatTime(
        _ date: Date,
        format: VlogTimeFormat,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch format {
        case .system:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }
}
