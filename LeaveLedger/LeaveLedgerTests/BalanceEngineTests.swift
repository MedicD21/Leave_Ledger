import XCTest
@testable import LeaveLedger

final class BalanceEngineTests: XCTestCase {

    // Default engine with anchor payday 2026-02-06
    // Starting balances: Sick=801.84, Vac=33.72, Comp=0.25
    // Accrual rates: Sick=7.88/payday, Vac=6.46/payday
    let engine = BalanceEngine()
    let anchorPayday = DateUtils.makeDate(2026, 2, 6)

    // MARK: - Pay Period Service Tests

    func testPayPeriodForAnchorPayday() {
        let period = PayPeriodService.payPeriod(forPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(period.start, DateUtils.makeDate(2026, 1, 17)))
        XCTAssertTrue(DateUtils.isSameDay(period.end, DateUtils.makeDate(2026, 1, 30)))
        XCTAssertTrue(DateUtils.isSameDay(period.payday, anchorPayday))
    }

    func testPayPeriodForNextPayday() {
        let nextPayday = DateUtils.makeDate(2026, 2, 20)
        let period = PayPeriodService.payPeriod(forPayday: nextPayday)
        XCTAssertTrue(DateUtils.isSameDay(period.start, DateUtils.makeDate(2026, 1, 31)))
        XCTAssertTrue(DateUtils.isSameDay(period.end, DateUtils.makeDate(2026, 2, 13)))
    }

    func testPaydayForDateInAnchorPeriod() {
        // Jan 25, 2026 is within the anchor pay period (Jan 17-30)
        let payday = PayPeriodService.paydayFor(
            date: DateUtils.makeDate(2026, 1, 25), anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(payday, anchorPayday))
    }

    func testPaydayForDateInNextPeriod() {
        // Feb 2, 2026 is within Jan 31-Feb 13 period -> payday Feb 20
        let payday = PayPeriodService.paydayFor(
            date: DateUtils.makeDate(2026, 2, 2), anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(payday, DateUtils.makeDate(2026, 2, 20)))
    }

    func testLastPaydayBeforeAnchor() {
        // Jan 15 is before anchor payday's period start
        let last = PayPeriodService.lastPayday(
            asOf: DateUtils.makeDate(2026, 1, 15), anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(last, DateUtils.makeDate(2026, 1, 23)))
    }

    func testLastPaydayOnPayday() {
        let last = PayPeriodService.lastPayday(asOf: anchorPayday, anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(last, anchorPayday))
    }

    func testLastPaydayAfterAnchor() {
        // Feb 10 -> last payday is Feb 6
        let last = PayPeriodService.lastPayday(
            asOf: DateUtils.makeDate(2026, 2, 10), anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(last, anchorPayday))
    }

    func testLastPaydayOnNextPayday() {
        // Feb 20 is a payday
        let last = PayPeriodService.lastPayday(
            asOf: DateUtils.makeDate(2026, 2, 20), anchorPayday: anchorPayday)
        XCTAssertTrue(DateUtils.isSameDay(last, DateUtils.makeDate(2026, 2, 20)))
    }

    func testIsPayday() {
        XCTAssertTrue(PayPeriodService.isPayday(anchorPayday, anchorPayday: anchorPayday))
        XCTAssertTrue(PayPeriodService.isPayday(DateUtils.makeDate(2026, 2, 20), anchorPayday: anchorPayday))
        XCTAssertFalse(PayPeriodService.isPayday(DateUtils.makeDate(2026, 2, 7), anchorPayday: anchorPayday))
    }

    // MARK: - Official Balance Tests

    func testOfficialBalanceAtAnchorPayday() {
        // At anchor payday with no entries, starting balances should be returned.
        let balance = engine.officialBalance(asOfPayday: anchorPayday, entries: [])
        XCTAssertEqual(balance.sick, Decimal(string: "801.84")!)
        XCTAssertEqual(balance.vacation, Decimal(string: "33.72")!)
        XCTAssertEqual(balance.comp, Decimal(string: "0.25")!)
    }

    func testOfficialBalanceAtNextPayday_NoEntries() {
        // Next payday Feb 20: starting + one accrual cycle
        let nextPayday = DateUtils.makeDate(2026, 2, 20)
        let balance = engine.officialBalance(asOfPayday: nextPayday, entries: [])

        let expectedSick = Decimal(string: "801.84")! + Decimal(string: "7.88")!
        let expectedVac = Decimal(string: "33.72")! + Decimal(string: "6.46")!
        let expectedComp = Decimal(string: "0.25")!

        XCTAssertEqual(balance.sick, expectedSick) // 809.72
        XCTAssertEqual(balance.vacation, expectedVac) // 40.18
        XCTAssertEqual(balance.comp, expectedComp) // 0.25
    }

    func testOfficialBalanceTwoPaydaysForward_NoEntries() {
        // Two paydays from anchor: Feb 20 and Mar 6
        let thirdPayday = DateUtils.makeDate(2026, 3, 6)
        let balance = engine.officialBalance(asOfPayday: thirdPayday, entries: [])

        let expectedSick = Decimal(string: "801.84")! + Decimal(string: "7.88")! * 2
        let expectedVac = Decimal(string: "33.72")! + Decimal(string: "6.46")! * 2

        XCTAssertEqual(balance.sick, expectedSick) // 817.60
        XCTAssertEqual(balance.vacation, expectedVac) // 46.64
    }

    // MARK: - Spec Test Scenario: Feb 6 Payday Verification
    // "Sick: 801.84 + 7.88 = 809.72 (with 0 used) at that payday"
    // This describes what happens at the NEXT payday (anchor +14) because the starting balance
    // is the official AT anchor. So 809.72 would be the official at Feb 20 payday.
    //
    // "Vacation: 35.26 + 6.46 - 8.00 = 33.72 at that payday"
    // This means 33.72 is the RESULT (the starting official balance we have).
    // So the computation yielding 33.72 happened AT anchor. The 35.26 was the prior balance.
    //
    // "Comp: 21.25 - 21.00 = 0.25 at that payday"
    // Similarly, 0.25 is the result at anchor. 21.25 was prior balance.

    func testSpec_SickAt809Point72AtNextPayday() {
        let nextPayday = DateUtils.makeDate(2026, 2, 20)
        let balance = engine.officialBalance(asOfPayday: nextPayday, entries: [])
        // Starting 801.84 + 7.88 accrual = 809.72
        XCTAssertEqual(balance.sick, Decimal(string: "809.72")!)
    }

    // MARK: - Vacation Usage Test Scenario

    func testVacationUsage_ForecastImmediateOfficialDeferred() {
        let userId = UUID()

        // 24 hours of vacation used on Feb 2, 2026
        // Feb 2 falls in Jan 31-Feb 13 period -> payday Feb 20
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 2),
            leaveType: .vacation,
            action: .used,
            hours: Decimal(24)
        )

        // FORECAST as of Feb 5: should reflect the -24 immediately
        let forecastFeb5 = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 5), entries: [entry])
        // Starting vac = 33.72, no payday accrual between anchor (Feb 6) and Feb 5
        // Wait - Feb 5 is BEFORE anchor payday (Feb 6), so we need to think about this.
        // Actually the forecast as of Feb 5: no paydays between anchor and Feb 5 going backward...
        // The starting balance includes anchor payday processing. Feb 5 < anchor Feb 6.
        // So we need to un-apply the anchor payday's accrual.
        // forecastBalance at Feb 5 = 33.72 - 6.46 (un-apply anchor accrual) - 24 (usage) = 3.26
        // Hmm, that doesn't seem right either. Let me reconsider.
        //
        // Actually: The starting balance (33.72) represents the official at anchor payday.
        // The anchor payday's accrual IS included in 33.72 already.
        // For forecast at Feb 5 (before anchor):
        //   - We need to "un-count" the anchor payday's accrual since the payday hasn't happened yet?
        //   - No, forecast includes accruals for paydays <= target date.
        //   - Feb 5 < Feb 6 (anchor), so anchor payday's accrual should NOT be included in forecast.
        //   - But starting balance already includes it.
        //   - So: forecast = 33.72 - 6.46 (remove anchor accrual) - 24 (usage) = 3.26
        //
        // Let me verify with a simpler case: forecast as of Feb 6 (anchor) with no entries
        // = 33.72 (starting includes anchor accrual). That's correct.
        // Forecast as of Feb 5 with no entries = 33.72 - 6.46 = 27.26 (before anchor accrual).
        // This makes sense if we think of it as: what's the vacation balance at end of Feb 5
        // before the payday on Feb 6 processes.

        let expectedForecastVac = Decimal(string: "33.72")! - Decimal(string: "6.46")! - Decimal(24)
        XCTAssertEqual(forecastFeb5.vacation, expectedForecastVac) // 3.26

        // OFFICIAL as of last payday Feb 6: should NOT include the Feb 2 entry
        // because that entry's pay period payday is Feb 20 which hasn't occurred.
        // Wait - "Official as of Feb 6" means official at the anchor payday.
        // The entry is on Feb 2, in the Jan 31-Feb 13 period with payday Feb 20.
        // Since Feb 20 > Feb 6, this entry is NOT posted to the Feb 6 official.
        let officialFeb6 = engine.officialBalance(asOfPayday: anchorPayday, entries: [entry])
        XCTAssertEqual(officialFeb6.vacation, Decimal(string: "33.72")!) // unchanged

        // OFFICIAL as of Feb 20 payday: should include the usage + accrual
        let officialFeb20 = engine.officialBalance(
            asOfPayday: DateUtils.makeDate(2026, 2, 20), entries: [entry])
        // 33.72 + 6.46 accrual - 24 usage = 16.18
        let expectedOfficialVac = Decimal(string: "33.72")! + Decimal(string: "6.46")! - Decimal(24)
        XCTAssertEqual(officialFeb20.vacation, expectedOfficialVac) // 16.18
    }

    // MARK: - Comp Accrual and Usage

    func testCompAccrualAndUsage() {
        let userId = UUID()

        // Comp accrued 12h on Feb 10 (in Jan 31-Feb 13 period, payday Feb 20)
        let accrualEntry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 10),
            leaveType: .comp,
            action: .accrued,
            hours: Decimal(12)
        )

        // Comp used 5h on Feb 12 (same period)
        let usageEntry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 12),
            leaveType: .comp,
            action: .used,
            hours: Decimal(5)
        )

        let entries = [accrualEntry, usageEntry]

        // Forecast as of Feb 15: includes both entries
        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 15), entries: entries)
        // 0.25 + 12 - 5 = 7.25
        XCTAssertEqual(forecast.comp, Decimal(string: "7.25")!)

        // Official at Feb 6 (anchor): neither entry posted yet (they're in Feb 20 pay period)
        let officialFeb6 = engine.officialBalance(asOfPayday: anchorPayday, entries: entries)
        XCTAssertEqual(officialFeb6.comp, Decimal(string: "0.25")!)

        // Official at Feb 20: both entries posted
        let officialFeb20 = engine.officialBalance(
            asOfPayday: DateUtils.makeDate(2026, 2, 20), entries: entries)
        XCTAssertEqual(officialFeb20.comp, Decimal(string: "7.25")!)
    }

    // MARK: - Adjustment Tests

    func testPositiveAdjustment() {
        let userId = UUID()
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 3),
            leaveType: .sick,
            action: .adjustment,
            hours: Decimal(10),
            adjustmentSign: .positive
        )

        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 5), entries: [entry])
        // Starting sick = 801.84, un-apply anchor accrual = -7.88, + 10 adjustment
        let expected = Decimal(string: "801.84")! - Decimal(string: "7.88")! + Decimal(10)
        XCTAssertEqual(forecast.sick, expected) // 803.96
    }

    func testNegativeAdjustment() {
        let userId = UUID()
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 3),
            leaveType: .sick,
            action: .adjustment,
            hours: Decimal(10),
            adjustmentSign: .negative
        )

        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 5), entries: [entry])
        let expected = Decimal(string: "801.84")! - Decimal(string: "7.88")! - Decimal(10)
        XCTAssertEqual(forecast.sick, expected) // 783.96
    }

    // MARK: - Posted Status Tests

    func testPostedStatus() {
        let userId = UUID()

        // Entry on Jan 20 (in anchor pay period, payday Feb 6)
        let postedEntry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 1, 20),
            leaveType: .vacation,
            action: .used,
            hours: Decimal(8)
        )

        // Entry on Feb 10 (payday Feb 20)
        let pendingEntry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 10),
            leaveType: .vacation,
            action: .used,
            hours: Decimal(8)
        )

        // As of Feb 10, the last payday is Feb 6
        // Jan 20 entry's payday is Feb 6 <= Feb 6, so it's posted
        let posted = engine.isPosted(entry: postedEntry, asOf: DateUtils.makeDate(2026, 2, 10))
        XCTAssertTrue(posted)

        // Feb 10 entry's payday is Feb 20 > Feb 6, so it's pending
        let pending = engine.isPosted(entry: pendingEntry, asOf: DateUtils.makeDate(2026, 2, 10))
        XCTAssertFalse(pending)
    }

    // MARK: - Soft Delete

    func testSoftDeletedEntriesExcluded() {
        let userId = UUID()
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 10),
            leaveType: .comp,
            action: .accrued,
            hours: Decimal(12),
            deletedAt: Date() // soft deleted
        )

        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 15), entries: [entry])
        // Should NOT include the deleted entry
        XCTAssertEqual(forecast.comp, Decimal(string: "0.25")!)
    }

    // MARK: - Backward Balance Computation

    func testOfficialBalanceAtPreviousPayday() {
        // Previous payday before anchor: Jan 23, 2026
        let prevPayday = DateUtils.makeDate(2026, 1, 23)
        let balance = engine.officialBalance(asOfPayday: prevPayday, entries: [])

        // Going backward from anchor:
        // At anchor: sick=801.84, vac=33.72, comp=0.25
        // Un-apply anchor accrual: sick -= 7.88 = 793.96, vac -= 6.46 = 27.26
        XCTAssertEqual(balance.sick, Decimal(string: "793.96")!)
        XCTAssertEqual(balance.vacation, Decimal(string: "27.26")!)
        XCTAssertEqual(balance.comp, Decimal(string: "0.25")!)
    }

    // MARK: - Multiple Entries Across Periods

    func testMultipleEntriesAcrossPayPeriods() {
        let userId = UUID()

        let entries: [LeaveEntry] = [
            // Comp accrued 10h on Jan 20 (anchor period, payday Feb 6)
            LeaveEntry(userId: userId, date: DateUtils.makeDate(2026, 1, 20),
                       leaveType: .comp, action: .accrued, hours: Decimal(10)),
            // Vacation used 8h on Feb 3 (Feb 20 pay period)
            LeaveEntry(userId: userId, date: DateUtils.makeDate(2026, 2, 3),
                       leaveType: .vacation, action: .used, hours: Decimal(8)),
            // Sick used 5h on Feb 15 (Feb 20 pay period: Jan 31-Feb 13... wait Feb 15 is next)
            // Actually Feb 15 is in Feb 14-27 period, payday Mar 6
            LeaveEntry(userId: userId, date: DateUtils.makeDate(2026, 2, 15),
                       leaveType: .sick, action: .used, hours: Decimal(5)),
        ]

        // Official at anchor (Feb 6):
        // Comp: 0.25 + 10 (anchor period entry) = 10.25
        // Vac: 33.72 (Feb 3 entry is in Feb 20 period, not yet posted)
        // Sick: 801.84 (Feb 15 entry is in Mar 6 period, not yet posted)
        let officialFeb6 = engine.officialBalance(asOfPayday: anchorPayday, entries: entries)
        XCTAssertEqual(officialFeb6.comp, Decimal(string: "10.25")!)
        XCTAssertEqual(officialFeb6.vacation, Decimal(string: "33.72")!)
        XCTAssertEqual(officialFeb6.sick, Decimal(string: "801.84")!)

        // Official at Feb 20:
        // Comp: 10.25 (no new comp entries in Feb 20 period)
        // Vac: 33.72 + 6.46 (accrual) - 8 (usage) = 32.18
        // Sick: 801.84 + 7.88 (accrual) = 809.72 (Feb 15 entry is Mar 6 period)
        let officialFeb20 = engine.officialBalance(
            asOfPayday: DateUtils.makeDate(2026, 2, 20), entries: entries)
        XCTAssertEqual(officialFeb20.comp, Decimal(string: "10.25")!)
        XCTAssertEqual(officialFeb20.vacation, Decimal(string: "32.18")!)
        XCTAssertEqual(officialFeb20.sick, Decimal(string: "809.72")!)

        // Official at Mar 6:
        // Comp: 10.25
        // Vac: 32.18 + 6.46 = 38.64
        // Sick: 809.72 + 7.88 - 5 = 812.60
        let officialMar6 = engine.officialBalance(
            asOfPayday: DateUtils.makeDate(2026, 3, 6), entries: entries)
        XCTAssertEqual(officialMar6.comp, Decimal(string: "10.25")!)
        XCTAssertEqual(officialMar6.vacation, Decimal(string: "38.64")!)
        XCTAssertEqual(officialMar6.sick, Decimal(string: "812.60")!)
    }

    // MARK: - Forecast Balance Tests

    func testForecastAtAnchorPayday() {
        // With no entries, forecast at anchor should equal starting balance
        let forecast = engine.forecastBalance(asOf: anchorPayday, entries: [])
        XCTAssertEqual(forecast.sick, Decimal(string: "801.84")!)
        XCTAssertEqual(forecast.vacation, Decimal(string: "33.72")!)
        XCTAssertEqual(forecast.comp, Decimal(string: "0.25")!)
    }

    func testForecastAtFutureDate() {
        // Forecast at Feb 25 (after Feb 20 payday)
        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 25), entries: [])
        // One payday accrual (Feb 20) since anchor
        XCTAssertEqual(forecast.sick, Decimal(string: "801.84")! + Decimal(string: "7.88")!)
        XCTAssertEqual(forecast.vacation, Decimal(string: "33.72")! + Decimal(string: "6.46")!)
    }

    func testForecastWithEntries() {
        let userId = UUID()
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.makeDate(2026, 2, 10),
            leaveType: .vacation,
            action: .used,
            hours: Decimal(16)
        )

        // Forecast at Feb 25: includes Feb 20 accrual + Feb 10 usage
        let forecast = engine.forecastBalance(
            asOf: DateUtils.makeDate(2026, 2, 25), entries: [entry])
        let expected = Decimal(string: "33.72")! + Decimal(string: "6.46")! - Decimal(16)
        XCTAssertEqual(forecast.vacation, expected) // 24.18
    }
}

// MARK: - Pay Period Service Additional Tests

final class PayPeriodServiceTests: XCTestCase {
    let anchor = DateUtils.makeDate(2026, 2, 6)

    func testPaydaysInRange() {
        let start = DateUtils.makeDate(2026, 1, 1)
        let end = DateUtils.makeDate(2026, 3, 31)
        let paydays = PayPeriodService.paydays(from: start, to: end, anchorPayday: anchor)

        // Jan 9, Jan 23, Feb 6, Feb 20, Mar 6, Mar 20
        XCTAssertEqual(paydays.count, 6)
        XCTAssertTrue(DateUtils.isSameDay(paydays[0], DateUtils.makeDate(2026, 1, 9)))
        XCTAssertTrue(DateUtils.isSameDay(paydays[1], DateUtils.makeDate(2026, 1, 23)))
        XCTAssertTrue(DateUtils.isSameDay(paydays[2], DateUtils.makeDate(2026, 2, 6)))
        XCTAssertTrue(DateUtils.isSameDay(paydays[3], DateUtils.makeDate(2026, 2, 20)))
        XCTAssertTrue(DateUtils.isSameDay(paydays[4], DateUtils.makeDate(2026, 3, 6)))
        XCTAssertTrue(DateUtils.isSameDay(paydays[5], DateUtils.makeDate(2026, 3, 20)))
    }

    func testPayPeriodBoundaries() {
        // First day of anchor pay period
        let firstDay = DateUtils.makeDate(2026, 1, 17)
        let payday1 = PayPeriodService.paydayFor(date: firstDay, anchorPayday: anchor)
        XCTAssertTrue(DateUtils.isSameDay(payday1, anchor))

        // Last day of anchor pay period
        let lastDay = DateUtils.makeDate(2026, 1, 30)
        let payday2 = PayPeriodService.paydayFor(date: lastDay, anchorPayday: anchor)
        XCTAssertTrue(DateUtils.isSameDay(payday2, anchor))

        // Day after period end should be in next period
        let nextPeriodDay = DateUtils.makeDate(2026, 1, 31)
        let payday3 = PayPeriodService.paydayFor(date: nextPeriodDay, anchorPayday: anchor)
        XCTAssertTrue(DateUtils.isSameDay(payday3, DateUtils.makeDate(2026, 2, 20)))
    }
}
