import Foundation
import Security

protocol KeychainSecurityClient {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct LiveKeychainSecurityClient: KeychainSecurityClient {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class KeychainDeviceIdentityStorage: KeychainPersisting {
    private let service: String
    private let account: String
    private let accessGroup: String?
    private let securityClient: KeychainSecurityClient

    init(
        service: String = "com.route25.GirlPower.deviceid",
        account: String = "device-id",
        accessGroup: String? = nil,
        securityClient: KeychainSecurityClient = LiveKeychainSecurityClient()
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.securityClient = securityClient
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
        _ = securityClient.delete(legacyQuery)
        return legacyUUID
    }

    func store(uuid: UUID) throws {
        let query = baseQuery(returnData: false)
        let data = uuid.uuidString.data(using: .utf8)!

        var status = securityClient.add(query.merging([kSecValueData as String: data]) { _, new in new })
        if status == errSecDuplicateItem {
            status = securityClient.update(query, attributes: [kSecValueData as String: data])
        }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainUnavailable
        }
    }

    private func readUUID(query: [String: Any]) throws -> UUID? {
        let result = securityClient.copyMatching(query)
        let status = result.status
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainUnavailable
        }
        guard let data = result.data,
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
