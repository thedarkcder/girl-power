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

    func testShowSummaryFromDemoStub() {
        let summary = stateMachine.transition(from: .demoStub, event: .showSummary)
        XCTAssertEqual(summary, .sessionSummary)
    }

    func testSummaryStartDemoRoutesBackToStub() {
        let next = stateMachine.transition(from: .sessionSummary, event: .startDemo)
        XCTAssertEqual(next, .demoStub)
    }

    func testSummaryShowPaywallRoutesToPaywall() {
        let next = stateMachine.transition(from: .sessionSummary, event: .showPaywall)
        XCTAssertEqual(next, .paywall)
    }
}

@MainActor
final class AppFlowViewModelTests: XCTestCase {
    func testCompleteOnboardingPersistsFlagAndMovesToCTA() {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: false)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: DemoQuotaCoordinatorDisabled(),
            entitlementService: EntitlementServiceStub()
        )

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
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: DemoQuotaCoordinatorDisabled(),
            entitlementService: EntitlementServiceStub()
        )

        XCTAssertEqual(viewModel.state, .splash)
        viewModel.handleSplashFinished()
        XCTAssertEqual(viewModel.state, .demoCTA)

        let toStub = expectation(description: "routes to demo stub")
        let stubMonitor = Task {
            while viewModel.state != .demoStub {
                await Task.yield()
            }
            toStub.fulfill()
        }
        viewModel.startDemo()
        wait(for: [toStub], timeout: 1.0)
        stubMonitor.cancel()
        XCTAssertEqual(viewModel.state, .demoStub)
        XCTAssertFalse(viewModel.navigationPath.isEmpty)

        let backToCTA = expectation(description: "returns to CTA")
        let ctaMonitor = Task {
            while viewModel.state != .demoCTA {
                await Task.yield()
            }
            backToCTA.fulfill()
        }
        viewModel.finishDemo()
        wait(for: [backToCTA], timeout: 1.0)
        ctaMonitor.cancel()
        XCTAssertEqual(viewModel.state, .demoCTA)
        XCTAssertTrue(viewModel.navigationPath.isEmpty)
    }

    func testCompleteAttemptShowsSummary() async {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: true)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: DemoQuotaCoordinatorDisabled(),
            entitlementService: EntitlementServiceStub()
        )

        viewModel.handleSplashFinished()
        viewModel.startDemo()
        let stubExpectation = expectation(description: "demo stub ready")
        let stubMonitor = Task {
            while viewModel.state != .demoStub {
                await Task.yield()
            }
            stubExpectation.fulfill()
        }
        await fulfillment(of: [stubExpectation], timeout: 1.0)
        stubMonitor.cancel()

        let input = SessionSummaryInput(
            attemptIndex: 1,
            snapshot: RepCounter.Snapshot(
                repetitionCount: 3,
                tempoSamples: [1.2, 1.3],
                correctionCounts: [:]
            ),
            duration: 10,
            generatedAt: Date()
        )

        let context = await viewModel.completeAttempt(with: input)
        XCTAssertEqual(context.summary.totalReps, 3)
        XCTAssertEqual(viewModel.state, .sessionSummary)
        XCTAssertNotNil(viewModel.summaryViewModel)
    }

    func testSummaryCTARespondsToQuotaStateChanges() async {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: true)
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .gatePending)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub()
        )

        await waitForCondition { viewModel.demoQuotaState == .gatePending }

        let context = SummaryContext(summary: makeSummary(attemptIndex: 1), ctaState: .awaitingDecision)
        viewModel.presentSummary(context)
        XCTAssertEqual(viewModel.summaryViewModel?.primaryButtonTitle, "Checking eligibility…")

        await coordinator.updateState(.secondAttemptEligible)
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        await waitForCondition { viewModel.summaryViewModel?.primaryButtonTitle == "One more go" }
        XCTAssertTrue(viewModel.summaryViewModel?.isSecondaryButtonVisible ?? false)
    }

    func testAttemptTwoSummaryAlwaysLocks() async {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: true)
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .secondAttemptEligible)
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub()
        )

        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }

        let context = SummaryContext(summary: makeSummary(attemptIndex: 2), ctaState: .secondAttemptEligible)
        viewModel.presentSummary(context)
        XCTAssertEqual(viewModel.summaryViewModel?.primaryButtonTitle, "Continue to Paywall")
        XCTAssertFalse(viewModel.summaryViewModel?.isSecondaryButtonVisible ?? true)
        XCTAssertEqual(
            viewModel.summaryViewModel?.statusMessage,
            DemoQuotaStateMachine.LockReason.quotaExhausted.userFacingMessage
        )
    }

    func testContinueToPaywallClearsSummaryAndRoutes() async {
        let repository = FakeOnboardingCompletionRepository(hasCompleted: true)
        let coordinator = DemoQuotaCoordinatorStreamStub(initialState: .fresh)
        let router = PaywallRouterSpy()
        let auth = AuthServiceStub(initialState: .authenticated(.fixture))
        auth.ensuredSession = .fixture
        let viewModel = AppFlowViewModel(
            repository: repository,
            demoQuotaCoordinator: coordinator,
            entitlementService: EntitlementServiceStub(),
            authService: auth,
            paywallRouter: router
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.state == .demoCTA }
        viewModel.startDemo()
        await waitForCondition { viewModel.state == .demoStub }

        let context = SummaryContext(summary: makeSummary(attemptIndex: 2), ctaState: .locked(message: "Denied"))
        viewModel.presentSummary(context)
        await waitForCondition { viewModel.state == .sessionSummary }

        viewModel.continueToPaywall()

        await waitForCondition { viewModel.state == .paywall }
        XCTAssertNil(viewModel.summaryViewModel)
        XCTAssertEqual(viewModel.state, .paywall)
        XCTAssertEqual(viewModel.navigationPath.count, 1)
        XCTAssertEqual(router.presentCallCount, 1)
    }

    private func makeSummary(attemptIndex: Int) -> SessionSummary {
        SessionSummary(
            attemptIndex: attemptIndex,
            totalReps: 5,
            tempoInsight: .steady,
            averageTempoSeconds: 1.1,
            coachingNotes: [],
            duration: 15,
            generatedAt: Date()
        )
    }

    private func waitForCondition(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async {
        let conditionExpectation = expectation(description: "condition met")
        let monitor = Task {
            while !condition() {
                await Task.yield()
            }
            conditionExpectation.fulfill()
        }
        await fulfillment(of: [conditionExpectation], timeout: timeout)
        monitor.cancel()
    }
}

@MainActor
final class AppStartupWorkTests: XCTestCase {
    func testBootstrapLoadsEntitlementsWithoutWaitingForAuthRestore() async {
        let authService = BlockingStartupAuthService()
        let entitlementService = StartupEntitlementServiceSpy()

        let bootstrapTask = Task {
            await AppStartupWork.bootstrap(
                authService: authService,
                entitlementService: entitlementService
            )
        }

        await waitForCondition {
            authService.didStartRestore && entitlementService.loadCallCount == 1
        }

        XCTAssertEqual(authService.restoreCallCount, 1)
        XCTAssertEqual(entitlementService.loadCallCount, 1)

        authService.resumeRestore()
        await bootstrapTask.value
    }

    private func waitForCondition(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async {
        let conditionExpectation = expectation(description: "condition met")
        let monitor = Task {
            while !condition() {
                await Task.yield()
            }
            conditionExpectation.fulfill()
        }
        await fulfillment(of: [conditionExpectation], timeout: timeout)
        monitor.cancel()
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

private final class PaywallRouterSpy: PaywallRouting {
    private(set) var presentCallCount = 0

    func presentPaywall() {
        presentCallCount += 1
    }
}

private extension AuthSession {
    static var fixture: AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
    }
}

@MainActor
private final class BlockingStartupAuthService: ObservableObject, AuthServicing {
    @Published private(set) var state: AuthState = .anonymousEligible

    private var restoreContinuation: CheckedContinuation<Void, Never>?
    private(set) var restoreCallCount = 0
    private(set) var didStartRestore = false

    func observeStates() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }

    func restoreSession() async {
        restoreCallCount += 1
        didStartRestore = true
        await withCheckedContinuation { continuation in
            restoreContinuation = continuation
        }
    }

    func resumeRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }

    func handleAppDidBecomeActive() async {}
    func requireAuthentication(context: AuthRequirementContext, message: String) async {}
    func dismissFailure() async {}
    func ensureValidSession(for context: AuthRequirementContext) async -> AuthSession? { nil }
    func signIn(email: String, password: String, context: AuthRequirementContext) async {}
    func signUp(email: String, password: String, context: AuthRequirementContext) async {}
    func signInWithApple(identityToken: String, nonce: String, context: AuthRequirementContext) async {}
    func signOut() async {}
    func beginAnonymousSessionIfNeeded() -> UUID? { nil }
}

@MainActor
private final class StartupEntitlementServiceSpy: ObservableObject, EntitlementServicing {
    @Published var state: EntitlementState = .loading
    var isPro: Bool = false
    private(set) var loadCallCount = 0

    func load() async {
        loadCallCount += 1
    }

    func purchase() async {}
    func restore() async {}

    func observeStates() -> AsyncStream<EntitlementState> {
        AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }
}
