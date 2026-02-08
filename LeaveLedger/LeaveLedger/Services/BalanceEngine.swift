import Foundation

/// Deterministic balance calculation engine.
///
/// OFFICIAL balance: Incorporates only entries from pay periods whose payday <= asOfPayday.
/// Plus accruals (vac/sick) for each payday <= asOfPayday.
///
/// FORECAST balance: Incorporates all entries with date <= targetDate,
/// plus accruals for each payday <= targetDate.
struct BalanceEngine {
    let anchorPayday: Date
    let startingBalances: BalanceSnapshot
    let vacAccrualRate: Decimal
    let sickAccrualRate: Decimal

    init(
        anchorPayday: Date = DateUtils.makeDate(2026, 2, 6),
        compStart: Decimal = Decimal(string: "0.25")!,
        vacStart: Decimal = Decimal(string: "33.72")!,
        sickStart: Decimal = Decimal(string: "801.84")!,
        vacAccrualRate: Decimal = Decimal(string: "6.46")!,
        sickAccrualRate: Decimal = Decimal(string: "7.88")!
    ) {
        self.anchorPayday = DateUtils.startOfDay(anchorPayday)
        self.startingBalances = BalanceSnapshot(comp: compStart, vacation: vacStart, sick: sickStart)
        self.vacAccrualRate = vacAccrualRate
        self.sickAccrualRate = sickAccrualRate
    }

    // MARK: - Official Balance

    /// Computes OFFICIAL balance as of a given payday.
    /// Starting balances represent official at the anchor payday.
    func officialBalance(asOfPayday payday: Date, entries: [LeaveEntry]) -> BalanceSnapshot {
        let targetPayday = DateUtils.startOfDay(payday)
        var balance = startingBalances

        // Starting balances are the baseline official balance at the anchor payday.
        // DB entries (including those in the anchor's pay period) are ADDITIVE — they
        // represent user-entered data that adjusts the baseline. The baseline already
        // accounts for historical payroll, but any entries the user adds in the app
        // (even for the anchor period) are applied on top.

        if DateUtils.isSameDay(targetPayday, anchorPayday) {
            // Apply any user entries from the anchor pay period
            let anchorEntries = entriesForPayday(anchorPayday, entries: entries)
            for entry in anchorEntries {
                balance.apply(leaveType: entry.leaveType, signedHours: entry.signedHours)
            }
            return balance
        }

        let isForward = targetPayday > anchorPayday

        if isForward {
            // First apply anchor period entries
            let anchorEntries = entriesForPayday(anchorPayday, entries: entries)
            for entry in anchorEntries {
                balance.apply(leaveType: entry.leaveType, signedHours: entry.signedHours)
            }

            // Then for each subsequent payday up to target, apply accruals and entries.
            let paydays = PayPeriodService.paydaysBetween(
                anchorPayday: anchorPayday, targetPayday: targetPayday)
            for pd in paydays {
                balance.applyAccruals(vacRate: vacAccrualRate, sickRate: sickAccrualRate)
                let pdEntries = entriesForPayday(pd, entries: entries)
                for entry in pdEntries {
                    balance.apply(leaveType: entry.leaveType, signedHours: entry.signedHours)
                }
            }
        } else {
            // Moving backward from anchor to an earlier payday.
            // Un-apply the anchor payday's accrual (it was baked into the baseline)
            // and then continue backward.

            // Un-apply anchor accrual to get to the state before anchor processing
            balance.applyAccruals(vacRate: -vacAccrualRate, sickRate: -sickAccrualRate)

            // Now balance represents the end of the previous payday (anchor - 14).
            let prevPayday = DateUtils.addDays(anchorPayday, -PayPeriodService.payInterval)

            if DateUtils.isSameDay(targetPayday, prevPayday) {
                return balance
            }

            // Continue walking backward
            var current = prevPayday
            while DateUtils.dateOnlyCompare(current, targetPayday) == .orderedDescending {
                balance.applyAccruals(vacRate: -vacAccrualRate, sickRate: -sickAccrualRate)
                current = DateUtils.addDays(current, -PayPeriodService.payInterval)
            }
        }

        return balance
    }

    /// Convenience: official balance as of last payday before or on `today`.
    func currentOfficialBalance(asOf today: Date, entries: [LeaveEntry]) -> BalanceSnapshot {
        let lastPD = PayPeriodService.lastPayday(asOf: today, anchorPayday: anchorPayday)
        return officialBalance(asOfPayday: lastPD, entries: entries)
    }

    /// Returns the last payday on or before the given date.
    func lastPayday(asOf date: Date) -> Date {
        PayPeriodService.lastPayday(asOf: date, anchorPayday: anchorPayday)
    }

    // MARK: - Forecast Balance

    /// Computes FORECAST balance as of target date D.
    /// Includes all entries with date <= D, plus accruals for each payday <= D.
    func forecastBalance(asOf targetDate: Date, entries: [LeaveEntry]) -> BalanceSnapshot {
        let target = DateUtils.startOfDay(targetDate)
        var balance = startingBalances

        // Determine paydays between anchor and target (exclusive of anchor)
        let isForward = target >= anchorPayday

        if isForward {
            // Count paydays from anchor+14 up to target
            var pd = DateUtils.addDays(anchorPayday, PayPeriodService.payInterval)
            while DateUtils.dateOnlyCompare(pd, target) != .orderedDescending {
                balance.applyAccruals(vacRate: vacAccrualRate, sickRate: sickAccrualRate)
                pd = DateUtils.addDays(pd, PayPeriodService.payInterval)
            }
        } else {
            // Count paydays from anchor backward: un-apply accruals for anchor and each prior payday > target
            // The starting balance includes the anchor payday's accrual.
            // We need to un-apply accruals for paydays > target.
            balance.applyAccruals(vacRate: -vacAccrualRate, sickRate: -sickAccrualRate)
            var pd = DateUtils.addDays(anchorPayday, -PayPeriodService.payInterval)
            while DateUtils.dateOnlyCompare(pd, target) == .orderedDescending {
                balance.applyAccruals(vacRate: -vacAccrualRate, sickRate: -sickAccrualRate)
                pd = DateUtils.addDays(pd, -PayPeriodService.payInterval)
            }
        }

        // Apply ALL entries with date <= target
        let activeEntries = entries.filter { !$0.isDeleted }
        for entry in activeEntries {
            let entryDate = DateUtils.startOfDay(entry.date)
            if DateUtils.dateOnlyCompare(entryDate, target) != .orderedDescending {
                balance.apply(leaveType: entry.leaveType, signedHours: entry.signedHours)
            }
        }

        return balance
    }

    // MARK: - Posted Status

    /// Returns whether an entry is "Posted" (its pay period's payday <= today's last payday).
    func isPosted(entry: LeaveEntry, asOf today: Date) -> Bool {
        let entryPayday = PayPeriodService.paydayFor(date: entry.date, anchorPayday: anchorPayday)
        let lastPD = PayPeriodService.lastPayday(asOf: today, anchorPayday: anchorPayday)
        return DateUtils.dateOnlyCompare(entryPayday, lastPD) != .orderedDescending
    }

    // MARK: - Helpers

    /// Returns non-deleted entries whose date falls within the pay period of the given payday.
    private func entriesForPayday(_ payday: Date, entries: [LeaveEntry]) -> [LeaveEntry] {
        let period = PayPeriodService.payPeriod(forPayday: payday)
        return entries.filter { entry in
            guard !entry.isDeleted else { return false }
            let entryDate = DateUtils.startOfDay(entry.date)
            return entryDate >= period.start && entryDate <= period.end
        }
    }
}
