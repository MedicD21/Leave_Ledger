import Foundation

/// Configuration for Supabase connection.
/// Values should be set in Info.plist or .xcconfig.
enum SupabaseConfig {
    static var url: String {
        Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
    }
    static var anonKey: String {
        Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let payload: [[String: Any]] = entries.map { entry in
            var dict: [String: Any] = [
                "id": entry.id.uuidString,
                "user_id": entry.userId.uuidString,
                "date": DateUtils.isoDate(entry.date),
                "leave_type": entry.leaveTypeRaw,
                "action": entry.actionRaw,
                "hours": NSDecimalNumber(decimal: entry.hours).doubleValue,
                "source": entry.sourceRaw,
                "created_at": ISO8601DateFormatter().string(from: entry.createdAt),
                "updated_at": ISO8601DateFormatter().string(from: entry.updatedAt)
            ]
            if let sign = entry.adjustmentSignRaw { dict["adjustment_sign"] = sign }
            if let notes = entry.notes { dict["notes"] = notes }
            if let deleted = entry.deletedAt {
                dict["deleted_at"] = ISO8601DateFormatter().string(from: deleted)
            }
            return dict
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
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncError = error.localizedDescription
                    completion(false)
                } else if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                    self?.syncError = nil
                    completion(true)
                } else {
                    self?.syncError = "Push failed with status \((response as? HTTPURLResponse)?.statusCode ?? 0)"
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

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncError = error.localizedDescription
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
        let dirty = store.dirtyEntries()
        if dirty.isEmpty {
            pullEntries { [weak self] remote in
                if let remote = remote {
                    store.upsertFromRemote(remote)
                }
                _ = self
            }
        } else {
            pushEntries(dirty) { [weak self] success in
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
