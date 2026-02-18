import XCTest
import Combine
@testable import GirlPower

final class DemoQuotaCoordinatorTests: XCTestCase {
    private var persistence: DemoQuotaTestPersistence!
    private var logger: DemoQuotaTestSessionLogger!
    private var evaluation: DemoQuotaTestEvaluationService!
    private var identity: DemoQuotaTestIdentityProvider!
    private var snapshotSync: DemoQuotaTestSnapshotSync!
    private var coordinator: DemoQuotaCoordinator!
    private let fixedTimeoutDate = Date(timeIntervalSince1970: 42)

    override func setUp() {
        super.setUp()
        persistence = DemoQuotaTestPersistence()
        logger = DemoQuotaTestSessionLogger()
        evaluation = DemoQuotaTestEvaluationService(timestamp: Date(timeIntervalSince1970: 100))
        identity = DemoQuotaTestIdentityProvider(deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!)
        snapshotSync = DemoQuotaTestSnapshotSync()
        coordinator = DemoQuotaCoordinator(
            persistence: persistence,
            sessionLogger: logger,
            evaluationService: evaluation,
            identityProvider: identity,
            snapshotSync: snapshotSync,
            clock: { self.fixedTimeoutDate }
        )
    }

    override func tearDown() {
        coordinator = nil
        snapshotSync = nil
        identity = nil
        evaluation = nil
        logger = nil
        persistence = nil
        super.tearDown()
    }

    func testSecondAttemptAllowedThenLocksAfterCompletion() async throws {
        evaluation.responses = [.allow]

        await coordinator.prepareForDemoStart()
        let firstState = try await coordinator.markAttemptStarted(startMetadata: ["source": "test"])
        XCTAssertEqual(firstState, .firstAttemptActive)

        let pendingState = await coordinator.markAttemptCompleted(resultMetadata: ["result": "complete"])
        XCTAssertEqual(pendingState, .gatePending)
        XCTAssertEqual(persistence.attemptsUsed, 1)
        XCTAssertEqual(logger.loggedStages, [
            DemoQuotaLogEntry(stage: .start, attemptIndex: 1),
            DemoQuotaLogEntry(stage: .completion, attemptIndex: 1)
        ])

        await expectState(.secondAttemptEligible)
        XCTAssertEqual(evaluation.requests.map(\.attemptIndex), [1])

        let secondState = try await coordinator.markAttemptStarted(startMetadata: [:])
        XCTAssertEqual(secondState, .secondAttemptActive)

        let lockedState = await coordinator.markAttemptCompleted(resultMetadata: [:])
        XCTAssertEqual(lockedState, .locked(reason: .quotaExhausted))
        XCTAssertEqual(persistence.attemptsUsed, 2)
        XCTAssertEqual(logger.loggedStages.count, 4)
        XCTAssertEqual(snapshotSync.mirroredSnapshots.last?.attemptsUsed, 2)
    }

    func testEvaluationDenyLocksAndPersistsDecision() async throws {
        evaluation.responses = [.deny(message: "no more")]

        await coordinator.prepareForDemoStart()
        _ = try await coordinator.markAttemptStarted(startMetadata: [:])
        _ = await coordinator.markAttemptCompleted(resultMetadata: [:])

        await expectState(.locked(reason: .evaluationDenied(message: "no more")))
        XCTAssertEqual(persistence.lastDecision, .deny(message: "no more", timestamp: evaluation.timestamp))
        XCTAssertEqual(persistence.lockReason, .evaluationDenied(message: "no more"))
        XCTAssertEqual(snapshotSync.mirroredSnapshots.last?.serverLockReason, .evaluationDenied(message: "no more"))
    }

    func testEvaluationTimeoutFailsClosed() async throws {
        evaluation.responses = [.timeout]

        await coordinator.prepareForDemoStart()
        _ = try await coordinator.markAttemptStarted(startMetadata: [:])
        _ = await coordinator.markAttemptCompleted(resultMetadata: [:])

        await expectState(.locked(reason: .evaluationTimeout))
        XCTAssertEqual(persistence.lastDecision, .timeout(timestamp: fixedTimeoutDate))
        XCTAssertEqual(persistence.lockReason, .evaluationTimeout)
        XCTAssertEqual(snapshotSync.mirroredSnapshots.last?.serverLockReason, .evaluationTimeout)
    }

    func testLoggingFailureLocksWithServerSyncReason() async throws {
        logger.failuresBeforeSuccess = 3

        await coordinator.prepareForDemoStart()
        do {
            _ = try await coordinator.markAttemptStarted(startMetadata: [:])
            XCTFail("Expected logging failure")
        } catch let error as DemoQuotaCoordinatorError {
            XCTAssertEqual(error, .loggingFailed)
        } catch {
            XCTFail("Unexpected error \(error)")
        }

        let currentState = await coordinator.currentState()
        XCTAssertEqual(currentState, .locked(reason: .serverSync))
        XCTAssertEqual(persistence.attemptsUsed, 2)
        XCTAssertEqual(snapshotSync.mirroredSnapshots.last?.serverLockReason, .serverSync)
    }

    func testPrepareForDemoStartHydratesSnapshot() async throws {
        snapshotSync.fetchResult = DemoQuotaStateMachine.RemoteSnapshot(
            attemptsUsed: 2,
            activeAttemptIndex: nil,
            lastDecision: nil,
            serverLockReason: .quotaExhausted
        )

        await coordinator.prepareForDemoStart()
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .locked(reason: .quotaExhausted))
        XCTAssertEqual(identity.requestCount, 1)
        XCTAssertEqual(snapshotSync.fetchCount, 1)
        XCTAssertTrue(snapshotSync.mirroredSnapshots.isEmpty)
    }

    private func expectState(_ expected: DemoQuotaStateMachine.State, timeout: TimeInterval = 1.0) async {
        let expectation = expectation(description: "state \(expected)")
        let stream = await coordinator.observeStates()
        let monitor = Task {
            for await state in stream {
                if state == expected {
                    expectation.fulfill()
                    break
                }
            }
        }
        await fulfillment(of: [expectation], timeout: timeout)
        monitor.cancel()
    }
}

@MainActor
final class DemoQuotaViewModelBindingTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testButtonTitleSwitchesToOneMoreGoWhenEligible() async throws {
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .fresh)
        let repository = InMemoryOnboardingRepository(hasCompleted: true)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub()
        )

        let expectation = expectation(description: "second attempt eligible")
        viewModel.$demoQuotaState
            .dropFirst()
            .sink { state in
                if state == .secondAttemptEligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await coordinator.updateState(.secondAttemptEligible)
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.demoButtonTitle, "One more go")
        XCTAssertFalse(viewModel.isDemoButtonDisabled)
    }

    func testGatePendingDisablesButtonAndShowsStatus() async throws {
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .fresh)
        let repository = InMemoryOnboardingRepository(hasCompleted: true)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub()
        )

        let expectation = expectation(description: "gate pending")
        viewModel.$demoQuotaState
            .dropFirst()
            .sink { state in
                if state == .gatePending {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await coordinator.updateState(.gatePending)
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isDemoButtonDisabled)
        XCTAssertEqual(viewModel.demoStatusMessage, "Checking eligibility…")
    }

    func testLockedStateSurfacesUserFacingReason() async throws {
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .fresh)
        let repository = InMemoryOnboardingRepository(hasCompleted: true)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub()
        )
        let reason = DemoQuotaStateMachine.LockReason.evaluationDenied(message: "Need subscription")

        let expectation = expectation(description: "locked")
        viewModel.$demoQuotaState
            .dropFirst()
            .sink { state in
                if state == .locked(reason: reason) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await coordinator.updateState(.locked(reason: reason))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isDemoButtonDisabled)
        XCTAssertEqual(viewModel.demoStatusMessage, "Need subscription")
    }
}

// MARK: - Test doubles

struct DemoQuotaLogEntry: Equatable {
    let stage: DemoSessionStage
    let attemptIndex: Int
}

final class DemoQuotaTestPersistence: DemoAttemptPersisting {
    private(set) var attemptsUsed: Int = 0
    private(set) var activeAttemptIndex: Int?
    private(set) var lastDecision: DemoQuotaStateMachine.DemoEvaluationDecision?
    private(set) var lockReason: DemoQuotaStateMachine.LockReason?

    func loadSnapshot() -> DemoQuotaStateMachine.RemoteSnapshot {
        DemoQuotaStateMachine.RemoteSnapshot(
            attemptsUsed: attemptsUsed,
            activeAttemptIndex: activeAttemptIndex,
            lastDecision: lastDecision,
            serverLockReason: lockReason
        )
    }

    func setAttemptsUsed(_ count: Int) {
        attemptsUsed = count
    }

    func setActiveAttempt(index: Int?) {
        activeAttemptIndex = index
    }

    func persistEvaluationDecision(_ decision: DemoQuotaStateMachine.DemoEvaluationDecision) {
        lastDecision = decision
    }

    func persistServerLockReason(_ reason: DemoQuotaStateMachine.LockReason?) {
        lockReason = reason
    }

    func replace(with snapshot: DemoQuotaStateMachine.RemoteSnapshot) {
        attemptsUsed = snapshot.attemptsUsed
        activeAttemptIndex = snapshot.activeAttemptIndex
        lastDecision = snapshot.lastDecision
        lockReason = snapshot.serverLockReason
    }

    func reset() {
        attemptsUsed = 0
        activeAttemptIndex = nil
        lastDecision = nil
        lockReason = nil
    }
}

final class DemoQuotaTestSessionLogger: DemoSessionLogging {
    private(set) var loggedStages: [DemoQuotaLogEntry] = []
    var failuresBeforeSuccess: Int = 0

    func logAttempt(deviceID: UUID, attemptIndex: Int, stage: DemoSessionStage, metadata: [String : Any]) async throws {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw DemoSessionLoggingError.networkFailure
        }
        loggedStages.append(DemoQuotaLogEntry(stage: stage, attemptIndex: attemptIndex))
    }
}

final class DemoQuotaTestEvaluationService: DemoEvaluationServicing {
    enum Response {
        case allow
        case deny(message: String?)
        case timeout
        case networkFailure
    }

    var responses: [Response] = []
    private(set) var requests: [EvaluationRequest] = []
    let timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }

    func evaluate(deviceID: UUID, attemptIndex: Int, context: [String : Any]) async throws -> EvaluationResult {
        requests.append(EvaluationRequest(attemptIndex: attemptIndex, context: context))
        let response = responses.isEmpty ? .allow : responses.removeFirst()
        switch response {
        case .allow:
            return EvaluationResult(allowAnotherDemo: true, message: nil, timestamp: timestamp)
        case .deny(let message):
            return EvaluationResult(allowAnotherDemo: false, message: message, timestamp: timestamp)
        case .timeout:
            throw DemoEvaluationError.timeout
        case .networkFailure:
            throw DemoEvaluationError.networkFailure
        }
    }

    struct EvaluationRequest {
        let attemptIndex: Int
        let context: [String: Any]
    }
}

final class DemoQuotaTestIdentityProvider: DeviceIdentityProviding {
    private let deviceID: UUID
    private(set) var requestCount = 0

    init(deviceID: UUID) {
        self.deviceID = deviceID
    }

    func deviceID() async throws -> UUID {
        requestCount += 1
        return deviceID
    }
}

final class DemoQuotaTestSnapshotSync: DemoQuotaSnapshotSyncing {
    var fetchResult: DemoQuotaStateMachine.RemoteSnapshot?
    var fetchError: Error?
    var mirrorError: Error?
    private(set) var fetchCount = 0
    private(set) var mirroredSnapshots: [DemoQuotaStateMachine.RemoteSnapshot] = []
    private(set) var mirroredDeviceIDs: [UUID] = []

    func fetchSnapshot(deviceID: UUID) async throws -> DemoQuotaStateMachine.RemoteSnapshot? {
        fetchCount += 1
        if let error = fetchError {
            throw error
        }
        return fetchResult
    }

    func mirror(snapshot: DemoQuotaStateMachine.RemoteSnapshot, deviceID: UUID) async throws {
        if let error = mirrorError {
            throw error
        }
        mirroredSnapshots.append(snapshot)
        mirroredDeviceIDs.append(deviceID)
    }
}

actor DemoQuotaCoordinatorStreamStub: DemoQuotaCoordinating {
    private var state: DemoQuotaStateMachine.State
    private var continuations: [UUID: AsyncStream<DemoQuotaStateMachine.State>.Continuation] = [:]
    private let machine = DemoQuotaStateMachine()

    init(initialState: DemoQuotaStateMachine.State) {
        self.state = initialState
    }

    func prepareForDemoStart() async {}

    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
            Task { await self.addContinuation(continuation, id: id) }
        }
    }

    func currentState() async -> DemoQuotaStateMachine.State {
        state
    }

    func markAttemptStarted(startMetadata: [String : Any]) async throws -> DemoQuotaStateMachine.State {
        state
    }

    func markAttemptCompleted(resultMetadata: [String : Any]) async -> DemoQuotaStateMachine.State {
        state
    }

    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async {
        state = machine.state(from: snapshot)
        broadcast()
    }

    func updateState(_ newState: DemoQuotaStateMachine.State) async {
        state = newState
        broadcast()
    }

    private func addContinuation(_ continuation: AsyncStream<DemoQuotaStateMachine.State>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func broadcast() {
        continuations.values.forEach { $0.yield(state) }
    }
}

final class InMemoryOnboardingRepository: OnboardingCompletionRepository {
    private(set) var hasCompletedOnboarding: Bool

    init(hasCompleted: Bool) {
        self.hasCompletedOnboarding = hasCompleted
    }

    func markCompleted() {
        hasCompletedOnboarding = true
    }
}
