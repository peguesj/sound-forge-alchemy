import Foundation
import Security

struct LocalSecureTokenStatus: Identifiable, Hashable {
    let id: String
    var account: String
    var service: String
    var present: Bool
    var detail: String
}

enum LocalSecureTokenStore {
    static let spotifyAccount = "spotify-oauth"
    static let lalalaiAccount = "lalalai-api-key"
    static let providerAccountPrefix = "llm-provider"
    static let service = "com.soundforgealchemy.mac.secure-tokens"

    static func save(_ value: String, account: String, service: String = Self.service) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account, service: service)

        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    static func read(account: String, service: String = Self.service) throws -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String, service: String = Self.service) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    static func statusRecords(providerIDs: [String]) -> [LocalSecureTokenStatus] {
        let accounts = [
            spotifyAccount,
            lalalaiAccount
        ] + providerIDs.map { "\(providerAccountPrefix):\($0)" }

        return accounts.map { account in
            let present = (try? read(account: account)) != nil
            return LocalSecureTokenStatus(
                id: account,
                account: account,
                service: service,
                present: present,
                detail: present ? "Stored in Keychain" : "No local secret stored"
            )
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
