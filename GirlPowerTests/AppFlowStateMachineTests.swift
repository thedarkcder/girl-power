import XCTest
@testable import GirlPower

final class AppFlowStateMachineTests: XCTestCase {
    private var stateMachine: AppFlowStateMachine!

    override func setUp() {
        super.setUp()
        stateMachine = AppFlowStateMachine()
    }

    func testInitialState_WhenOnboardingNotCompleted_IsSplash() {
        let state = stateMachine.initialState()
        XCTAssertEqual(state, .splash)
    }

    func testSplashFinishedSkipsDirectlyToCTAWhenOnboardingCompleted() {
        stateMachine = AppFlowStateMachine(skipOnboardingAfterSplash: true)
        let afterSplash = stateMachine.transition(from: .splash, event: .splashFinished)
        XCTAssertEqual(afterSplash, .demoCTA)
    }

    func testSplashFinishedWithoutSlidesGoesToCTA() {
        stateMachine = AppFlowStateMachine(slideCount: 0)
        let afterSplash = stateMachine.transition(from: .splash, event: .splashFinished)
        XCTAssertEqual(afterSplash, .demoCTA)
    }

    func testSplashFinishedTransitionsToFirstOnboardingSlide() {
        let next = stateMachine.transition(from: .splash, event: .splashFinished)
        XCTAssertEqual(next, .onboarding(index: 0))
    }

    func testSlideAdvanceRequiresStepByStepNavigation() {
        let skip = stateMachine.transition(from: .onboarding(index: 0), event: .slideAdvance(to: 2))
        XCTAssertEqual(skip, .onboarding(index: 0))

        let next = stateMachine.transition(from: .onboarding(index: 0), event: .slideAdvance(to: 1))
        XCTAssertEqual(next, .onboarding(index: 1))
    }

    func testSlideAdvanceRejectsOutOfRangeTargets() {
        let belowLowerBound = stateMachine.transition(from: .onboarding(index: 0), event: .slideAdvance(to: -1))
        XCTAssertEqual(belowLowerBound, .onboarding(index: 0))

        let aboveUpperBound = stateMachine.transition(from: .onboarding(index: 2), event: .slideAdvance(to: 3))
        XCTAssertEqual(aboveUpperBound, .onboarding(index: 2))
    }

    func testOnboardingCompletedOnlyFromLastSlide() {
        let early = stateMachine.transition(from: .onboarding(index: 1), event: .onboardingCompleted)
        XCTAssertEqual(early, .onboarding(index: 1))

        let completed = stateMachine.transition(from: .onboarding(index: 2), event: .onboardingCompleted)
        XCTAssertEqual(completed, .demoCTA)
    }

    func testStartDemoMovesToDemoStub() {
        let next = stateMachine.transition(from: .demoCTA, event: .startDemo)
        XCTAssertEqual(next, .demoStub)
    }

    func testFinishDemoReturnsToCTA() {
        let next = stateMachine.transition(from: .demoStub, event: .finishDemo)
        XCTAssertEqual(next, .demoCTA)
    }
}

@MainActor
final class AppFlowViewModelTests: XCTestCase {
    func testCompleteOnboardingPersistsFlagAndMovesToCTA() {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: false)
        let viewModel = AppFlowViewModel(repository: repository)

        viewModel.handleSplashFinished()
        let indexBinding = viewModel.bindingForOnboardingIndex()
        indexBinding.wrappedValue = 1
        indexBinding.wrappedValue = 2
        viewModel.completeOnboarding()

        XCTAssertEqual(viewModel.state, .demoCTA)
        XCTAssertEqual(repository.markCompletedCallCount, 1)
        XCTAssertTrue(repository.hasCompletedOnboarding)
    }

    func testStartDemoRoutesToStubAndFinishReturnsToCTA() {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: true)
        let viewModel = AppFlowViewModel(repository: repository)

        XCTAssertEqual(viewModel.state, .splash)
        viewModel.handleSplashFinished()
        XCTAssertEqual(viewModel.state, .demoCTA)

        viewModel.startDemo()
        XCTAssertEqual(viewModel.state, .demoStub)
        XCTAssertFalse(viewModel.navigationPath.isEmpty)

        viewModel.finishDemo()
        XCTAssertEqual(viewModel.state, .demoCTA)
        XCTAssertTrue(viewModel.navigationPath.isEmpty)
    }
}

private final class FakeOnboardingCompletionRepository: OnboardingCompletionRepository {
    private(set) var markCompletedCallCount = 0
    private var completed: Bool

    init(hasCompleted: Bool) {
        self.completed = hasCompleted
    }

    var hasCompletedOnboarding: Bool {
        completed
    }

    func markCompleted() {
        markCompletedCallCount += 1
        completed = true
    }
}
