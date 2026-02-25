import Foundation
import OSLog

enum DateStampFormatter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FragmentCamera", category: "settings")
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
        // Zero-padding switch takes priority over the stored template.
        return zeroPadded ? zeroPaddedDateTime : compactDateTime
    }

    static func string(from date: Date, storedFormat: String, zeroPadded: Bool) -> String {
        let formatter = Foundation.DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = resolvedFormat(storedFormat: storedFormat, zeroPadded: zeroPadded)
        return formatter.string(from: date)
    }
}
