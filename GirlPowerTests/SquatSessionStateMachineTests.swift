import XCTest
@testable import GirlPower

final class SquatSessionStateMachineTests: XCTestCase {
    func testPermissionsGrantedLeadsToRunning() {
        let machine = SquatSessionStateMachine()
        var state = machine.initialState()

        state = machine.transition(from: state, event: .requestPermissions)
        XCTAssertEqual(state, .permissionsPending)

        state = machine.transition(from: state, event: .permissionsGranted)
        XCTAssertEqual(state, .configuringSession)

        state = machine.transition(from: state, event: .configurationSucceeded())
        XCTAssertEqual(state, .running(.idleWithinSet))
    }

    func testPermissionsDeniedEndsSession() {
        let machine = SquatSessionStateMachine()
        var state = machine.transition(from: .idle, event: .requestPermissions)
        state = machine.transition(from: state, event: .permissionsDenied)
        XCTAssertEqual(state, .endingError(.permissionsDenied))
    }

    func testBackgroundSuspendAndResume() {
        let machine = SquatSessionStateMachine()
        let running = SquatSessionStateMachine.State.running(.descending(progress: 0.6))
        var state = machine.transition(from: running, event: .enteredBackground)
        guard case let .backgroundSuspended(previousPhase) = state else {
            return XCTFail("Expected background suspended")
        }
        XCTAssertEqual(previousPhase, .descending(progress: 0.6))

        state = machine.transition(from: state, event: .resumedForeground)
        XCTAssertEqual(state, .configuringSession)
    }

    func testInterruptionFlow() {
        let machine = SquatSessionStateMachine()
        let running = SquatSessionStateMachine.State.running(.ascending(progress: 0.5))
        var state = machine.transition(from: running, event: .interruptionBegan(.audioSession))
        guard case let .interrupted(reason, previousPhase) = state else {
            return XCTFail("Expected interruption state")
        }
        XCTAssertEqual(reason, .audioSession)
        XCTAssertEqual(previousPhase, .ascending(progress: 0.5))

        state = machine.transition(from: state, event: .interruptionEnded)
        XCTAssertEqual(state, .configuringSession)
    }

    func testFatalErrorOverridesState() {
        let machine = SquatSessionStateMachine()
        let running = SquatSessionStateMachine.State.running(.idleWithinSet)
        let error = SquatSessionError.captureFailed("Runtime")
        let state = machine.transition(from: running, event: .fatalError(error))
        XCTAssertEqual(state, .endingError(error))
    }
}
