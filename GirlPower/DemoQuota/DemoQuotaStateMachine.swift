import Foundation

/// Reducer enforcing the Demo quota workflow.
struct DemoQuotaStateMachine {
    enum State: Equatable {
        case fresh
        case firstAttemptActive
        case gatePending
        case secondAttemptEligible
        case secondAttemptActive
        case locked(reason: LockReason)

        var isLocked: Bool {
            if case .locked = self { return true }
            return false
        }

        var hasActiveAttempt: Bool {
            switch self {
            case .firstAttemptActive, .secondAttemptActive:
                return true
            default:
                return false
            }
        }
    }

    enum Event: Equatable {
        case startAttempt
        case attemptCompleted
        case evaluationAllow(decision: DemoEvaluationDecision)
        case evaluationDeny(decision: DemoEvaluationDecision)
        case evaluationTimeout(decision: DemoEvaluationDecision)
        case resetFromServer(snapshot: RemoteSnapshot)
    }

    enum LockReason: Equatable {
        case quotaExhausted
        case evaluationDenied(message: String?)
        case evaluationTimeout
        case serverSync
    }

    enum SideEffect: Equatable {
        case logAttemptStart(index: Int)
        case logAttemptCompletion(index: Int)
        case setActiveAttempt(index: Int?)
        case setAttemptsUsed(Int)
        case requestEvaluation(attemptIndex: Int)
        case persistEvaluationDecision(DemoEvaluationDecision)
        case replaceSnapshot(RemoteSnapshot)
    }

    struct RemoteSnapshot: Equatable {
        let attemptsUsed: Int
        let activeAttemptIndex: Int?
        let lastDecision: DemoEvaluationDecision?
        let serverLockReason: LockReason?
        let lastSyncAt: Date?

        init(
            attemptsUsed: Int,
            activeAttemptIndex: Int?,
            lastDecision: DemoEvaluationDecision?,
            serverLockReason: LockReason? = nil,
            lastSyncAt: Date? = nil
        ) {
            self.attemptsUsed = attemptsUsed
            self.activeAttemptIndex = activeAttemptIndex
            self.lastDecision = lastDecision
            self.serverLockReason = serverLockReason
            self.lastSyncAt = lastSyncAt
        }

        static var empty: RemoteSnapshot {
            RemoteSnapshot(attemptsUsed: 0, activeAttemptIndex: nil, lastDecision: nil)
        }
    }

    enum DemoEvaluationDecision: Equatable {
        case allowSecondAttempt(timestamp: Date)
        case deny(message: String?, timestamp: Date)
        case timeout(timestamp: Date)

        var allowsSecondAttempt: Bool {
            if case .allowSecondAttempt = self { return true }
            return false
        }

        var lockReason: LockReason? {
            switch self {
            case .allowSecondAttempt:
                return nil
            case .deny(let message, _):
                return .evaluationDenied(message: message)
            case .timeout:
                return .evaluationTimeout
            }
        }

        var denialMessage: String? {
            if case let .deny(message, _) = self { return message }
            return nil
        }
    }

    struct Result: Equatable {
        let state: State
        let sideEffects: [SideEffect]
    }

    func reduce(state: State, event: Event) -> Result {
        switch (state, event) {
        case (.fresh, .startAttempt):
            return Result(
                state: .firstAttemptActive,
                sideEffects: [
                    .logAttemptStart(index: 1),
                    .setActiveAttempt(index: 1)
                ]
            )

        case (.firstAttemptActive, .attemptCompleted):
            return Result(
                state: .gatePending,
                sideEffects: [
                    .logAttemptCompletion(index: 1),
                    .setActiveAttempt(index: nil),
                    .setAttemptsUsed(1),
                    .requestEvaluation(attemptIndex: 1)
                ]
            )

        case (.gatePending, .evaluationAllow(let decision)):
            return Result(
                state: .secondAttemptEligible,
                sideEffects: [
                    .persistEvaluationDecision(decision)
                ]
            )

        case (.gatePending, .evaluationDeny(let decision)):
            return Result(
                state: .locked(reason: .evaluationDenied(message: decision.denialMessage)),
                sideEffects: [
                    .persistEvaluationDecision(decision)
                ]
            )

        case (.gatePending, .evaluationTimeout(let decision)):
            return Result(
                state: .locked(reason: .evaluationTimeout),
                sideEffects: [
                    .persistEvaluationDecision(decision)
                ]
            )

        case (.secondAttemptEligible, .startAttempt):
            return Result(
                state: .secondAttemptActive,
                sideEffects: [
                    .logAttemptStart(index: 2),
                    .setActiveAttempt(index: 2)
                ]
            )

        case (.secondAttemptActive, .attemptCompleted):
            return Result(
                state: .locked(reason: .quotaExhausted),
                sideEffects: [
                    .logAttemptCompletion(index: 2),
                    .setActiveAttempt(index: nil),
                    .setAttemptsUsed(2)
                ]
            )

        case (_, .resetFromServer(let snapshot)):
            let targetState = self.state(from: snapshot)
            return Result(
                state: targetState,
                sideEffects: [
                    .replaceSnapshot(snapshot)
                ]
            )

        default:
            return Result(state: state, sideEffects: [])
        }
    }

    func state(from snapshot: RemoteSnapshot) -> State {
        if let index = snapshot.activeAttemptIndex {
            return index == 2 ? .secondAttemptActive : .firstAttemptActive
        }

        if snapshot.attemptsUsed >= 2 {
            return .locked(reason: snapshot.serverLockReason ?? .quotaExhausted)
        }

        if snapshot.attemptsUsed == 1 {
            if let decision = snapshot.lastDecision {
                if decision.allowsSecondAttempt {
                    return .secondAttemptEligible
                }
                return .locked(reason: decision.lockReason ?? .serverSync)
            }
            return .gatePending
        }

        return .fresh
    }
}
