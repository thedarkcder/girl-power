import SwiftUI

@MainActor
final class AppFlowViewModel: ObservableObject {
    enum Route: Hashable {
        case demoStub
    }

    @Published private(set) var state: AppFlowStateMachine.State
    @Published var navigationPath = NavigationPath()

    let slides: [OnboardingSlide]
    private var lastSlideIndex: Int? {
        slides.indices.last
    }

    private let stateMachine: AppFlowStateMachine
    private let repository: OnboardingCompletionRepository

    init(
        repository: OnboardingCompletionRepository,
        slides: [OnboardingSlide] = OnboardingSlide.defaultSlides,
        stateMachine: AppFlowStateMachine? = nil
    ) {
        self.repository = repository
        self.slides = slides
        self.stateMachine = stateMachine ?? AppFlowStateMachine(
            slideCount: slides.count,
            skipOnboardingAfterSplash: repository.hasCompletedOnboarding
        )
        self.state = self.stateMachine.initialState()
        syncNavigation(for: state)
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

    func startDemo() {
        apply(event: .startDemo)
    }

    func finishDemo() {
        apply(event: .finishDemo)
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
}
