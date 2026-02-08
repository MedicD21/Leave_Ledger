import Foundation

/// Generates ICS (iCalendar) content from leave entries.
struct ICSService {
    /// Generates an ICS string for all entries plus virtual payday accrual events.
    static func generateICS(
        entries: [LeaveEntry],
        profile: UserProfile,
        fromDate: Date? = nil,
        toDate: Date? = nil
    ) -> String {
        let from = fromDate ?? DateUtils.addDays(Date(), -365)
        let to = toDate ?? DateUtils.addDays(Date(), 365)

        var ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//LeaveLedger//LeaveLedger//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        X-WR-CALNAME:Leave Ledger
        X-WR-TIMEZONE:America/New_York

        """

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"

        // Add entry events
        for entry in entries where !entry.isDeleted {
            let entryDate = DateUtils.startOfDay(entry.date)
            guard entryDate >= from && entryDate <= to else { continue }

            let dateStr = dateFormatter.string(from: entry.date)
            let nextDay = dateFormatter.string(from: DateUtils.addDays(entry.date, 1))
            let hours = NSDecimalNumber(decimal: entry.hours).doubleValue
            let hoursStr = String(format: "%.2f", hours)

            let title: String
            switch entry.action {
            case .accrued:
                title = "\(entry.leaveType.displayName) Accrued \(hoursStr)h"
            case .used:
                title = "\(entry.leaveType.displayName) Used \(hoursStr)h"
            case .adjustment:
                let sign = entry.adjustmentSign == .negative ? "-" : "+"
                title = "\(entry.leaveType.displayName) Adj \(sign)\(hoursStr)h"
            }

            let payday = PayPeriodService.paydayFor(
                date: entry.date, anchorPayday: profile.anchorPayday)
            let period = PayPeriodService.payPeriod(forPayday: payday)
            let isPosted = DateUtils.dateOnlyCompare(payday, Date()) != .orderedDescending

            let uid = entry.id.uuidString
            let notes = [
                entry.notes ?? "",
                "Pay Period: \(period.description)",
                "Status: \(isPosted ? "Posted" : "Pending")",
                "leaveLedger://entry/\(entry.id.uuidString)"
            ].joined(separator: "\\n")

            // Color via category
            let category: String
            switch entry.action {
            case .accrued: category = "Green"
            case .used: category = "Red"
            case .adjustment:
                category = entry.adjustmentSign == .negative ? "Red" : "Green"
            }

            ics += """
            BEGIN:VEVENT
            UID:\(uid)@leaveLedger
            DTSTART;VALUE=DATE:\(dateStr)
            DTEND;VALUE=DATE:\(nextDay)
            SUMMARY:\(title)
            DESCRIPTION:\(notes)
            CATEGORIES:\(category)
            TRANSP:TRANSPARENT
            END:VEVENT

            """
        }

        // Add virtual payday accrual events
        let paydays = PayPeriodService.paydays(
            from: from, to: to, anchorPayday: profile.anchorPayday)
        for payday in paydays {
            let dateStr = dateFormatter.string(from: payday)
            let nextDay = dateFormatter.string(from: DateUtils.addDays(payday, 1))

            let vacRate = NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue
            let sickRate = NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue

            // Payday event
            ics += """
            BEGIN:VEVENT
            UID:payday-\(dateStr)@leaveLedger
            DTSTART;VALUE=DATE:\(dateStr)
            DTEND;VALUE=DATE:\(nextDay)
            SUMMARY:Payday (Vac +\(String(format: "%.2f", vacRate))h, Sick +\(String(format: "%.2f", sickRate))h)
            CATEGORIES:Blue
            TRANSP:TRANSPARENT
            END:VEVENT

            """
        }

        ics += "END:VCALENDAR\n"
        return ics
    }
}
