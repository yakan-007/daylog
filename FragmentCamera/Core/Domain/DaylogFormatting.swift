import Foundation

enum DaylogFormatters {
    private static func localizedDateFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dayTitleFormatter: DateFormatter = {
        localizedDateFormatter(template: "MMMd")
    }()

    static let weekdayFormatter: DateFormatter = {
        localizedDateFormatter(template: "EEE")
    }()

    static let monthTitleFormatter: DateFormatter = {
        localizedDateFormatter(template: "MMMM")
    }()

    static let yearMonthTitleFormatter: DateFormatter = {
        localizedDateFormatter(template: "yMMMM")
    }()

    static let yearTitleFormatter: DateFormatter = {
        localizedDateFormatter(template: "yyyy")
    }()

    static let feedDateFormatter: DateFormatter = {
        localizedDateFormatter(template: "MMMdEEE")
    }()

    static let feedTimeFormatter: DateFormatter = {
        localizedDateFormatter(template: "jmm")
    }()

    static var veryShortWeekdaySymbols: [String] {
        let symbols = weekdayFormatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let firstIndex = max(0, min(Calendar.autoupdatingCurrent.firstWeekday - 1, 6))
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

}
