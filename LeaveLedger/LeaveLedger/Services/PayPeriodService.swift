import Foundation

/// Computes pay periods and paydays based on a biweekly anchor payday.
///
/// Given anchor payday 2026-02-06 and its pay period 2026-01-17 to 2026-01-30:
///   PayPeriodEnd = payday - 7 days
///   PayPeriodStart = PayPeriodEnd - 13 days (14 day period inclusive)
///   Next payday = payday + 14 days
enum PayPeriodService {
    static let payInterval = 14

    /// Returns the PayPeriod for a given payday date.
    static func payPeriod(forPayday payday: Date) -> PayPeriod {
        let end = DateUtils.addDays(payday, -7)
        let start = DateUtils.addDays(end, -13)
        return PayPeriod(start: DateUtils.startOfDay(start),
                         end: DateUtils.startOfDay(end),
                         payday: DateUtils.startOfDay(payday))
    }

    /// Returns the payday that closes the pay period containing `date`.
    static func paydayFor(date: Date, anchorPayday: Date) -> Date {
        let anchor = DateUtils.startOfDay(anchorPayday)
        let target = DateUtils.startOfDay(date)
        let anchorPeriod = payPeriod(forPayday: anchor)

        // Check if target falls within the anchor period
        if target >= anchorPeriod.start && target <= anchorPeriod.end {
            return anchor
        }

        let daysDiff = DateUtils.daysBetween(anchorPeriod.start, target)

        if daysDiff >= 0 {
            // Forward: how many full 14-day periods from anchor period start
            let periodsForward = daysDiff / payInterval
            let candidatePayday = DateUtils.addDays(anchor, periodsForward * payInterval)
            let candidatePeriod = payPeriod(forPayday: candidatePayday)
            if target >= candidatePeriod.start && target <= candidatePeriod.end {
                return candidatePayday
            }
            // Must be in next period
            return DateUtils.addDays(candidatePayday, payInterval)
        } else {
            // Backward
            let periodsBack = (-daysDiff + payInterval - 1) / payInterval
            let candidatePayday = DateUtils.addDays(anchor, -periodsBack * payInterval)
            let candidatePeriod = payPeriod(forPayday: candidatePayday)
            if target >= candidatePeriod.start && target <= candidatePeriod.end {
                return candidatePayday
            }
            // Check adjacent periods
            let nextPayday = DateUtils.addDays(candidatePayday, payInterval)
            let nextPeriod = payPeriod(forPayday: nextPayday)
            if target >= nextPeriod.start && target <= nextPeriod.end {
                return nextPayday
            }
            return DateUtils.addDays(candidatePayday, -payInterval)
        }
    }

    /// Returns the most recent payday on or before `date`.
    static func lastPayday(asOf date: Date, anchorPayday: Date) -> Date {
        let anchor = DateUtils.startOfDay(anchorPayday)
        let target = DateUtils.startOfDay(date)

        if target >= anchor {
            let daysDiff = DateUtils.daysBetween(anchor, target)
            let periods = daysDiff / payInterval
            return DateUtils.addDays(anchor, periods * payInterval)
        } else {
            let daysDiff = DateUtils.daysBetween(target, anchor)
            let periods = (daysDiff + payInterval - 1) / payInterval
            let candidate = DateUtils.addDays(anchor, -periods * payInterval)
            if DateUtils.dateOnlyCompare(candidate, target) == .orderedDescending {
                return DateUtils.addDays(candidate, -payInterval)
            }
            return candidate
        }
    }

    /// Returns all paydays in the given date range (inclusive).
    static func paydays(from start: Date, to end: Date, anchorPayday: Date) -> [Date] {
        let firstPayday = nextPaydayOnOrAfter(date: start, anchorPayday: anchorPayday)
        var result: [Date] = []
        var current = firstPayday
        let endDay = DateUtils.startOfDay(end)
        while DateUtils.dateOnlyCompare(current, endDay) != .orderedDescending {
            result.append(current)
            current = DateUtils.addDays(current, payInterval)
        }
        return result
    }

    /// Returns the next payday on or after the given date.
    static func nextPaydayOnOrAfter(date: Date, anchorPayday: Date) -> Date {
        let last = lastPayday(asOf: date, anchorPayday: anchorPayday)
        if DateUtils.isSameDay(last, date) {
            return last
        }
        return DateUtils.addDays(last, payInterval)
    }

    /// Checks if a given date is a payday.
    static func isPayday(_ date: Date, anchorPayday: Date) -> Bool {
        let last = lastPayday(asOf: date, anchorPayday: anchorPayday)
        return DateUtils.isSameDay(last, date)
    }

    /// Returns ordered paydays from anchor to target payday (exclusive of anchor, inclusive of target)
    /// when moving forward, or (exclusive of anchor, inclusive of target) when moving backward.
    static func paydaysBetween(anchorPayday: Date, targetPayday: Date) -> [Date] {
        let anchor = DateUtils.startOfDay(anchorPayday)
        let target = DateUtils.startOfDay(targetPayday)
        if DateUtils.isSameDay(anchor, target) { return [] }

        var result: [Date] = []
        if target > anchor {
            var current = DateUtils.addDays(anchor, payInterval)
            while DateUtils.dateOnlyCompare(current, target) != .orderedDescending {
                result.append(current)
                current = DateUtils.addDays(current, payInterval)
            }
        } else {
            var current = DateUtils.addDays(anchor, -payInterval)
            while DateUtils.dateOnlyCompare(current, target) != .orderedAscending {
                result.append(current)
                current = DateUtils.addDays(current, -payInterval)
            }
            result.reverse()
        }
        return result
    }
}
