import Foundation
import Observation
import SwiftData
import OSLog

@Observable
final class AppViewModel {
    let store: DataStore
    let supabaseService: SupabaseService
    private(set) var engine: BalanceEngine

    var selectedDate: Date = Date()
    var displayedMonth: Date = Date()
    var forecastMode: ForecastMode = .nextPayday

    var entries: [LeaveEntry] = []
    var profile: UserProfile!

    var officialBalance: BalanceSnapshot = .zero
    var forecastBalance: BalanceSnapshot = .zero
    var lastPaydayDate: Date = Date()
    var forecastAsOfDate: Date = Date()

    enum ForecastMode: String, CaseIterable {
        case today = "Today"
        case selectedDay = "Selected Day"
        case nextPayday = "Next Payday"
    }

    init(store: DataStore? = nil) {
        let dataStore = store ?? DataStore()
        self.store = dataStore
        let userId = KeychainService.getUserId()
        self.supabaseService = SupabaseService(userId: userId)
        self.engine = BalanceEngine()
        self.profile = dataStore.getOrCreateProfile()
        self.engine = buildEngine(from: profile)
        refreshData()
    }

    private func buildEngine(from profile: UserProfile) -> BalanceEngine {
        BalanceEngine(
            anchorPayday: profile.anchorPayday,
            compStart: profile.compStartBalance,
            vacStart: profile.vacStartBalance,
            sickStart: profile.sickStartBalance,
            vacAccrualRate: profile.vacAccrualRate,
            sickAccrualRate: profile.sickAccrualRate
        )
    }

    func refreshData() {
        profile = store.getOrCreateProfile()
        engine = buildEngine(from: profile)
        entries = store.allEntries()
        recalculateBalances()
    }

    func recalculateBalances() {
        let today = Date()
        lastPaydayDate = engine.lastPayday(asOf: today)
        officialBalance = engine.currentOfficialBalance(asOf: today, entries: entries)

        switch forecastMode {
        case .today:
            forecastAsOfDate = today
        case .selectedDay:
            forecastAsOfDate = selectedDate
        case .nextPayday:
            forecastAsOfDate = PayPeriodService.nextPaydayOnOrAfter(date: today, anchorPayday: profile.anchorPayday)
        }

        forecastBalance = engine.forecastBalance(asOf: forecastAsOfDate, entries: entries)
    }

    // MARK: - Entry CRUD

    func addEntry(
        date: Date,
        leaveType: LeaveType,
        action: LeaveAction,
        hours: Decimal,
        adjustmentSign: AdjustmentSign? = nil,
        notes: String? = nil
    ) {
        let userId = KeychainService.getUserId()
        let roundedHours = profile.enforceQuarterIncrements ? roundToQuarter(hours) : hours
        let entry = LeaveEntry(
            userId: userId,
            date: DateUtils.startOfDay(date),
            leaveType: leaveType,
            action: action,
            hours: roundedHours,
            adjustmentSign: adjustmentSign,
            notes: notes
        )
        store.addEntry(entry)
        refreshData()
    }

    func updateEntry(_ entry: LeaveEntry, date: Date, leaveType: LeaveType,
                     action: LeaveAction, hours: Decimal,
                     adjustmentSign: AdjustmentSign?, notes: String?) {
        let roundedHours = profile.enforceQuarterIncrements ? roundToQuarter(hours) : hours
        store.updateEntry(entry) { e in
            e.date = DateUtils.startOfDay(date)
            e.leaveType = leaveType
            e.action = action
            e.hours = roundedHours
            e.adjustmentSign = adjustmentSign
            e.notes = notes
        }
        refreshData()
    }

    func deleteEntry(_ entry: LeaveEntry) {
        store.softDelete(entry)
        refreshData()
    }

    // MARK: - Calendar helpers

    func entriesForDate(_ date: Date) -> [LeaveEntry] {
        let dayStart = DateUtils.startOfDay(date)
        return entries.filter { DateUtils.isSameDay($0.date, dayStart) }
    }

    func isPayday(_ date: Date) -> Bool {
        PayPeriodService.isPayday(date, anchorPayday: profile.anchorPayday)
    }

    func forecastForDate(_ date: Date) -> BalanceSnapshot {
        engine.forecastBalance(asOf: date, entries: entries)
    }

    func payPeriodFor(date: Date) -> PayPeriod {
        let payday = PayPeriodService.paydayFor(date: date, anchorPayday: profile.anchorPayday)
        return PayPeriodService.payPeriod(forPayday: payday)
    }

    func isPosted(_ entry: LeaveEntry) -> Bool {
        engine.isPosted(entry: entry, asOf: Date())
    }

    func entriesForLeaveType(_ type: LeaveType) -> [LeaveEntry] {
        store.entries(forLeaveType: type.rawValue)
    }

    // MARK: - Navigation

    func goToNextMonth() {
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) else {
            os_log(.error, log: Logger.viewModel, "Failed to calculate next month from %@", displayedMonth as CVarArg)
            return
        }
        displayedMonth = nextMonth
        recalculateBalances()
    }

    func goToPreviousMonth() {
        guard let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) else {
            os_log(.error, log: Logger.viewModel, "Failed to calculate previous month from %@", displayedMonth as CVarArg)
            return
        }
        displayedMonth = previousMonth
        recalculateBalances()
    }

    func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
        recalculateBalances()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        if forecastMode == .selectedDay {
            recalculateBalances()
        }
    }

    func setForecastMode(_ mode: ForecastMode) {
        forecastMode = mode
        recalculateBalances()
    }

    // MARK: - Sync

    func syncWithSupabase() {
        supabaseService.sync(store: store)
    }

    // MARK: - Settings

    func updateAnchorPayday(_ date: Date) {
        store.updateProfile { p in
            p.anchorPayday = date
        }
        refreshData()
    }

    func updateStartingBalances(comp: Decimal, vac: Decimal, sick: Decimal) {
        store.updateProfile { p in
            p.compStartBalance = comp
            p.vacStartBalance = vac
            p.sickStartBalance = sick
        }
        refreshData()
    }

    func updateAccrualRates(vac: Decimal, sick: Decimal) {
        store.updateProfile { p in
            p.vacAccrualRate = vac
            p.sickAccrualRate = sick
        }
        refreshData()
    }

    func toggleQuarterIncrements() {
        store.updateProfile { p in
            p.enforceQuarterIncrements.toggle()
        }
        refreshData()
    }

    func regenerateICalToken() {
        store.updateProfile { p in
            p.icalToken = UUID().uuidString
        }
        refreshData()
        // Immediately sync to Supabase to invalidate old token
        syncWithSupabase()
    }

    // MARK: - Utilities

    private func roundToQuarter(_ value: Decimal) -> Decimal {
        let nsValue = NSDecimalNumber(decimal: value)
        let multiplied = nsValue.multiplying(by: 4)
        let rounded = multiplied.rounding(accordingToBehavior:
            NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )
        return rounded.dividing(by: 4).decimalValue
    }
}
