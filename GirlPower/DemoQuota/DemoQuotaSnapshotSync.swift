import Foundation

protocol DemoQuotaSnapshotSyncing {
    func fetchSnapshot(deviceID: UUID) async throws -> DemoQuotaStateMachine.RemoteSnapshot?
    func mirror(snapshot: DemoQuotaStateMachine.RemoteSnapshot, deviceID: UUID) async throws
}
