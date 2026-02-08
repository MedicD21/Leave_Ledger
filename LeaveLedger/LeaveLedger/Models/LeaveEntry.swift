import Foundation
import SwiftData

@Model
final class LeaveEntry {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var date: Date
    var leaveTypeRaw: String
    var actionRaw: String
    var hours: Decimal
    var adjustmentSignRaw: String?
    var notes: String?
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool

    var leaveType: LeaveType {
        get { LeaveType(rawValue: leaveTypeRaw) ?? .comp }
        set { leaveTypeRaw = newValue.rawValue }
    }

    var action: LeaveAction {
        get { LeaveAction(rawValue: actionRaw) ?? .used }
        set { actionRaw = newValue.rawValue }
    }

    var adjustmentSign: AdjustmentSign? {
        get { adjustmentSignRaw.flatMap { AdjustmentSign(rawValue: $0) } }
        set { adjustmentSignRaw = newValue?.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    /// Returns the signed hours value based on action type.
    /// Accrued = positive, Used = negative, Adjustment = depends on sign.
    var signedHours: Decimal {
        switch action {
        case .accrued:
            return hours
        case .used:
            return -hours
        case .adjustment:
            if let sign = adjustmentSign {
                return sign == .positive ? hours : -hours
            }
            return hours
        }
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date,
        leaveType: LeaveType,
        action: LeaveAction,
        hours: Decimal,
        adjustmentSign: AdjustmentSign? = nil,
        notes: String? = nil,
        source: EntrySource = .user,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        isDirty: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.leaveTypeRaw = leaveType.rawValue
        self.actionRaw = action.rawValue
        self.hours = hours
        self.adjustmentSignRaw = adjustmentSign?.rawValue
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isDirty = isDirty
    }
}

extension LeaveEntry {
    var isDeleted: Bool { deletedAt != nil }

    var dateOnly: Date {
        Calendar.current.startOfDay(for: date)
    }

    var chipLabel: String {
        let h = NSDecimalNumber(decimal: hours).doubleValue
        let hoursStr = String(format: "%.2f", h)
        switch action {
        case .accrued:
            return "\(leaveType.displayName) +\(hoursStr)h"
        case .used:
            return "\(leaveType.displayName) -\(hoursStr)h"
        case .adjustment:
            let sign = adjustmentSign == .negative ? "-" : "+"
            return "\(leaveType.displayName) Adj \(sign)\(hoursStr)h"
        }
    }
}
