import Foundation

extension DemoQuotaStateMachine.LockReason {
    var storageValue: String {
        switch self {
        case .quotaExhausted:
            return "quota"
        case .evaluationDenied(let message):
            return "deny: \(message ?? "")"
        case .evaluationTimeout:
            return "timeout"
        case .serverSync:
            return "server"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "quota":
            self = .quotaExhausted
        case "timeout":
            self = .evaluationTimeout
        case "server":
            self = .serverSync
        default:
            if storageValue.hasPrefix("deny: ") {
                let message = String(storageValue.dropFirst(6))
                let normalized = message.isEmpty ? nil : message
                self = .evaluationDenied(message: normalized)
            } else {
                return nil
            }
        }
    }
}

extension DemoQuotaStateMachine.LockReason {
    var userFacingMessage: String {
        switch self {
        case .quotaExhausted:
            return "You’ve used both free demos. Unlock full access to continue."
        case .evaluationDenied(let message):
            return message ?? "We can’t offer another free demo right now."
        case .evaluationTimeout:
            return "Eligibility check timed out. Please try again later or subscribe."
        case .serverSync:
            return "We couldn’t sync with the server. Please try again or contact support."
        }
    }
}
