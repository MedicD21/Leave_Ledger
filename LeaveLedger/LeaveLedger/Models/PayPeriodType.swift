import Foundation

/// Pay period configuration types
enum PayPeriodType: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case semiMonthly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Bi-weekly (every 2 weeks)"
        case .semiMonthly:
            return "Semi-monthly (twice per month)"
        case .monthly:
            return "Monthly"
        }
    }

    var intervalDays: Int {
        switch self {
        case .weekly:
            return 7
        case .biweekly:
            return 14
        case .semiMonthly:
            return 15  // Approximate - actual dates vary
        case .monthly:
            return 30  // Approximate - actual dates vary
        }
    }

    var description: String {
        switch self {
        case .weekly:
            return "Pay period is 7 days, payday every week"
        case .biweekly:
            return "Pay period is 14 days, payday every 2 weeks"
        case .semiMonthly:
            return "Payday twice per month (typically 1st and 15th)"
        case .monthly:
            return "Payday once per month"
        }
    }
}
