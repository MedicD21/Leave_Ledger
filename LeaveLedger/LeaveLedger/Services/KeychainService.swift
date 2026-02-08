import Foundation
import Security

enum KeychainService {
    private static let service = "com.leaveLedger.userId"
    private static let account = "deviceUserId"

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
        return UUID(uuidString: str)
    }

    private static func saveUserId(_ id: UUID) {
        let data = id.uuidString.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
