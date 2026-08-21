import Foundation
import Security

final class KeychainSessionStore: SessionStoring, @unchecked Sendable {
    private enum Key {
        static let installationId = "installation-id"
        static let session = "app-session"
    }

    private let service = "com.robertcdawson.whoops.session"
    private let lock = NSLock()

    func installationId() throws -> String {
        try lock.withLock {
            if let data = try read(key: Key.installationId),
                let value = String(data: data, encoding: .utf8)
            {
                return value
            }
            let value = UUID().uuidString.lowercased()
            try write(Data(value.utf8), key: Key.installationId)
            return value
        }
    }

    func session() throws -> AppSessionPair? {
        try lock.withLock {
            guard let data = try read(key: Key.session) else { return nil }
            return try JSONDecoder().decode(AppSessionPair.self, from: data)
        }
    }

    func save(session: AppSessionPair) throws {
        try lock.withLock {
            try write(JSONEncoder().encode(session), key: Key.session)
        }
    }

    func deleteSession() throws {
        try lock.withLock {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: Key.session,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AppError.transport("Keychain deletion failed (\(status)).")
            }
        }
    }

    private func read(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.transport("Keychain read failed (\(status)).")
        }
        return data
    }

    private func write(_ data: Data, key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AppError.transport("Keychain update failed (\(updateStatus)).")
        }
        var insertion = query
        for (key, value) in attributes {
            insertion[key] = value
        }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppError.transport("Keychain write failed (\(addStatus)).")
        }
    }
}
