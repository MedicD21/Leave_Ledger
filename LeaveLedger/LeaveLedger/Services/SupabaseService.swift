import Foundation

/// Configuration for Supabase connection.
/// Values should be set in Info.plist or .xcconfig.
enum SupabaseConfig {
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
            completion(false)
            return
        }
        isSyncing = true

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

        let payload: [[String: Any]] = entries.map { entry in
            [
                "id": entry.id.uuidString,
                "user_id": entry.userId.uuidString,
                "date": DateUtils.isoDate(entry.date),
                "leave_type": entry.leaveTypeRaw,
                "action": entry.actionRaw,
                "hours": NSDecimalNumber(decimal: entry.hours).doubleValue,
                "adjustment_sign": valueOrNull(entry.adjustmentSignRaw),
                "notes": valueOrNull(entry.notes),
                "source": entry.sourceRaw,
                "created_at": ISO8601DateFormatter().string(from: entry.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: entry.updatedAt),
                "deleted_at": valueOrNull(entry.deletedAt.map { ISO8601DateFormatter().string(from: $0) })
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            syncError = "Failed to serialize entries"
            isSyncing = false
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncError = error.localizedDescription
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    self?.syncError = nil
                    completion(true)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    self?.syncError = "Push failed with status \(status)\(detail)"
                    completion(false)
                }
            }
        }.resume()
    }

    /// Pulls entries updated since last sync from Supabase.
    func pullEntries(completion: @escaping ([RemoteLeaveEntry]?) -> Void) {
        guard isConfigured else {
            syncError = "Supabase not configured"
            completion(nil)
            return
        }
        isSyncing = true

        var urlString = "\(SupabaseConfig.url)/rest/v1/leave_entries?user_id=eq.\(userId.uuidString)&order=updated_at.desc"
        if let lastSync = lastSyncAt {
            let isoDate = ISO8601DateFormatter().string(from: lastSync)
            urlString += "&updated_at=gte.\(isoDate)"
        }

        guard let url = URL(string: urlString) else {
            syncError = "Invalid URL"
            isSyncing = false
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncError = error.localizedDescription
                    completion(nil)
                    return
                }
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 300 {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    self?.syncError = "Pull failed with status \(httpResp.statusCode)\(detail)"
                    completion(nil)
                    return
                }
                guard let data = data else {
                    self?.syncError = "No data received"
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
                    completion(entries)
                } catch {
                    self?.syncError = "Decode error: \(error.localizedDescription)"
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
        }
    }

    private func ensureProfile(_ profile: UserProfile, completion: @escaping (Bool) -> Void) {
        guard isConfigured else {
            syncError = "Supabase not configured"
            completion(false)
            return
        }
        isSyncing = true

        guard let url = URL(string: "\(SupabaseConfig.url)/rest/v1/profiles") else {
            syncError = "Invalid Supabase URL"
            isSyncing = false
            completion(false)
            return
        }

        let payload: [String: Any] = [
            "id": profile.id.uuidString,
            "anchor_payday": DateUtils.isoDate(profile.anchorPayday),
            "sick_start_balance": NSDecimalNumber(decimal: profile.sickStartBalance).doubleValue,
            "vac_start_balance": NSDecimalNumber(decimal: profile.vacStartBalance).doubleValue,
            "comp_start_balance": NSDecimalNumber(decimal: profile.compStartBalance).doubleValue,
            "sick_accrual_rate": NSDecimalNumber(decimal: profile.sickAccrualRate).doubleValue,
            "vac_accrual_rate": NSDecimalNumber(decimal: profile.vacAccrualRate).doubleValue,
            "ical_token": profile.icalToken
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            syncError = "Failed to serialize profile"
            isSyncing = false
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(userId.uuidString, forHTTPHeaderField: "X-User-Id")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncError = error.localizedDescription
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    self?.syncError = nil
                    completion(true)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let detail = body.isEmpty ? "" : " - \(body)"
                    self?.syncError = "Profile upsert failed with status \(status)\(detail)"
                    completion(false)
                }
            }
        }.resume()
    }
}
