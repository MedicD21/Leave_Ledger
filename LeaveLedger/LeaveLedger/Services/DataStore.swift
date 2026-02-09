import Foundation
import SwiftData
import Observation
import OSLog

@Observable
final class DataStore {
    let container: ModelContainer
    private let context: ModelContext

    init() {
        let schema = Schema([LeaveEntry.self, UserProfile.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // For testing
    init(inMemory: Bool) {
        let schema = Schema([LeaveEntry.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Profile

    func getOrCreateProfile() -> UserProfile {
        let deviceUserId = KeychainService.getUserId()
        let descriptor = FetchDescriptor<UserProfile>()

        do {
            let profiles = try context.fetch(descriptor)
            if let profile = profiles.first {
                if profile.id != deviceUserId {
                    profile.id = deviceUserId
                    profile.updatedAt = Date()
                    do {
                        try context.save()
                    } catch {
                        os_log(.error, log: Logger.dataStore, "Failed to save profile ID update: %@", error.localizedDescription)
                    }
                }
                return profile
            }
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch profiles: %@", error.localizedDescription)
        }

        let profile = UserProfile(id: deviceUserId)
        context.insert(profile)
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save new profile: %@", error.localizedDescription)
        }
        return profile
    }

    func updateProfile(_ update: (UserProfile) -> Void) {
        let profile = getOrCreateProfile()
        update(profile)
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save profile update: %@", error.localizedDescription)
        }
    }

    // MARK: - Entries

    func allEntries() -> [LeaveEntry] {
        var descriptor = FetchDescriptor<LeaveEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.predicate = #Predicate<LeaveEntry> { $0.deletedAt == nil }
        do {
            return try context.fetch(descriptor)
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch all entries: %@", error.localizedDescription)
            return []
        }
    }

    func entries(for date: Date) -> [LeaveEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            os_log(.error, log: Logger.dataStore, "Failed to calculate end date for entries query")
            return []
        }
        var descriptor = FetchDescriptor<LeaveEntry>(
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.predicate = #Predicate<LeaveEntry> {
            $0.date >= start && $0.date < end && $0.deletedAt == nil
        }
        do {
            return try context.fetch(descriptor)
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch entries for date: %@", error.localizedDescription)
            return []
        }
    }

    func entries(from start: Date, to end: Date) -> [LeaveEntry] {
        let startDay = Calendar.current.startOfDay(for: start)
        guard let endDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) else {
            os_log(.error, log: Logger.dataStore, "Failed to calculate end date for date range query")
            return []
        }
        var descriptor = FetchDescriptor<LeaveEntry>(
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.predicate = #Predicate<LeaveEntry> {
            $0.date >= startDay && $0.date < endDay && $0.deletedAt == nil
        }
        do {
            return try context.fetch(descriptor)
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch entries for date range: %@", error.localizedDescription)
            return []
        }
    }

    func entries(forLeaveType type: String) -> [LeaveEntry] {
        var descriptor = FetchDescriptor<LeaveEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.predicate = #Predicate<LeaveEntry> {
            $0.leaveTypeRaw == type && $0.deletedAt == nil
        }
        do {
            return try context.fetch(descriptor)
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch entries for leave type %@: %@", type, error.localizedDescription)
            return []
        }
    }

    func addEntry(_ entry: LeaveEntry) {
        context.insert(entry)
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save new entry: %@", error.localizedDescription)
        }
    }

    func updateEntry(_ entry: LeaveEntry, update: (LeaveEntry) -> Void) {
        update(entry)
        entry.updatedAt = Date()
        entry.isDirty = true
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save entry update: %@", error.localizedDescription)
        }
    }

    func softDelete(_ entry: LeaveEntry) {
        entry.deletedAt = Date()
        entry.updatedAt = Date()
        entry.isDirty = true
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save soft delete: %@", error.localizedDescription)
        }
    }

    func dirtyEntries() -> [LeaveEntry] {
        var descriptor = FetchDescriptor<LeaveEntry>()
        descriptor.predicate = #Predicate<LeaveEntry> { $0.isDirty == true }
        do {
            return try context.fetch(descriptor)
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to fetch dirty entries: %@", error.localizedDescription)
            return []
        }
    }

    func markClean(_ entry: LeaveEntry) {
        entry.isDirty = false
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to mark entry as clean: %@", error.localizedDescription)
        }
    }

    func save() {
        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save context: %@", error.localizedDescription)
        }
    }

    // MARK: - Sync support

    func upsertFromRemote(_ remoteEntries: [RemoteLeaveEntry]) {
        for remote in remoteEntries {
            let idToFind = remote.id
            var descriptor = FetchDescriptor<LeaveEntry>()
            descriptor.predicate = #Predicate<LeaveEntry> { $0.id == idToFind }

            do {
                let results = try context.fetch(descriptor)
                if let existing = results.first {
                    // Last-write-wins
                    if remote.updatedAt > existing.updatedAt {
                        existing.date = remote.date
                        existing.leaveTypeRaw = remote.leaveType
                        existing.actionRaw = remote.action
                        existing.hours = remote.hours
                        existing.adjustmentSignRaw = remote.adjustmentSign
                        existing.notes = remote.notes
                        existing.sourceRaw = remote.source
                        existing.updatedAt = remote.updatedAt
                        existing.deletedAt = remote.deletedAt
                        existing.isDirty = false
                    }
                } else {
                    let entry = LeaveEntry(
                        id: remote.id,
                        userId: remote.userId,
                        date: remote.date,
                        leaveType: LeaveType(rawValue: remote.leaveType) ?? .comp,
                        action: LeaveAction(rawValue: remote.action) ?? .used,
                        hours: remote.hours,
                        adjustmentSign: remote.adjustmentSign.flatMap { AdjustmentSign(rawValue: $0) },
                        notes: remote.notes,
                        source: EntrySource(rawValue: remote.source) ?? .user,
                        createdAt: remote.createdAt,
                        updatedAt: remote.updatedAt,
                        deletedAt: remote.deletedAt,
                        isDirty: false
                    )
                    context.insert(entry)
                }
            } catch {
                os_log(.error, log: Logger.dataStore, "Failed to fetch entry for upsert (id: %@): %@", idToFind.uuidString, error.localizedDescription)
            }
        }

        do {
            try context.save()
        } catch {
            os_log(.error, log: Logger.dataStore, "Failed to save remote entries: %@", error.localizedDescription)
        }
    }
}

// DTO for remote entries
struct RemoteLeaveEntry: Codable {
    let id: UUID
    let userId: UUID
    let date: Date
    let leaveType: String
    let action: String
    let hours: Decimal
    let adjustmentSign: String?
    let notes: String?
    let source: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case leaveType = "leave_type"
        case action
        case hours
        case adjustmentSign = "adjustment_sign"
        case notes
        case source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    // Custom decoder to handle date-only format for 'date' field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        leaveType = try container.decode(String.self, forKey: .leaveType)
        action = try container.decode(String.self, forKey: .action)
        hours = try container.decode(Decimal.self, forKey: .hours)
        adjustmentSign = try container.decodeIfPresent(String.self, forKey: .adjustmentSign)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        source = try container.decode(String.self, forKey: .source)

        // Helper function to parse ISO8601 dates with or without fractional seconds
        func parseISO8601(_ string: String) -> Date? {
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: string) {
                return date
            }

            let formatterWithoutFractional = ISO8601DateFormatter()
            formatterWithoutFractional.formatOptions = [.withInternetDateTime]
            return formatterWithoutFractional.date(from: string)
        }

        // Decode timestamp fields using ISO8601
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let createdAtDate = parseISO8601(createdAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Invalid ISO8601 date format")
        }
        createdAt = createdAtDate

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        guard let updatedAtDate = parseISO8601(updatedAtString) else {
            throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "Invalid ISO8601 date format")
        }
        updatedAt = updatedAtDate

        if let deletedAtString = try container.decodeIfPresent(String.self, forKey: .deletedAt) {
            deletedAt = parseISO8601(deletedAtString)
        } else {
            deletedAt = nil
        }

        // Decode date-only field using a simple date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        let dateString = try container.decode(String.self, forKey: .date)
        guard let dateValue = dateFormatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Invalid date format, expected yyyy-MM-dd")
        }
        date = dateValue
    }
}
