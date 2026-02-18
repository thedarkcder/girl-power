import XCTest
@testable import GirlPower

final class DemoQuotaStateMachineTests: XCTestCase {
    private var machine: DemoQuotaStateMachine!

    override func setUp() {
        super.setUp()
        machine = DemoQuotaStateMachine()
    }

    func testFreshStartEmitsLoggingSideEffects() {
        let result = machine.reduce(state: .fresh, event: .startAttempt)
        XCTAssertEqual(result.state, .firstAttemptActive)
        XCTAssertEqual(result.sideEffects, [.logAttemptStart(index: 1), .setActiveAttempt(index: 1)])
    }

    func testFirstAttemptCompletionMovesToGatePending() {
        let result = machine.reduce(state: .firstAttemptActive, event: .attemptCompleted)
        XCTAssertEqual(result.state, .gatePending)
        XCTAssertEqual(result.sideEffects.count, 4)
    }

    func testEvaluationAllowMovesToSecondAttemptEligible() {
        let decision: DemoQuotaStateMachine.DemoEvaluationDecision = .allowSecondAttempt(timestamp: Date())
        let result = machine.reduce(state: .gatePending, event: .evaluationAllow(decision: decision))
        XCTAssertEqual(result.state, .secondAttemptEligible)
        XCTAssertEqual(result.sideEffects, [.persistEvaluationDecision(decision)])
    }

    func testEvaluationDenyLocksMachine() {
        let decision: DemoQuotaStateMachine.DemoEvaluationDecision = .deny(message: "nope", timestamp: Date())
        let result = machine.reduce(state: .gatePending, event: .evaluationDeny(decision: decision))
        XCTAssertEqual(result.state, .locked(reason: .evaluationDenied(message: "nope")))
    }

    func testSecondAttemptFlowLocksAfterCompletion() {
        let startResult = machine.reduce(state: .secondAttemptEligible, event: .startAttempt)
        XCTAssertEqual(startResult.state, .secondAttemptActive)
        XCTAssertEqual(startResult.sideEffects, [.logAttemptStart(index: 2), .setActiveAttempt(index: 2)])

        let completion = machine.reduce(state: .secondAttemptActive, event: .attemptCompleted)
        XCTAssertEqual(completion.state, .locked(reason: .quotaExhausted))
        XCTAssertEqual(completion.sideEffects.count, 3)
    }

    func testRemoteSnapshotRehydratesLockedState() {
        let snapshot = DemoQuotaStateMachine.RemoteSnapshot(attemptsUsed: 2, activeAttemptIndex: nil, lastDecision: nil)
        let result = machine.reduce(state: .fresh, event: .resetFromServer(snapshot: snapshot))
        XCTAssertEqual(result.state, .locked(reason: .quotaExhausted))
    }
}
