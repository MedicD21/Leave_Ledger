import Foundation
import OSLog

/// Configuration for Supabase connection.
/// Values should be set in Info.plist or .xcconfig.
enum SupabaseConfig {
    /// Timeout for network requests in seconds
    static let requestTimeout: TimeInterval = 30
    static var url: String {
        let direct = resolvedValue("SUPABASE_URL")
        if !direct.isEmpty {
            return direct
        }
        let host = resolvedValue("SUPABASE_HOST")
        if host.isEmpty {
            return ""
        }
        if host.contains("://") {
            return host
        }
        let scheme = resolvedValue("SUPABASE_SCHEME")
        let resolvedScheme = scheme.isEmpty ? "https" : scheme
        return "\(resolvedScheme)://\(host)"
    }
    static var anonKey: String { resolvedValue("SUPABASE_ANON_KEY") }

    private static func resolvedValue(_ key: String) -> String {
        let infoValue = Bundle.main.infoDictionary?[key] as? String ?? ""
        let envValue = ProcessInfo.processInfo.environment[key] ?? ""
        let trimmedInfo = infoValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInfo.isEmpty && !trimmedInfo.contains("$(") {
            return trimmedInfo
        }
        let trimmedEnv = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEnv.isEmpty && !trimmedEnv.contains("$(") {
            return trimmedEnv
        }
        return ""
    }
}

/// Manages Supabase sync for leave entries.
/// Uses a device-specific UUID as user identifier for this single-user app.
@Observable
final class SupabaseService {
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var syncError: String?

    private let userId: UUID
    private let syncLock = NSLock()

    init(userId: UUID) {
        self.userId = userId
        self.lastSyncAt = UserDefaults.standard.object(forKey: "lastSyncAt") as? Date
    }

    var isConfigured: Bool {
        !SupabaseConfig.url.isEmpty && !SupabaseConfig.anonKey.isEmpty
    }

    /// Pushes dirty local entries to Supabase.
    func pushEntries(_ entries: [LeaveEntry], completion: @escaping (Bool) -> Void) {
        guard isConfigured else {
            syncError = "Supabase not configured"
            os_log(.error, log: Logger.sync, "Push entries failed: Supabase not configured")
            completion(false)
            return
        }

        guard syncLock.try() else {
            syncError = "Sync already in progress"
            os_log(.default, log: Logger.sync, "Push entries skipped: sync already in progress")
            completion(false)
            return
        }
        defer { syncLock.unlock() }

        isSyncing = true
        os_log(.info, log: Logger.sync, "Starting push of %d entries", entries.count)

        // Build URL for upsert
        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/leave_entries") else {
            syncError = "Invalid Supabase URL"
            isSyncing = false
            completion(false)
            return
        }

        func valueOrNull(_ value: Any?) -> Any {
            value ?? NSNull()
        }

        let iso8601Formatter = ISO8601DateFormatter()

        let payload: [[String: Any]] = entries.map { entry in
            let updatedAtString = iso8601Formatter.string(from: entry.updatedAt)

            // Log details for each entry being pushed
            os_log(.info, log: Logger.sync, "Pushing entry %@ with:", String(entry.id.uuidString.prefix(8)))
            os_log(.info, log: Logger.sync, "  Date: %@", DateUtils.isoDate(entry.date))
            os_log(.info, log: Logger.sync, "  Local updatedAt (Date): %@", entry.updatedAt as CVarArg)
            os_log(.info, log: Logger.sync, "  Serialized updatedAt (ISO8601): %@", updatedAtString)

            return [
                "id": entry.id.uuidString,
                "user_id": entry.userId.uuidString,
                "date": DateUtils.isoDate(entry.date),
                "leave_type": entry.leaveTypeRaw,
                "action": entry.actionRaw,
                "hours": NSDecimalNumber(decimal: entry.hours).doubleValue,
                "adjustment_sign": valueOrNull(entry.adjustmentSignRaw),
                "notes": valueOrNull(entry.notes),
                "source": entry.sourceRaw,
                "created_at": iso8601Formatter.string(from: entry.createdAt),
                "updated_at": updatedAtString,
                "deleted_at": valueOrNull(entry.deletedAt.map { iso8601Formatter.string(from: $0) })
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            syncError = "Failed to serialize entries"
            isSyncing = false
            os_log(.error, log: Logger.sync, "Failed to serialize entries for push")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = SupabaseConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        // Use authenticated access token if available, otherwise fall back to anon key
        if let token = KeychainService.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        }

        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    let errorMsg = error.localizedDescription
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "Push entries network error: %@", errorMsg)
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    self?.syncError = nil
                    os_log(.info, log: Logger.sync, "Push entries successful")
                    completion(true)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    let errorMsg = "Push failed with status \(status)\(detail)"
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "%@", errorMsg)
                    completion(false)
                }
            }
        }.resume()
    }

    /// Pulls entries updated since last sync from Supabase.
    func pullEntries(completion: @escaping ([RemoteLeaveEntry]?) -> Void) {
        guard isConfigured else {
            syncError = "Supabase not configured"
            os_log(.error, log: Logger.sync, "Pull entries failed: Supabase not configured")
            completion(nil)
            return
        }

        isSyncing = true
        os_log(.info, log: Logger.sync, "Starting pull entries")

        var urlString = "\(SupabaseConfig.url)/rest/v1/leave_entries?user_id=eq.\(userId.uuidString)&order=updated_at.desc"
        if let lastSync = lastSyncAt {
            let isoDate = ISO8601DateFormatter().string(from: lastSync)
            urlString += "&updated_at=gte.\(isoDate)"
        }

        guard let url = URL(string: urlString) else {
            syncError = "Invalid URL"
            isSyncing = false
            os_log(.error, log: Logger.sync, "Pull entries failed: Invalid URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = SupabaseConfig.requestTimeout
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        // Use authenticated access token if available, otherwise fall back to anon key
        if let token = KeychainService.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    let errorMsg = error.localizedDescription
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "Pull entries network error: %@", errorMsg)
                    completion(nil)
                    return
                }
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 300 {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    let errorMsg = "Pull failed with status \(httpResp.statusCode)\(detail)"
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "%@", errorMsg)
                    completion(nil)
                    return
                }
                guard let data = data else {
                    self?.syncError = "No data received"
                    os_log(.error, log: Logger.sync, "Pull entries failed: No data received")
                    completion(nil)
                    return
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    let entries = try decoder.decode([RemoteLeaveEntry].self, from: data)
                    self?.lastSyncAt = Date()
                    UserDefaults.standard.set(self?.lastSyncAt, forKey: "lastSyncAt")
                    self?.syncError = nil
                    os_log(.info, log: Logger.sync, "Pull entries successful: %d entries", entries.count)
                    completion(entries)
                } catch {
                    let responseBody = String(data: data, encoding: .utf8) ?? "<unable to decode response>"
                    let errorMsg = "Decode error: \(error.localizedDescription)"
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "%@", errorMsg)
                    os_log(.error, log: Logger.sync, "Decode error details: %@", String(describing: error))
                    os_log(.error, log: Logger.sync, "Response body: %@", responseBody)
                    completion(nil)
                }
            }
        }.resume()
    }

    /// Full sync: push dirty, then pull updates.
    func sync(store: DataStore) {
        let profile = store.getOrCreateProfile()
        ensureProfile(profile) { [weak self] ready in
            guard ready else { return }

            // Sync entries
            let dirty = store.dirtyEntries()
            if dirty.isEmpty {
                self?.pullEntries { remote in
                    if let remote = remote {
                        store.upsertFromRemote(remote)
                    }
                }
            } else {
                self?.pushEntries(dirty) { success in
                    if success {
                        for entry in dirty {
                            store.markClean(entry)
                        }
                    }
                    self?.pullEntries { remote in
                        if let remote = remote {
                            store.upsertFromRemote(remote)
                        }
                    }
                }
            }

            // Sync notes (always do full sync for simplicity)
            self?.syncNotes(store: store)
        }
    }

    // MARK: - Date Notes Sync

    /// Syncs all date notes with Supabase
    private func syncNotes(store: DataStore) {
        let allNotes = store.allNotes()
        if !allNotes.isEmpty {
            pushNotes(allNotes) { [weak self] _ in
                self?.pullNotes { remote in
                    if let remote = remote {
                        store.upsertNotesFromRemote(remote)
                    }
                }
            }
        } else {
            pullNotes { remote in
                if let remote = remote {
                    store.upsertNotesFromRemote(remote)
                }
            }
        }
    }

    /// Pushes date notes to Supabase.
    private func pushNotes(_ notes: [DateNote], completion: @escaping (Bool) -> Void) {
        guard isConfigured else {
            os_log(.error, log: Logger.sync, "Push notes failed: Supabase not configured")
            completion(false)
            return
        }

        guard !notes.isEmpty else {
            completion(true)
            return
        }

        os_log(.info, log: Logger.sync, "Starting push of %d notes", notes.count)

        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/date_notes") else {
            os_log(.error, log: Logger.sync, "Push notes failed: Invalid URL")
            completion(false)
            return
        }

        func valueOrNull(_ value: Any?) -> Any {
            value ?? NSNull()
        }

        let payload: [[String: Any]] = notes.map { note in
            [
                "id": note.id.uuidString,
                "user_id": note.userId.uuidString,
                "date": DateUtils.isoDate(note.date),
                "title": note.title,
                "note_text": note.noteText,
                "color_hex": note.colorHex,
                "created_at": ISO8601DateFormatter().string(from: note.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: note.updatedAt),
                "deleted_at": valueOrNull(note.deletedAt.map { ISO8601DateFormatter().string(from: $0) })
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            os_log(.error, log: Logger.sync, "Failed to serialize notes for push")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = SupabaseConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        if let token = KeychainService.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        }

        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    os_log(.error, log: Logger.sync, "Push notes network error: %@", error.localizedDescription)
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    os_log(.info, log: Logger.sync, "Push notes successful")
                    completion(true)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    os_log(.error, log: Logger.sync, "Push notes failed with status %d", status)
                    completion(false)
                }
            }
        }.resume()
    }

    /// Pulls date notes from Supabase.
    private func pullNotes(completion: @escaping ([RemoteDateNote]?) -> Void) {
        guard isConfigured else {
            os_log(.error, log: Logger.sync, "Pull notes failed: Supabase not configured")
            completion(nil)
            return
        }

        os_log(.info, log: Logger.sync, "Starting pull notes")

        let urlString = "\(SupabaseConfig.url)/rest/v1/date_notes?user_id=eq.\(userId.uuidString)&order=updated_at.desc"

        guard let url = URL(string: urlString) else {
            os_log(.error, log: Logger.sync, "Pull notes failed: Invalid URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = SupabaseConfig.requestTimeout
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        if let token = KeychainService.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    os_log(.error, log: Logger.sync, "Pull notes network error: %@", error.localizedDescription)
                    completion(nil)
                    return
                }
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 300 {
                    os_log(.error, log: Logger.sync, "Pull notes failed with status %d", httpResp.statusCode)
                    completion(nil)
                    return
                }
                guard let data = data else {
                    os_log(.error, log: Logger.sync, "Pull notes failed: No data received")
                    completion(nil)
                    return
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    let notes = try decoder.decode([RemoteDateNote].self, from: data)
                    os_log(.info, log: Logger.sync, "Pull notes successful: %d notes", notes.count)
                    completion(notes)
                } catch {
                    os_log(.error, log: Logger.sync, "Decode notes error: %@", error.localizedDescription)
                    completion(nil)
                }
            }
        }.resume()
    }

    private func ensureProfile(_ profile: UserProfile, completion: @escaping (Bool) -> Void) {
        guard isConfigured else {
            syncError = "Supabase not configured"
            os_log(.error, log: Logger.sync, "Ensure profile failed: Supabase not configured")
            completion(false)
            return
        }

        isSyncing = true
        os_log(.info, log: Logger.sync, "Ensuring profile sync")

        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/profiles") else {
            syncError = "Invalid Supabase URL"
            isSyncing = false
            os_log(.error, log: Logger.sync, "Ensure profile failed: Invalid Supabase URL")
            completion(false)
            return
        }

        func valueOrNull(_ value: Any?) -> Any {
            value ?? NSNull()
        }

        let payload: [String: Any] = [
            "id": profile.id.uuidString,
            "anchor_payday": DateUtils.isoDate(profile.anchorPayday),
            "sick_start_balance": NSDecimalNumber(decimal: profile.sickStartBalance).doubleValue,
            "vac_start_balance": NSDecimalNumber(decimal: profile.vacStartBalance).doubleValue,
            "comp_start_balance": NSDecimalNumber(decimal: profile.compStartBalance).doubleValue,
            "sick_accrual_rate": NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue,
            "vac_accrual_rate": NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue,
            "ical_token": profile.icalToken,
            // Authentication and onboarding fields
            "apple_user_id": valueOrNull(profile.appleUserId),
            "email": valueOrNull(profile.email),
            "is_authenticated": profile.isAuthenticated,
            "is_setup_complete": profile.isSetupComplete,
            // Pay period configuration
            "pay_period_type": profile.payPeriodType,
            "pay_period_interval": profile.payPeriodInterval,
            // Enabled leave types
            "comp_enabled": profile.compEnabled,
            "vacation_enabled": profile.vacationEnabled,
            "sick_enabled": profile.sickEnabled
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            syncError = "Failed to serialize profile"
            isSyncing = false
            os_log(.error, log: Logger.sync, "Failed to serialize profile for sync")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = SupabaseConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        // Use authenticated access token if available, otherwise fall back to anon key
        if let token = KeychainService.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        }

        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    let errorMsg = error.localizedDescription
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "Profile sync network error: %@", errorMsg)
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    self?.syncError = nil
                    os_log(.info, log: Logger.sync, "Profile sync successful")
                    completion(true)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    let errorMsg = "Profile upsert failed with status \(status)\(detail)"
                    self?.syncError = errorMsg
                    os_log(.error, log: Logger.sync, "%@", errorMsg)
                    completion(false)
                }
            }
        }.resume()
    }
}
