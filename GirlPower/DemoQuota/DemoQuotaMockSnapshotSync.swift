import Foundation

final class DemoQuotaMockSnapshotSync: DemoQuotaSnapshotSyncing {
    func fetchSnapshot(deviceID: UUID) async throws -> DemoQuotaStateMachine.RemoteSnapshot? { nil }
    func mirror(snapshot: DemoQuotaStateMachine.RemoteSnapshot, deviceID: UUID) async throws {}
}
