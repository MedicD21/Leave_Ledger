import SwiftUI
import SwiftData

@Model
final class DateNote {
    var id: UUID
    var userId: UUID
    var date: Date
    var title: String
    var noteText: String
    var colorHex: String  // Store color as hex string for serialization
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date,
        title: String,
        noteText: String,
        colorHex: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.title = title
        self.noteText = noteText
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // Helper computed property to get Color from hex
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

// Extension to convert Color to/from hex string
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else {
            return "0000FF" // Default to blue
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
