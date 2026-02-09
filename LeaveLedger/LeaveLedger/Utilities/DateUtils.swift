import Foundation
import OSLog

enum DateUtils {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else {
            os_log(.error, log: Logger.general, "Failed to create date from components: %d-%d-%d", year, month, day)
            // Return a fallback date to prevent crashes
            return Date()
        }
        return date
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addDays(_ date: Date, _ days: Int) -> Date {
        guard let newDate = calendar.date(byAdding: .day, value: days, to: date) else {
            os_log(.error, log: Logger.general, "Failed to add %d days to date", days)
            return date // Return original date as fallback
        }
        return newDate
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let fromStart = startOfDay(from)
        let toStart = startOfDay(to)
        let components = calendar.dateComponents([.day], from: fromStart, to: toStart)
        guard let days = components.day else {
            os_log(.error, log: Logger.general, "Failed to calculate days between dates")
            return 0
        }
        return days
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func dateOnlyCompare(_ a: Date, _ b: Date) -> ComparisonResult {
        let aStart = startOfDay(a)
        let bStart = startOfDay(b)
        if aStart < bStart { return .orderedAscending }
        if aStart > bStart { return .orderedDescending }
        return .orderedSame
    }

    static func monthRange(for date: Date) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else {
            os_log(.error, log: Logger.general, "Failed to calculate month range for date")
            return (date, date) // Return same date as fallback
        }
        return (start, end)
    }

    static func daysInMonth(for date: Date) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date) else {
            os_log(.error, log: Logger.general, "Failed to get days in month for date")
            return 30 // Return reasonable default
        }
        return range.count
    }

    static func firstWeekday(of date: Date) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let first = calendar.date(from: comps) else {
            os_log(.error, log: Logger.general, "Failed to get first day of month")
            return 1 // Return Sunday as default
        }
        return calendar.component(.weekday, from: first) // 1=Sun ... 7=Sat
    }

    static func monthYear(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }

    static func isoDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    static func parseISO(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: string)
    }

    static func year(_ date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    static func month(_ date: Date) -> Int {
        calendar.component(.month, from: date)
    }

    static func day(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }
}
