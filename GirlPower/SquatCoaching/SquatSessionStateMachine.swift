import Foundation

struct SquatSessionStateMachine {
    enum State: Equatable {
        case idle
        case permissionsPending
        case configuringSession
        case running(PosePhase)
        case backgroundSuspended(previousPhase: PosePhase?)
        case interrupted(reason: SquatSessionInterruption, previousPhase: PosePhase?)
        case endingError(SquatSessionError)
        case summary(SummaryContext)
    }

    enum Event: Equatable {
        case requestPermissions
        case permissionsGranted
        case permissionsDenied
        case configurationStarted
        case configurationSucceeded(initialPhase: PosePhase = .idleWithinSet)
        case configurationFailed(SquatSessionError)
        case posePhaseChanged(PosePhase)
        case enteredBackground
        case resumedForeground
        case interruptionBegan(SquatSessionInterruption)
        case interruptionEnded
        case fatalError(SquatSessionError)
        case sessionEnded
        case summaryReady(SummaryContext)
    }

    func initialState() -> State {
        .idle
    }

    func transition(from state: State, event: Event) -> State {
        switch (state, event) {
        case (_, .fatalError(let error)):
            return .endingError(error)

        case (.endingError, .sessionEnded):
            return .idle

        case (_, .sessionEnded):
            return .idle

        case (.idle, .requestPermissions):
            return .permissionsPending

        case (.permissionsPending, .permissionsGranted):
            return .configuringSession

        case (.permissionsPending, .permissionsDenied):
            return .endingError(.permissionsDenied)

        case (.configuringSession, .configurationStarted):
            return .configuringSession

        case (.configuringSession, .configurationSucceeded(let phase)):
            return .running(phase)

        case (.configuringSession, .configurationFailed(let error)):
            return .endingError(error)

        case (.running, .posePhaseChanged(let phase)):
            return .running(phase)

        case (.running, .summaryReady(let context)):
            return .summary(context)

        case (.running(let phase), .enteredBackground):
            return .backgroundSuspended(previousPhase: phase)

        case (.backgroundSuspended, .resumedForeground):
            return .configuringSession

        case (.running(let phase), .interruptionBegan(let interruption)):
            return .interrupted(reason: interruption, previousPhase: phase)

        case (.interrupted, .interruptionEnded):
            return .configuringSession

        case (.running, .configurationFailed(let error)):
            return .endingError(error)

        case (.idle, .configurationFailed(let error)):
            return .endingError(error)

        case (_, .configurationStarted):
            return .configuringSession

        case (.running, .permissionsDenied):
            return .endingError(.permissionsDenied)

        case (.running, .permissionsGranted):
            return state

        case (.idle, .configurationSucceeded(let phase)):
            return .running(phase)

        case (.idle, .posePhaseChanged(let phase)):
            return .running(phase)

        case (.summary, .sessionEnded):
            return .idle

        default:
            return state
        }
    }
}
