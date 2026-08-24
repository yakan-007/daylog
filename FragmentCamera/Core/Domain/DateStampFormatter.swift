import Foundation
import OSLog

enum DateStampFormatter {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FragmentCamera",
        category: "settings"
    )
    static let compactDateTime = "y.M.d H:mm"
    static let zeroPaddedDateTime = "yyyy.MM.dd HH:mm"

    static let supportedFormats: Set<String> = [
        compactDateTime,
        zeroPaddedDateTime
    ]

    static func resolvedFormat(storedFormat: String, zeroPadded: Bool) -> String {
        let fallback = zeroPadded ? zeroPaddedDateTime : compactDateTime
        let trimmed = storedFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, supportedFormats.contains(trimmed) else {
            logger.notice("date_stamp_format_fallback format=\(storedFormat, privacy: .public)")
            return fallback
        }
        return zeroPadded ? zeroPaddedDateTime : compactDateTime
    }

    static func lines(
        from date: Date,
        storedFormat: String,
        zeroPadded: Bool,
        timeStyle: DateStampTimeStyle,
        elements: Set<DateStampElement>,
        placeName: String? = nil,
        timeZone: TimeZone? = nil
    ) -> [String] {
        let resolved = resolvedFormat(storedFormat: storedFormat, zeroPadded: zeroPadded)
        let dateText = string(
            from: date,
            format: resolved == zeroPaddedDateTime ? "yyyy.MM.dd" : "y.M.d",
            timeZone: timeZone
        )
        let timeText = timeString(
            from: date,
            style: timeStyle,
            timeZone: timeZone
        )
        var lines: [String] = []

        if elements.contains(.date) {
            lines.append(dateText)
        }
        if elements.contains(.time) {
            lines.append(timeText)
        }

        if elements.contains(.place),
           let placeName = placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !placeName.isEmpty {
            lines.append(placeName)
        }
        if lines.isEmpty {
            // 「場所のみ」を選んだ撮影で測位・地名解決に失敗しても、
            // スタンプONなのに何も表示されない状態を避ける。
            lines.append(timeText)
        }
        return lines
    }

    private static func timeString(
        from date: Date,
        style: DateStampTimeStyle,
        timeZone: TimeZone?
    ) -> String {
        switch style {
        case .twelveHour:
            let formatter = Foundation.DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm a"
            formatter.timeZone = timeZone
            return formatter.string(from: date)
        case .twentyFourHour:
            return string(from: date, format: "H:mm", timeZone: timeZone)
        }
    }

    private static func string(
        from date: Date,
        format: String,
        timeZone: TimeZone?
    ) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
