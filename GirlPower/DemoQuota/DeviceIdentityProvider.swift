import Foundation

protocol DeviceIdentityProviding {
    func deviceID() async throws -> UUID
}

enum DeviceIdentityError: Error, Equatable {
    case keychainUnavailable
    case networkUnavailable
    case unableToGenerate
}

final class DeviceIdentityProvider: DeviceIdentityProviding {
    private let keychain: KeychainPersisting

    init(keychain: KeychainPersisting) {
        self.keychain = keychain
    }

    func deviceID() async throws -> UUID {
        if let existing = try keychain.readUUID() {
            return existing
        }

        let generated = UUID()
        try keychain.store(uuid: generated)
        return generated
    }
}

protocol KeychainPersisting {
    func readUUID() throws -> UUID?
    func store(uuid: UUID) throws
}
