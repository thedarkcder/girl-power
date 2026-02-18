import Foundation

protocol DemoAttemptPersisting {
    func loadSnapshot() -> DemoQuotaStateMachine.RemoteSnapshot
    func setAttemptsUsed(_ count: Int)
    func setActiveAttempt(index: Int?)
    func persistEvaluationDecision(_ decision: DemoQuotaStateMachine.DemoEvaluationDecision)
    func persistServerLockReason(_ reason: DemoQuotaStateMachine.LockReason?)
    func replace(with snapshot: DemoQuotaStateMachine.RemoteSnapshot)
    func reset()
}

final class UserDefaultsDemoAttemptRepository: DemoAttemptPersisting {
    private let defaults: UserDefaults
    private let attemptsKey: String
    private let activeAttemptKey: String
    private let lastDecisionKey: String
    private let serverLockReasonKey: String

    init(defaults: UserDefaults = .standard, prefix: String = "demo.quota") {
        self.defaults = defaults
        self.attemptsKey = "\(prefix).attempts"
        self.activeAttemptKey = "\(prefix).active"
        self.lastDecisionKey = "\(prefix).decision"
        self.serverLockReasonKey = "\(prefix).serverLockReason"
    }

    func loadSnapshot() -> DemoQuotaStateMachine.RemoteSnapshot {
        let attemptsUsed = defaults.integer(forKey: attemptsKey)
        let activeAttemptIndex = defaults.object(forKey: activeAttemptKey) as? Int
        let decision = loadDecision()
        let lockReason = loadServerLockReason()
        return DemoQuotaStateMachine.RemoteSnapshot(
            attemptsUsed: attemptsUsed,
            activeAttemptIndex: activeAttemptIndex,
            lastDecision: decision,
            serverLockReason: lockReason
        )
    }

    func setAttemptsUsed(_ count: Int) {
        defaults.set(count, forKey: attemptsKey)
    }

    func setActiveAttempt(index: Int?) {
        if let index {
            defaults.set(index, forKey: activeAttemptKey)
        } else {
            defaults.removeObject(forKey: activeAttemptKey)
        }
    }

    func persistEvaluationDecision(_ decision: DemoQuotaStateMachine.DemoEvaluationDecision) {
        switch decision {
        case .allowSecondAttempt(let timestamp):
            defaults.set(["type": "allow", "ts": timestamp.timeIntervalSince1970], forKey: lastDecisionKey)
        case .deny(let message, let timestamp):
            defaults.set([
                "type": "deny",
                "message": message ?? "",
                "ts": timestamp.timeIntervalSince1970
            ], forKey: lastDecisionKey)
        case .timeout(let timestamp):
            defaults.set(["type": "timeout", "ts": timestamp.timeIntervalSince1970], forKey: lastDecisionKey)
        }
    }

    func persistServerLockReason(_ reason: DemoQuotaStateMachine.LockReason?) {
        guard let reason else {
            defaults.removeObject(forKey: serverLockReasonKey)
            return
        }
        defaults.set(reason.storageValue, forKey: serverLockReasonKey)
    }

    func replace(with snapshot: DemoQuotaStateMachine.RemoteSnapshot) {
        setAttemptsUsed(snapshot.attemptsUsed)
        setActiveAttempt(index: snapshot.activeAttemptIndex)
        if let decision = snapshot.lastDecision {
            persistEvaluationDecision(decision)
        } else {
            defaults.removeObject(forKey: lastDecisionKey)
        }
        persistServerLockReason(snapshot.serverLockReason)
    }

    func reset() {
        defaults.removeObject(forKey: attemptsKey)
        defaults.removeObject(forKey: activeAttemptKey)
        defaults.removeObject(forKey: lastDecisionKey)
        defaults.removeObject(forKey: serverLockReasonKey)
    }

    private func loadDecision() -> DemoQuotaStateMachine.DemoEvaluationDecision? {
        guard let payload = defaults.dictionary(forKey: lastDecisionKey),
              let type = payload["type"] as? String,
              let timestamp = payload["ts"] as? TimeInterval else {
            return nil
        }
        let date = Date(timeIntervalSince1970: timestamp)
        switch type {
        case "allow":
            return .allowSecondAttempt(timestamp: date)
        case "deny":
            let message = (payload["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .deny(message: message, timestamp: date)
        case "timeout":
            return .timeout(timestamp: date)
        default:
            return nil
        }
    }

    private func loadServerLockReason() -> DemoQuotaStateMachine.LockReason? {
        guard let raw = defaults.string(forKey: serverLockReasonKey) else { return nil }
        return DemoQuotaStateMachine.LockReason(storageValue: raw)
    }
}

