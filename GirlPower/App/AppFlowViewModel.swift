import SwiftUI

@MainActor
final class AppFlowViewModel: ObservableObject {
    enum Route: Hashable {
        case demoStub
    }

    @Published private(set) var state: AppFlowStateMachine.State
    @Published var navigationPath = NavigationPath()
    @Published private(set) var demoQuotaState: DemoQuotaStateMachine.State = .fresh

    var demoButtonTitle: String {
        switch (demoQuotaState, state) {
        case (.gatePending, _):
            return "Checking eligibility…"
        case (.secondAttemptEligible, _):
            return "One more go"
        default:
            return "Start Free Demo"
        }
    }

    var isDemoButtonDisabled: Bool {
        demoQuotaState.isLocked || demoQuotaState == .gatePending
    }

    var demoStatusMessage: String? {
        switch demoQuotaState {
        case .gatePending:
            return "Checking eligibility…"
        case .locked(let reason):
            return reason.userFacingMessage
        default:
            return nil
        }
    }

    let slides: [OnboardingSlide]
    private var lastSlideIndex: Int? {
        slides.indices.last
    }

    private let stateMachine: AppFlowStateMachine
    private let repository: OnboardingCompletionRepository
    private let demoQuotaCoordinator: DemoQuotaCoordinating
    private var stateTask: Task<Void, Never>?

    init(
        repository: OnboardingCompletionRepository,
        demoQuotaCoordinator: DemoQuotaCoordinating,
        slides: [OnboardingSlide] = OnboardingSlide.defaultSlides,
        stateMachine: AppFlowStateMachine? = nil
    ) {
        self.repository = repository
        self.demoQuotaCoordinator = demoQuotaCoordinator
        self.slides = slides
        self.stateMachine = stateMachine ?? AppFlowStateMachine(
            slideCount: slides.count,
            skipOnboardingAfterSplash: repository.hasCompletedOnboarding
        )
        self.state = self.stateMachine.initialState()
        syncNavigation(for: state)
        observeDemoQuota()
    }

    deinit {
        stateTask?.cancel()
    }

    func handleSplashFinished() {
        apply(event: .splashFinished)
    }

    func bindingForOnboardingIndex() -> Binding<Int> {
        Binding(
            get: {
                guard case let .onboarding(index) = self.state else { return 0 }
                return index
            },
            set: { newValue in
                self.handleSlideIndexChange(to: newValue)
            }
        )
    }

    func completeOnboarding() {
        guard case let .onboarding(index) = state,
              let lastIndex = lastSlideIndex,
              index == lastIndex else { return }
        repository.markCompleted()
        apply(event: .onboardingCompleted)
    }

    func startDemo(reason: String = "cta_tap") {
        guard isDemoButtonDisabled == false else { return }
        let metadata: [String: Any] = [
            "reason": reason,
            "cta_label": demoButtonTitle,
            "timestamp": isoFormatter.string(from: Date())
        ]
        Task {
            let newState = try? await demoQuotaCoordinator.markAttemptStarted(startMetadata: metadata)
            await MainActor.run {
                switch newState {
                case .firstAttemptActive?, .secondAttemptActive?:
                    apply(event: .startDemo)
                default:
                    break
                }
            }
        }
    }

    func finishDemo(reason: String = "user_exit") {
        let metadata: [String: Any] = [
            "reason": reason,
            "timestamp": isoFormatter.string(from: Date())
        ]
        Task {
            _ = await demoQuotaCoordinator.markAttemptCompleted(resultMetadata: metadata)
            await MainActor.run {
                apply(event: .finishDemo)
            }
        }
    }

    private func handleSlideIndexChange(to index: Int) {
        apply(event: .slideAdvance(to: index))
    }

    private func apply(event: AppFlowStateMachine.Event) {
        let nextState = stateMachine.transition(from: state, event: event)
        guard nextState != state else { return }
        state = nextState
        syncNavigation(for: nextState)
    }

    private func syncNavigation(for state: AppFlowStateMachine.State) {
        switch state {
        case .demoStub:
            if navigationPath.isEmpty {
                navigationPath.append(Route.demoStub)
            }
        default:
            if !navigationPath.isEmpty {
                navigationPath = NavigationPath()
            }
        }
    }

    private func observeDemoQuota() {
        stateTask = Task {
            await demoQuotaCoordinator.prepareForDemoStart()
            let stream = await demoQuotaCoordinator.observeStates()
            for await newState in stream {
                await MainActor.run {
                    demoQuotaState = newState
                }
            }
        }
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
