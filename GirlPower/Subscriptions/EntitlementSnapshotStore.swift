import Foundation

struct EntitlementSnapshot: Codable, Equatable {
    let isPro: Bool
    let productID: String?
    let lastUpdated: Date
}

protocol EntitlementSnapshotPersisting {
    func load() -> EntitlementSnapshot?
    func save(_ snapshot: EntitlementSnapshot)
    func clear()
}

struct UserDefaultsEntitlementSnapshotStore: EntitlementSnapshotPersisting {
    private let defaults: UserDefaults
    private let key = "com.girlpower.entitlements.snapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EntitlementSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EntitlementSnapshot.self, from: data)
    }

    func save(_ snapshot: EntitlementSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
