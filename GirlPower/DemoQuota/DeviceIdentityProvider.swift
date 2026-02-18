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
    private let serverMirror: DeviceIdentityMirroring

    init(keychain: KeychainPersisting, serverMirror: DeviceIdentityMirroring) {
        self.keychain = keychain
        self.serverMirror = serverMirror
    }

    func deviceID() async throws -> UUID {
        if let existing = try keychain.readUUID() {
            return existing
        }

        if let mirrored = try await serverMirror.fetchDeviceID() {
            try keychain.store(uuid: mirrored)
            return mirrored
        }

        let generated = UUID()
        try keychain.store(uuid: generated)
        try await serverMirror.mirror(deviceID: generated)
        return generated
    }
}

protocol KeychainPersisting {
    func readUUID() throws -> UUID?
    func store(uuid: UUID) throws
}

protocol DeviceIdentityMirroring {
    func fetchDeviceID() async throws -> UUID?
    func mirror(deviceID: UUID) async throws
}
