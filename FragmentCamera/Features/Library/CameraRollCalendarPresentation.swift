import Foundation

struct CameraRollCalendarMonth: Equatable {
    let start: Date
    let cells: [Date?]
    let recordedDays: [CameraRollCalendarDayItem]

    var recordedDayCount: Int { recordedDays.count }
    var clipCount: Int { recordedDays.reduce(0) { $0 + $1.clipCount } }
    var totalDuration: TimeInterval {
        recordedDays.reduce(0) { $0 + $1.totalDuration }
    }

    func recordedDay(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CameraRollCalendarDayItem? {
        recordedDays.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

enum CameraRollCalendarPresenter {
    static func makeMonth(
        containing date: Date,
        days: [CameraRollCalendarDayItem],
        calendar: Calendar = .autoupdatingCurrent
    ) -> CameraRollCalendarMonth {
        let start = monthStart(containing: date, calendar: calendar)
        let recordedDays = days.filter {
            calendar.isDate($0.date, equalTo: start, toGranularity: .month)
        }

        return CameraRollCalendarMonth(
            start: start,
            cells: makeCells(monthStart: start, calendar: calendar),
            recordedDays: recordedDays
        )
    }

    static func monthStart(
        containing date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func month(
        offsetBy offset: Int,
        from date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: date) else {
            return nil
        }
        return monthStart(containing: shifted, calendar: calendar)
    }

    static func containsRecordings(
        in month: Date,
        days: [CameraRollCalendarDayItem],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        days.contains {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private static func makeCells(
        monthStart: Date,
        calendar: Calendar
    ) -> [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leadingCount)
        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        })

        let trailingCount = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailingCount))
        return cells
    }
}
