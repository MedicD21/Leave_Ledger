import Foundation
import OSLog

// MARK: - Backup Data Models

/// Complete backup structure containing all user data
struct BackupData: Codable {
    let version: String
    let exportDate: Date
    let profile: BackupProfile
    let entries: [BackupEntry]

    static let currentVersion = "1.0"
}

/// Serializable user profile data
struct BackupProfile: Codable {
    let id: String
    let anchorPayday: String
    let sickStartBalance: Double
    let vacStartBalance: Double
    let compStartBalance: Double
    let sickAccrualRate: Double
    let vacAccrualRate: Double
    let enforceQuarterIncrements: Bool
    let icalToken: String
    let createdAt: String
    let updatedAt: String

    init(from profile: UserProfile) {
        self.id = profile.id.uuidString
        self.anchorPayday = DateUtils.isoDate(profile.anchorPayday)
        self.sickStartBalance = NSDecimalNumber(decimal: profile.sickStartBalance).doubleValue
        self.vacStartBalance = NSDecimalNumber(decimal: profile.vacStartBalance).doubleValue
        self.compStartBalance = NSDecimalNumber(decimal: profile.compStartBalance).doubleValue
        self.sickAccrualRate = NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue
        self.vacAccrualRate = NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue
        self.enforceQuarterIncrements = profile.enforceQuarterIncrements
        self.icalToken = profile.icalToken
        self.createdAt = ISO8601DateFormatter().string(from: profile.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: profile.updatedAt)
    }
}

/// Serializable leave entry data
struct BackupEntry: Codable {
    let id: String
    let userId: String
    let date: String
    let leaveType: String
    let action: String
    let hours: Double
    let adjustmentSign: String?
    let notes: String?
    let source: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    init(from entry: LeaveEntry) {
        self.id = entry.id.uuidString
        self.userId = entry.userId.uuidString
        self.date = DateUtils.isoDate(entry.date)
        self.leaveType = entry.leaveTypeRaw
        self.action = entry.actionRaw
        self.hours = NSDecimalNumber(decimal: entry.hours).doubleValue
        self.adjustmentSign = entry.adjustmentSignRaw
        self.notes = entry.notes
        self.source = entry.sourceRaw
        self.createdAt = ISO8601DateFormatter().string(from: entry.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: entry.updatedAt)
        self.deletedAt = entry.deletedAt.map { ISO8601DateFormatter().string(from: $0) }
    }
}

// MARK: - Import/Export Service

/// Handles exporting and importing complete app data backups
struct ImportExportService {

    // MARK: - Export

    /// Exports all user data to a JSON backup file
    /// - Parameters:
    ///   - profile: The user profile to export
    ///   - entries: All leave entries to export
    /// - Returns: URL to the exported backup file, or nil if export failed
    func exportBackup(profile: UserProfile, entries: [LeaveEntry]) -> URL? {
        os_log(.info, log: Logger.export, "Starting backup export")

        let backupData = BackupData(
            version: BackupData.currentVersion,
            exportDate: Date(),
            profile: BackupProfile(from: profile),
            entries: entries.map { BackupEntry(from: $0) }
        )

        guard let jsonData = try? JSONEncoder().encode(backupData) else {
            os_log(.error, log: Logger.export, "Failed to encode backup data")
            return nil
        }

        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            os_log(.error, log: Logger.export, "Failed to access documents directory")
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let fileURL = documentsDir.appendingPathComponent("LeaveLedger_Backup_\(dateString).json")

        do {
            try jsonData.write(to: fileURL)

            // Set file attributes for sharing
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = fileURL
            try mutableURL.setResourceValues(resourceValues)

            os_log(.info, log: Logger.export, "Backup export successful: %@", fileURL.path)
            return fileURL
        } catch {
            os_log(.error, log: Logger.export, "Failed to write backup file: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Import

    /// Import result with details about what was imported
    struct ImportResult {
        let success: Bool
        let profileImported: Bool
        let entriesImported: Int
        let error: String?
    }

    /// Imports user data from a backup file
    /// - Parameters:
    ///   - url: URL to the backup JSON file
    ///   - dataStore: DataStore to import data into
    /// - Returns: ImportResult with details about the import
    func importBackup(from url: URL, into dataStore: DataStore) -> ImportResult {
        os_log(.info, log: Logger.export, "Starting backup import from: %@", url.path)

        // Read and decode backup file
        guard let jsonData = try? Data(contentsOf: url) else {
            os_log(.error, log: Logger.export, "Failed to read backup file")
            return ImportResult(success: false, profileImported: false, entriesImported: 0, error: "Failed to read backup file")
        }

        let decoder = JSONDecoder()
        guard let backupData = try? decoder.decode(BackupData.self, from: jsonData) else {
            os_log(.error, log: Logger.export, "Failed to decode backup file")
            return ImportResult(success: false, profileImported: false, entriesImported: 0, error: "Invalid backup file format")
        }

        os_log(.info, log: Logger.export, "Backup version: %@, Export date: %@", backupData.version, backupData.exportDate.description)

        // Import profile
        let profileImported = importProfile(backupData.profile, into: dataStore)

        // Import entries
        let entriesImported = importEntries(backupData.entries, into: dataStore)

        let success = profileImported && entriesImported > 0
        os_log(.info, log: Logger.export, "Import completed: profile=%d, entries=%d", profileImported ? 1 : 0, entriesImported)

        return ImportResult(
            success: success,
            profileImported: profileImported,
            entriesImported: entriesImported,
            error: success ? nil : "Import completed with errors"
        )
    }

    // MARK: - Private Helpers

    private func importProfile(_ backupProfile: BackupProfile, into dataStore: DataStore) -> Bool {
        guard let profileId = UUID(uuidString: backupProfile.id),
              let anchorPayday = DateUtils.parseISO(backupProfile.anchorPayday),
              let createdAt = ISO8601DateFormatter().date(from: backupProfile.createdAt),
              let updatedAt = ISO8601DateFormatter().date(from: backupProfile.updatedAt) else {
            os_log(.error, log: Logger.export, "Failed to parse profile data")
            return false
        }

        // Get or create profile and update with backup data
        let profile = dataStore.getOrCreateProfile()
        profile.id = profileId
        profile.anchorPayday = anchorPayday
        profile.sickStartBalance = Decimal(backupProfile.sickStartBalance)
        profile.vacStartBalance = Decimal(backupProfile.vacStartBalance)
        profile.compStartBalance = Decimal(backupProfile.compStartBalance)
        profile.sickAccrualRate = Decimal(backupProfile.sickAccrualRate)
        profile.vacAccrualRate = Decimal(backupProfile.vacAccrualRate)
        profile.enforceQuarterIncrements = backupProfile.enforceQuarterIncrements
        profile.icalToken = backupProfile.icalToken
        profile.createdAt = createdAt
        profile.updatedAt = updatedAt

        dataStore.save()
        os_log(.info, log: Logger.export, "Profile imported successfully")
        return true
    }

    private func importEntries(_ backupEntries: [BackupEntry], into dataStore: DataStore) -> Int {
        var importedCount = 0

        for backupEntry in backupEntries {
            guard let entryId = UUID(uuidString: backupEntry.id),
                  let userId = UUID(uuidString: backupEntry.userId),
                  let date = DateUtils.parseISO(backupEntry.date),
                  let leaveType = LeaveType(rawValue: backupEntry.leaveType),
                  let action = LeaveAction(rawValue: backupEntry.action),
                  let source = EntrySource(rawValue: backupEntry.source),
                  let createdAt = ISO8601DateFormatter().date(from: backupEntry.createdAt),
                  let updatedAt = ISO8601DateFormatter().date(from: backupEntry.updatedAt) else {
                os_log(.error, log: Logger.export, "Failed to parse entry: %@", backupEntry.id)
                continue
            }

            let deletedAt = backupEntry.deletedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            let adjustmentSign = backupEntry.adjustmentSign.flatMap { AdjustmentSign(rawValue: $0) }

            let entry = LeaveEntry(
                id: entryId,
                userId: userId,
                date: date,
                leaveType: leaveType,
                action: action,
                hours: Decimal(backupEntry.hours),
                adjustmentSign: adjustmentSign,
                notes: backupEntry.notes,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                isDirty: true
            )

            dataStore.addEntry(entry)
            importedCount += 1
        }

        dataStore.save()
        os_log(.info, log: Logger.export, "Imported %d entries", importedCount)
        return importedCount
    }
}
