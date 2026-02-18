import Foundation

enum DemoQuotaSnapshotSyncError: Error {
    case invalidResponse
}

final class SupabaseDemoQuotaSnapshotSync: DemoQuotaSnapshotSyncing {
    private let fetchEndpoint: URL
    private let mirrorEndpoint: URL
    private let anonKey: String
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fetchEndpoint: URL,
        mirrorEndpoint: URL,
        anonKey: String,
        urlSession: URLSession = .shared
    ) {
        self.fetchEndpoint = fetchEndpoint
        self.mirrorEndpoint = mirrorEndpoint
        self.anonKey = anonKey
        self.urlSession = urlSession

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchSnapshot(deviceID: UUID) async throws -> DemoQuotaStateMachine.RemoteSnapshot? {
        var request = baseRequest(url: fetchEndpoint)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(DevicePayload(deviceID: deviceID.uuidString))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DemoQuotaSnapshotSyncError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard !data.isEmpty else { return nil }
            let payload = try decoder.decode(SnapshotPayload.self, from: data)
            return makeSnapshot(from: payload)
        case 204, 404:
            return nil
        default:
            throw DemoQuotaSnapshotSyncError.invalidResponse
        }
    }

    func mirror(snapshot: DemoQuotaStateMachine.RemoteSnapshot, deviceID: UUID) async throws {
        var request = baseRequest(url: mirrorEndpoint)
        request.httpMethod = "POST"
        let payload = MirrorPayload(deviceID: deviceID.uuidString, snapshot: makePayload(from: snapshot))
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw DemoQuotaSnapshotSyncError.invalidResponse
        }
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 4
        return request
    }

    private func makeSnapshot(from payload: SnapshotPayload) -> DemoQuotaStateMachine.RemoteSnapshot {
        let decision = payload.lastDecision.flatMap { decisionPayload -> DemoQuotaStateMachine.DemoEvaluationDecision? in
            switch decisionPayload.type {
            case "allow":
                return .allowSecondAttempt(timestamp: decisionPayload.timestamp)
            case "deny":
                return .deny(message: decisionPayload.message, timestamp: decisionPayload.timestamp)
            case "timeout":
                return .timeout(timestamp: decisionPayload.timestamp)
            default:
                return nil
            }
        }
        let lockReason = payload.serverLockReason.flatMap { DemoQuotaStateMachine.LockReason(storageValue: $0) }
        return DemoQuotaStateMachine.RemoteSnapshot(
            attemptsUsed: payload.attemptsUsed,
            activeAttemptIndex: payload.activeAttemptIndex,
            lastDecision: decision,
            serverLockReason: lockReason,
            lastSyncAt: payload.lastSyncAt
        )
    }

    private func makePayload(from snapshot: DemoQuotaStateMachine.RemoteSnapshot) -> SnapshotPayload {
        let decision: DecisionPayload?
        if let lastDecision = snapshot.lastDecision {
            switch lastDecision {
            case .allowSecondAttempt(let timestamp):
                decision = DecisionPayload(type: "allow", message: nil, timestamp: timestamp)
            case .deny(let message, let timestamp):
                decision = DecisionPayload(type: "deny", message: message, timestamp: timestamp)
            case .timeout(let timestamp):
                decision = DecisionPayload(type: "timeout", message: nil, timestamp: timestamp)
            }
        } else {
            decision = nil
        }

        return SnapshotPayload(
            attemptsUsed: snapshot.attemptsUsed,
            activeAttemptIndex: snapshot.activeAttemptIndex,
            lastDecision: decision,
            serverLockReason: snapshot.serverLockReason?.storageValue,
            lastSyncAt: snapshot.lastSyncAt ?? Date()
        )
    }
}

private struct DevicePayload: Codable {
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
    }
}

private struct MirrorPayload: Codable {
    let deviceID: String
    let snapshot: SnapshotPayload

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case snapshot
    }
}

private struct SnapshotPayload: Codable {
    let attemptsUsed: Int
    let activeAttemptIndex: Int?
    let lastDecision: DecisionPayload?
    let serverLockReason: String?
    let lastSyncAt: Date?

    enum CodingKeys: String, CodingKey {
        case attemptsUsed = "attempts_used"
        case activeAttemptIndex = "active_attempt_index"
        case lastDecision = "last_decision"
        case serverLockReason = "server_lock_reason"
        case lastSyncAt = "last_sync_at"
    }
}

private struct DecisionPayload: Codable {
    let type: String
    let message: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case timestamp = "ts"
    }
}
