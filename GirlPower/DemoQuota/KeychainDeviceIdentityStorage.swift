import Foundation
import Security

final class KeychainDeviceIdentityStorage: KeychainPersisting {
    private let service: String
    private let accessGroup: String?

    init(service: String = "com.route25.girlpower.deviceid", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func readUUID() throws -> UUID? {
        let query = baseQuery()
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

    func store(uuid: UUID) throws {
        let query = baseQuery()
        let data = uuid.uuidString.data(using: .utf8)!

        var status = SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainUnavailable
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
