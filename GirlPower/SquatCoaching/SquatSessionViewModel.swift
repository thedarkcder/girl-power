import Combine
import SwiftUI

@MainActor
final class SquatSessionViewModel: ObservableObject {
    @Published private(set) var repCount: Int = 0
    @Published private(set) var phase: PosePhase = .idleWithinSet
    @Published private(set) var state: SquatSessionStateMachine.State = .idle
    @Published var statusText: String = "Requesting camera access"
    @Published var error: SquatSessionError?

    let coordinator: SquatSessionCoordinator
    private var sessionStartDate: Date?

    init(coordinator: SquatSessionCoordinator = SquatSessionCoordinator()) {
        self.coordinator = coordinator
        self.coordinator.output = self
    }

    func start() {
        error = nil
        sessionStartDate = Date()
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
        sessionStartDate = nil
    }

    func bindOverlay(to controller: SquatSessionViewController) {
        coordinator.overlayOutput = controller
    }

    func makeSummaryInput(attemptIndex: Int) -> SessionSummaryInput {
        let snapshot = coordinator.captureSummarySnapshot()
        let now = Date()
        let duration = now.timeIntervalSince(sessionStartDate ?? now)
        sessionStartDate = nil
        return SessionSummaryInput(
            attemptIndex: attemptIndex,
            snapshot: snapshot,
            duration: duration,
            generatedAt: now
        )
    }

    func presentSummary(_ context: SummaryContext) {
        coordinator.presentSummary(context)
    }
}

@MainActor
extension SquatSessionViewModel: SquatSessionCoordinatorOutput {
    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didTransitionTo state: SquatSessionStateMachine.State) {
        self.state = state
        statusText = statusMessage(for: state)
    }

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didUpdate result: RepCounter.Result) {
        repCount = result.repetitionCount
        phase = result.phase
        if case .coachingPausedLowConfidence = result.phase {
            statusText = "Find your pose"
        } else if case .repCompleted = result.phase {
            statusText = "Rep \(result.repetitionCount) locked"
        } else {
            statusText = ""
        }
    }

    func squatSessionCoordinator(_ coordinator: SquatSessionCoordinator, didEncounter error: SquatSessionError) {
        self.error = error
        statusText = "Session error"
    }

    private func statusMessage(for state: SquatSessionStateMachine.State) -> String {
        switch state {
        case .idle:
            return ""
        case .permissionsPending:
            return "Requesting camera permission"
        case .configuringSession:
            return "Configuring session"
        case .running(_):
            return ""
        case .backgroundSuspended(_):
            return "Session paused"
        case .interrupted(_, _):
            return "Camera interrupted"
        case .endingError(_):
            return "Session ended"
        case .summary:
            return "Summary ready"
        }
    }
}
