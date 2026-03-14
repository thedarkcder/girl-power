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
    /// Returns a best-effort continuity hint for anonymous quota recovery.
    /// This value is not guaranteed to survive reinstalls or device/vendor resets.
    func lookupKey() -> String?
}

final class DeviceIdentityProvider: DeviceIdentityProviding {
    private let keychain: KeychainPersisting
    private let serverMirror: DeviceIdentityMirroring
    private let lookupKeyProvider: DeviceIdentityLookupKeyProviding

    init(
        keychain: KeychainPersisting,
        serverMirror: DeviceIdentityMirroring,
        lookupKeyProvider: DeviceIdentityLookupKeyProviding = VendorDeviceIdentityLookupKeyProvider()
    ) {
        self.keychain = keychain
        self.serverMirror = serverMirror
        self.lookupKeyProvider = lookupKeyProvider
    }

    func deviceID() async throws -> UUID {
        if let existing = try keychain.readUUID() {
            return existing
        }

        return try await resolveIdentityOnKeychainMiss()
    }

    private func resolveIdentityOnKeychainMiss() async throws -> UUID {
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

struct VendorDeviceIdentityLookupKeyProvider: DeviceIdentityLookupKeyProviding {
    func lookupKey() -> String? {
#if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
#else
        return nil
#endif
    }
}
