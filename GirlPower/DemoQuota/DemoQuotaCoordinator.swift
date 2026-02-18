import Foundation

protocol DemoQuotaCoordinating: Actor {
    func prepareForDemoStart() async
    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State>
    func currentState() async -> DemoQuotaStateMachine.State
    func markAttemptStarted(startMetadata: [String: Any]) async throws -> DemoQuotaStateMachine.State
    func markAttemptCompleted(resultMetadata: [String: Any]) async -> DemoQuotaStateMachine.State
    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async
}

enum DemoQuotaCoordinatorError: Error, Equatable {
    case deviceIdentityUnavailable
    case loggingFailed
}

actor DemoQuotaCoordinator: DemoQuotaCoordinating {
    private let stateMachine = DemoQuotaStateMachine()
    private var state: DemoQuotaStateMachine.State
    private let persistence: DemoAttemptPersisting
    private let sessionLogger: DemoSessionLogging
    private let evaluationService: DemoEvaluationServicing
    private let identityProvider: DeviceIdentityProviding
    private let snapshotSync: DemoQuotaSnapshotSyncing?
    private let clock: () -> Date

    private var deviceID: UUID?
    private var continuations: [UUID: AsyncStream<DemoQuotaStateMachine.State>.Continuation] = [:]

    init(
        persistence: DemoAttemptPersisting,
        sessionLogger: DemoSessionLogging,
        evaluationService: DemoEvaluationServicing,
        identityProvider: DeviceIdentityProviding,
        snapshotSync: DemoQuotaSnapshotSyncing?,
        clock: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.sessionLogger = sessionLogger
        self.evaluationService = evaluationService
        self.identityProvider = identityProvider
        self.snapshotSync = snapshotSync
        self.clock = clock
        let snapshot = persistence.loadSnapshot()
        self.state = stateMachine.state(from: snapshot)
    }

    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State> {
        AsyncStream { continuation in
            Task { await self.registerContinuation(continuation) }
        }
    }

    func currentState() async -> DemoQuotaStateMachine.State {
        state
    }

    func prepareForDemoStart() async {
        do {
            let device = try await resolveDeviceID()
            if let snapshot = try await snapshotSync?.fetchSnapshot(deviceID: device) {
                await resetFromServer(snapshot: snapshot)
            } else {
                publishState()
            }
        } catch {
            await failClosed(reason: .serverSync)
        }
    }

    func markAttemptStarted(startMetadata: [String: Any] = [:]) async throws -> DemoQuotaStateMachine.State {
        guard canStartNewAttempt else { return state }
        return try await apply(.startAttempt, metadata: startMetadata)
    }

    func markAttemptCompleted(resultMetadata: [String: Any] = [:]) async -> DemoQuotaStateMachine.State {
        guard state.hasActiveAttempt else { return state }
        do {
            return try await apply(.attemptCompleted, metadata: resultMetadata)
        } catch {
            return state
        }
    }

    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async {
        _ = try? await apply(.resetFromServer(snapshot: snapshot))
    }

    private func registerContinuation(_ continuation: AsyncStream<DemoQuotaStateMachine.State>.Continuation) async {
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publishState() {
        continuations.values.forEach { $0.yield(state) }
    }

    private func resolveDeviceID() async throws -> UUID {
        if let id = deviceID {
            return id
        }
        let id = try await identityProvider.deviceID()
        deviceID = id
        return id
    }

    @discardableResult
    private func apply(
        _ event: DemoQuotaStateMachine.Event,
        metadata: [String: Any] = [:]
    ) async throws -> DemoQuotaStateMachine.State {
        let previousState = state
        let result = stateMachine.reduce(state: state, event: event)
        state = result.state
        publishState()
        var shouldMirror = false
        do {
            shouldMirror = try await execute(result.sideEffects, metadata: metadata)
            if shouldMirror {
                try await mirrorSnapshot()
            }
            return state
        } catch {
            state = previousState
            publishState()
            await failClosed(reason: .serverSync)
            throw error
        }
    }

    private func execute(
        _ sideEffects: [DemoQuotaStateMachine.SideEffect],
        metadata: [String: Any]
    ) async throws -> Bool {
        var shouldMirror = false
        for effect in sideEffects {
            switch effect {
            case .logAttemptStart(let index):
                try await logAttempt(index: index, stage: .start, metadata: metadata)
            case .logAttemptCompletion(let index):
                try await logAttempt(index: index, stage: .completion, metadata: metadata)
            case .setActiveAttempt(let index):
                persistence.setActiveAttempt(index: index)
                shouldMirror = true
            case .setAttemptsUsed(let count):
                persistence.setAttemptsUsed(count)
                shouldMirror = true
            case .requestEvaluation(let attemptIndex):
                Task { await self.requestEvaluation(attemptIndex: attemptIndex, context: metadata) }
            case .persistEvaluationDecision(let decision):
                persistence.persistEvaluationDecision(decision)
                persistence.persistServerLockReason(decision.lockReason)
                shouldMirror = true
            case .replaceSnapshot(let snapshot):
                persistence.replace(with: snapshot)
            }
        }
        return shouldMirror
    }

    private func logAttempt(index: Int, stage: DemoSessionStage, metadata: [String: Any]) async throws {
        let device = try await resolveDeviceID()
        var attempts = 0
        while attempts < 2 {
            do {
                try await sessionLogger.logAttempt(
                    deviceID: device,
                    attemptIndex: index,
                    stage: stage,
                    metadata: metadata
                )
                return
            } catch {
                attempts += 1
            }
        }
        await failClosed(reason: .serverSync)
        throw DemoQuotaCoordinatorError.loggingFailed
    }

    private func requestEvaluation(attemptIndex: Int, context: [String: Any]) async {
        do {
            guard let device = try? await resolveDeviceID() else {
                throw DemoQuotaCoordinatorError.deviceIdentityUnavailable
            }
            let result = try await evaluationService.evaluate(deviceID: device, attemptIndex: attemptIndex, context: context)
            if result.allowAnotherDemo {
                let allowDecision = DemoQuotaStateMachine.DemoEvaluationDecision.allowSecondAttempt(timestamp: result.timestamp)
                _ = try? await apply(.evaluationAllow(decision: allowDecision))
            } else {
                let denyDecision = DemoQuotaStateMachine.DemoEvaluationDecision.deny(message: result.message, timestamp: result.timestamp)
                _ = try? await apply(.evaluationDeny(decision: denyDecision))
            }
        } catch DemoEvaluationError.timeout {
            let timeoutDecision = DemoQuotaStateMachine.DemoEvaluationDecision.timeout(timestamp: clock())
            _ = try? await apply(.evaluationTimeout(decision: timeoutDecision))
        } catch {
            let timeoutDecision = DemoQuotaStateMachine.DemoEvaluationDecision.timeout(timestamp: clock())
            _ = try? await apply(.evaluationTimeout(decision: timeoutDecision))
        }
    }

    private func mirrorSnapshot() async throws {
        guard let sync = snapshotSync else { return }
        let device = try await resolveDeviceID()
        let snapshot = persistence.loadSnapshot()
        try await sync.mirror(snapshot: snapshot, deviceID: device)
    }

    private func failClosed(reason: DemoQuotaStateMachine.LockReason) async {
        persistence.setAttemptsUsed(max(persistence.loadSnapshot().attemptsUsed, 2))
        persistence.setActiveAttempt(index: nil)
        persistence.persistServerLockReason(reason)
        state = .locked(reason: reason)
        publishState()
        try? await mirrorSnapshot()
    }

    private var canStartNewAttempt: Bool {
        switch state {
        case .fresh, .secondAttemptEligible:
            return true
        default:
            return false
        }
    }
}

final actor DemoQuotaCoordinatorDisabled: DemoQuotaCoordinating {
    func prepareForDemoStart() async {}

    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State> {
        AsyncStream { continuation in
            continuation.yield(.fresh)
            continuation.finish()
        }
    }

    func currentState() async -> DemoQuotaStateMachine.State { .fresh }

    func markAttemptStarted(startMetadata: [String: Any]) async throws -> DemoQuotaStateMachine.State {
        .firstAttemptActive
    }

    func markAttemptCompleted(resultMetadata: [String : Any]) async -> DemoQuotaStateMachine.State {
        .fresh
    }

    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async {}
}
