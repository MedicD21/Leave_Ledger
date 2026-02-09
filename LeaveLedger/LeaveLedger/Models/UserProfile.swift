import Foundation
import SwiftData
import OSLog

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var anchorPayday: Date
    var sickStartBalance: Decimal
    var vacStartBalance: Decimal
    var compStartBalance: Decimal
    var sickAccrualRate: Decimal
    var vacAccrualRate: Decimal
    var enforceQuarterIncrements: Bool
    var icalToken: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        anchorPayday: Date = DateUtils.makeDate(2026, 2, 6),
        sickStartBalance: Decimal = Decimal(string: "801.84")!,
        vacStartBalance: Decimal = Decimal(string: "33.72")!,
        compStartBalance: Decimal = Decimal(string: "0.25")!,
        sickAccrualRate: Decimal = Decimal(string: "7.88")!,
        vacAccrualRate: Decimal = Decimal(string: "6.46")!,
        enforceQuarterIncrements: Bool = true,
        icalToken: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.anchorPayday = anchorPayday
        self.sickStartBalance = sickStartBalance
        self.vacStartBalance = vacStartBalance
        self.compStartBalance = compStartBalance
        self.sickAccrualRate = sickAccrualRate
        self.vacAccrualRate = vacAccrualRate
        self.enforceQuarterIncrements = enforceQuarterIncrements
        self.icalToken = icalToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        // Validate anchor payday on initialization
        validateAnchorPayday()
    }

    /// Validates that the anchor payday is reasonable.
    /// Logs a warning if the anchor payday is not a Friday, as the pay period
    /// model assumes biweekly Friday paydays.
    func validateAnchorPayday() {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: anchorPayday)

        // Weekday: 1 = Sunday, 6 = Friday
        if weekday != 6 {
            os_log(.info, log: Logger.general,
                   "Anchor payday is not a Friday (weekday: %d). The pay period model assumes biweekly Friday paydays.",
                   weekday)
        }

        // Validate that balances are not negative
        if sickStartBalance < 0 || vacStartBalance < 0 || compStartBalance < 0 {
            os_log(.error, log: Logger.general, "Starting balance contains negative values")
        }

        // Validate that accrual rates are not negative
        if sickAccrualRate < 0 || vacAccrualRate < 0 {
            os_log(.error, log: Logger.general, "Accrual rate contains negative values")
        }
    }
}
