import Foundation
import SwiftData

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
    }
}
