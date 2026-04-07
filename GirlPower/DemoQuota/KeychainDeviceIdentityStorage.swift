import Foundation
import Security

final class KeychainDeviceIdentityStorage: KeychainPersisting {
    private let service: String
    private let account: String
    private let accessGroup: String?

    init(
        service: String = "com.route25.GirlPower.deviceid",
        account: String = "device-id",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    func readUUID() throws -> UUID? {
        if let existing = try readUUID(query: baseQuery(returnData: true)) {
            return existing
        }

        let legacyQuery = baseQuery(returnData: true, includeAccount: false)
        guard let legacyUUID = try readUUID(query: legacyQuery) else {
            return nil
        }

        try store(uuid: legacyUUID)
        SecItemDelete(legacyQuery as CFDictionary)
        return legacyUUID
    }

    func store(uuid: UUID) throws {
        let query = baseQuery(returnData: false)
        let data = uuid.uuidString.data(using: .utf8)!

        var status = SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainUnavailable
        }
    }

    private func readUUID(query: [String: Any]) throws -> UUID? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainUnavailable
        }
        guard let data = result as? Data,
              let uuidString = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: uuidString) else {
            throw DeviceIdentityError.unableToGenerate
        }
        return uuid
    }

    private func baseQuery(returnData: Bool, includeAccount: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if includeAccount {
            query[kSecAttrAccount as String] = account
        }
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if returnData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}
