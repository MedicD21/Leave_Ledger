import Foundation

struct PayPeriod: Equatable, Hashable {
    let start: Date
    let end: Date
    let payday: Date

    var description: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }
}

struct BalanceSnapshot: Equatable {
    var comp: Decimal
    var vacation: Decimal
    var sick: Decimal

    static var zero: BalanceSnapshot {
        BalanceSnapshot(comp: 0, vacation: 0, sick: 0)
    }

    mutating func apply(leaveType: LeaveType, signedHours: Decimal) {
        switch leaveType {
        case .comp: comp += signedHours
        case .vacation: vacation += signedHours
        case .sick: sick += signedHours
        }
    }

    mutating func applyAccruals(vacRate: Decimal, sickRate: Decimal) {
        vacation += vacRate
        sick += sickRate
    }
}
