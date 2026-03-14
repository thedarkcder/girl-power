import Foundation

protocol DeviceIdentityProviding {
    func deviceID() async throws -> UUID
}

enum DeviceIdentityError: Error, Equatable {
    case keychainUnavailable
    case networkUnavailable
    case unableToGenerate
}

protocol DeviceIdentityLookupKeyProviding {
    func stableLookupKey() -> String?
}

final class DeviceIdentityProvider: DeviceIdentityProviding {
    private let keychain: KeychainPersisting
    private let serverMirror: DeviceIdentityMirroring
    private let lookupKeyProvider: DeviceIdentityLookupKeyProviding

    init(
        keychain: KeychainPersisting,
        serverMirror: DeviceIdentityMirroring,
        lookupKeyProvider: DeviceIdentityLookupKeyProviding = UnsupportedDeviceIdentityLookupKeyProvider()
    ) {
        self.keychain = keychain
        self.serverMirror = serverMirror
        self.lookupKeyProvider = lookupKeyProvider
    }

    func deviceID() async throws -> UUID {
        if let existing = try keychain.readUUID() {
            return existing
        }

        let stableLookupKey = lookupKeyProvider.stableLookupKey()

        if let stableLookupKey {
            if let mirrored = try await serverMirror.fetchDeviceID(stableLookupKey: stableLookupKey) {
                try keychain.store(uuid: mirrored)
                return mirrored
            }

            let generated = UUID()
            try keychain.store(uuid: generated)
            try await serverMirror.mirror(deviceID: generated, stableLookupKey: stableLookupKey)
            return generated
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

protocol DeviceIdentityMirroring {
    func fetchDeviceID(stableLookupKey: String) async throws -> UUID?
    func mirror(deviceID: UUID, stableLookupKey: String) async throws
}

struct UnsupportedDeviceIdentityLookupKeyProvider: DeviceIdentityLookupKeyProviding {
    func stableLookupKey() -> String? {
        return nil
    }
}
