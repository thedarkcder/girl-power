import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol DeviceIdentityProviding {
    func deviceID() async throws -> UUID
}

enum DeviceIdentityError: Error, Equatable {
    case keychainUnavailable
    case networkUnavailable
    case unableToGenerate
}

protocol DeviceIdentityLookupKeyProviding {
    func lookupKey() -> String?
}

final class DeviceIdentityProvider: DeviceIdentityProviding {
    private let keychain: KeychainPersisting
    private let serverMirror: DeviceIdentityMirroring
    private let lookupKeyProvider: DeviceIdentityLookupKeyProviding

    init(
        keychain: KeychainPersisting,
        serverMirror: DeviceIdentityMirroring,
        lookupKeyProvider: DeviceIdentityLookupKeyProviding = ConfiguredDeviceIdentityLookupKeyProvider()
    ) {
        self.keychain = keychain
        self.serverMirror = serverMirror
        self.lookupKeyProvider = lookupKeyProvider
    }

    func deviceID() async throws -> UUID {
        if let existing = try keychain.readUUID() {
            return existing
        }

        let lookupKey = lookupKeyProvider.lookupKey()

        if let lookupKey,
           let mirrored = try await serverMirror.fetchDeviceID(lookupKey: lookupKey) {
            try keychain.store(uuid: mirrored)
            return mirrored
        }

        let generated = UUID()
        try keychain.store(uuid: generated)
        if let lookupKey {
            try await serverMirror.mirror(deviceID: generated, lookupKey: lookupKey)
        }
        return generated
    }
}

protocol KeychainPersisting {
    func readUUID() throws -> UUID?
    func store(uuid: UUID) throws
}

protocol DeviceIdentityMirroring {
    func fetchDeviceID(lookupKey: String) async throws -> UUID?
    func mirror(deviceID: UUID, lookupKey: String) async throws
}

struct ConfiguredDeviceIdentityLookupKeyProvider: DeviceIdentityLookupKeyProviding {
    private let configuredLookupKey: String?

    init(lookupKey: String? = nil) {
        let normalized = lookupKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configuredLookupKey = normalized?.isEmpty == false ? normalized : nil
    }

    func lookupKey() -> String? {
        configuredLookupKey
    }
}
