import Foundation

enum LeaveType: String, Codable, CaseIterable, Identifiable {
    case comp
    case vacation
    case sick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comp: return "Comp"
        case .vacation: return "Vacation"
        case .sick: return "Sick"
        }
    }
}

enum LeaveAction: String, Codable, CaseIterable, Identifiable {
    case accrued
    case used
    case adjustment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accrued: return "Accrued"
        case .used: return "Used"
        case .adjustment: return "Adjustment"
        }
    }
}

enum AdjustmentSign: String, Codable {
    case positive
    case negative
}

enum EntrySource: String, Codable {
    case user
    case system
}
