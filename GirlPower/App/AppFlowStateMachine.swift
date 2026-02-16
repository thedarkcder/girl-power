struct AppFlowStateMachine {
    enum State: Equatable {
        case splash
        case onboarding(index: Int)
        case demoCTA
        case demoStub
    }

    enum Event: Equatable {
        case splashFinished
        case slideAdvance(to: Int)
        case onboardingCompleted
        case startDemo
        case finishDemo
    }

    private let onboardingRange: ClosedRange<Int>
    private let hasSlides: Bool
    private let skipOnboardingAfterSplash: Bool

    init(
        slideCount: Int = OnboardingSlide.defaultSlides.count,
        skipOnboardingAfterSplash: Bool = false
    ) {
        self.hasSlides = slideCount > 0
        self.skipOnboardingAfterSplash = skipOnboardingAfterSplash
        let upperBound = max(slideCount - 1, 0)
        onboardingRange = 0...upperBound
    }

    func initialState() -> State {
        .splash
    }

    func transition(from state: State, event: Event) -> State {
        switch (state, event) {
        case (.splash, .splashFinished):
            guard hasSlides else { return .demoCTA }
            if skipOnboardingAfterSplash {
                return .demoCTA
            }
            return .onboarding(index: onboardingRange.lowerBound)

        case (.onboarding(let currentIndex), .slideAdvance(let targetIndex)):
            guard onboardingRange.contains(targetIndex),
                  abs(targetIndex - currentIndex) <= 1
            else { return state }
            return .onboarding(index: targetIndex)

        case (.onboarding(let index), .onboardingCompleted):
            guard index == onboardingRange.upperBound else { return state }
            return .demoCTA

        case (.demoCTA, .startDemo):
            return .demoStub

        case (.demoStub, .finishDemo):
            return .demoCTA

        default:
            return state
        }
    }
}
