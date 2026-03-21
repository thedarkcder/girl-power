import Foundation

extension DemoQuotaStateMachine.LockReason {
    var denialMessage: String? {
        if case let .evaluationDenied(message) = self {
            return message
        }
        return nil
    }

    var storageValue: String {
        switch self {
        case .quotaExhausted:
            return "quota"
        case .evaluationDenied:
            return "evaluation_denied"
        case .evaluationTimeout:
            return "evaluation_timeout"
        case .serverSync:
            return "server_sync"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "quota":
            self = .quotaExhausted
        case "evaluation_denied":
            self = .evaluationDenied(message: nil)
        case "evaluation_timeout":
            self = .evaluationTimeout
        case "server_sync":
            self = .serverSync
        default:
            return nil
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
