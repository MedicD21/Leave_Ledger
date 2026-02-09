import Foundation
import Security

enum KeychainService {
    private static let service = "com.leaveLedger.userId"
    private static let accountDeviceId = "deviceUserId"
    private static let accountAppleUserId = "appleUserId"
    private static let accountEmail = "email"
    private static let accountAccessToken = "supabaseAccessToken"
    private static let accountRefreshToken = "supabaseRefreshToken"

    // MARK: - Device UUID (Legacy)

    static func getUserId() -> UUID {
        if let existing = loadUserId() {
            return existing
        }
        let newId = UUID()
        saveUserId(newId)
        return newId
    }

    private static func loadUserId() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountDeviceId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return UUID(uuidString: str)
    }

    private static func saveUserId(_ id: UUID) {
        let data = id.uuidString.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountDeviceId,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Apple Sign In Credentials

    static func saveAppleUserId(_ userId: String) {
        save(userId, forAccount: accountAppleUserId)
    }

    static func getAppleUserId() -> String? {
        load(forAccount: accountAppleUserId)
    }

    static func saveEmail(_ email: String) {
        save(email, forAccount: accountEmail)
    }

    static func getEmail() -> String? {
        load(forAccount: accountEmail)
    }

    // MARK: - Supabase Tokens

    static func saveAccessToken(_ token: String) {
        save(token, forAccount: accountAccessToken)
    }

    static func getAccessToken() -> String? {
        load(forAccount: accountAccessToken)
    }

    static func saveRefreshToken(_ token: String) {
        save(token, forAccount: accountRefreshToken)
    }

    static func getRefreshToken() -> String? {
        load(forAccount: accountRefreshToken)
    }

    static func clearAuthTokens() {
        deleteItem(forAccount: accountAppleUserId)
        deleteItem(forAccount: accountEmail)
        deleteItem(forAccount: accountAccessToken)
        deleteItem(forAccount: accountRefreshToken)
    }

    // MARK: - Helper Methods

    private static func save(_ value: String, forAccount account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private static func deleteItem(forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
