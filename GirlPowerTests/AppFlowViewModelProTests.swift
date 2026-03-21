import XCTest
@testable import GirlPower

@MainActor
final class AppFlowViewModelProTests: XCTestCase {
    func testDemoButtonTitleForProUserShowsStartCoaching() {
        let entitlement = EntitlementServiceStub(
            initialState: .subscribed(info: .init(product: .mock, transactionID: 1, expirationDate: nil)),
            isPro: true
        )
        let viewModel = makeViewModel(entitlement: entitlement)
        XCTAssertEqual(viewModel.demoButtonTitle, "Start Coaching")
        XCTAssertFalse(viewModel.isDemoButtonDisabled)
        XCTAssertEqual(viewModel.demoStatusMessage, "Unlimited coaching unlocked.")
    }

    func testSummaryCTAUpdatesWhenEntitlementUnlocks() async {
        let entitlement = EntitlementServiceStub(initialState: .ready(product: .mock), isPro: false)
        let viewModel = makeViewModel(entitlement: entitlement)
        let summary = SessionSummary(
            attemptIndex: 1,
            totalReps: 4,
            tempoInsight: .steady,
            averageTempoSeconds: 1.1,
            coachingNotes: [],
            duration: 10,
            generatedAt: Date()
        )
        let context = SummaryContext(summary: summary, ctaState: .awaitingDecision)
        viewModel.presentSummary(context)
        XCTAssertEqual(viewModel.summaryViewModel?.context.ctaState, .awaitingDecision)

        entitlement.send(.subscribed(info: .init(product: .mock, transactionID: 9, expirationDate: nil)), isPro: true)
        await waitForCondition { viewModel.summaryViewModel?.context.ctaState == .proUnlocked }
        XCTAssertEqual(viewModel.summaryViewModel?.context.ctaState, .proUnlocked)
    }

    func testSecondDemoPresentsAuthPromptWhenSessionMissing() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let coordinator = DemoQuotaCoordinatorStub(initialState: .secondAttemptEligible)
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        viewModel.startDemo(reason: "cta_second_demo")

        await waitForCondition { viewModel.authPrompt?.context == .secondDemo }
        XCTAssertEqual(viewModel.demoButtonTitle, "Sign in to continue")
        XCTAssertEqual(viewModel.state, .demoCTA)
    }

    func testSecondDemoStaysFailClosedWhileSessionIsRefreshing() async {
        let auth = AuthServiceStub(initialState: .refreshing(.fixture, context: .secondDemo))
        let coordinator = DemoQuotaCoordinatorStub(initialState: .secondAttemptEligible)
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        XCTAssertEqual(viewModel.demoButtonTitle, "Sign in to continue")

        viewModel.startDemo(reason: "cta_second_demo_refreshing")

        await waitForCondition { viewModel.authPrompt?.context == .secondDemo }
        let startedCount = await coordinator.recordedStartCount()
        XCTAssertEqual(startedCount, 0)
        XCTAssertEqual(viewModel.state, .demoCTA)
    }

    func testSecondDemoWithExistingSessionExecutesImmediatelyAndDoesNotReplay() async {
        let auth = AuthServiceStub(initialState: .authenticated(.fixture))
        auth.ensuredSession = .fixture
        let coordinator = DemoQuotaCoordinatorStub(
            initialState: .secondAttemptEligible,
            startedState: .secondAttemptActive
        )
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        viewModel.startDemo(reason: "cta_second_demo_authenticated")

        await waitForCondition { viewModel.state == .demoStub }
        XCTAssertNil(viewModel.authPrompt)
        let initialStartCount = await coordinator.recordedStartCount()
        XCTAssertEqual(initialStartCount, 1)

        auth.send(.authenticated(.fixture))
        await Task.yield()

        let replayedStartCount = await coordinator.recordedStartCount()
        XCTAssertEqual(replayedStartCount, 1)
    }

    func testPaywallCanProceedAfterAuthSuccess() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let coordinator = DemoQuotaCoordinatorStub(initialState: .fresh)
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )
        let summary = SessionSummary(
            attemptIndex: 2,
            totalReps: 4,
            tempoInsight: .steady,
            averageTempoSeconds: 1.0,
            coachingNotes: [],
            duration: 8,
            generatedAt: Date()
        )

        viewModel.handleSplashFinished()
        viewModel.startDemo(reason: "summary_paywall_test")
        await waitForCondition { viewModel.state == .demoStub }
        viewModel.presentSummary(.init(summary: summary, ctaState: .locked(message: "Quota reached")))
        await waitForCondition { viewModel.state == .sessionSummary }
        viewModel.continueToPaywall()
        await waitForCondition { viewModel.authPrompt?.context == .paywall }

        auth.ensuredSession = .fixture
        auth.send(.authenticated(.fixture))

        await waitForCondition { viewModel.state == .paywall }
        XCTAssertEqual(viewModel.navigationPath.count, 1)

        auth.send(.authenticated(.fixture))
        await Task.yield()

        XCTAssertEqual(viewModel.state, .paywall)
        XCTAssertEqual(viewModel.navigationPath.count, 1)
    }

    func testPendingPaywallFromCTAResumesToPaywallAfterAuthentication() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.state == .demoCTA }

        viewModel.continueToPaywall()
        await waitForCondition { viewModel.authPrompt?.context == .paywall }

        auth.ensuredSession = .fixture
        auth.send(.authenticated(.fixture))

        await waitForCondition { viewModel.state == .paywall }
        XCTAssertNil(viewModel.summaryViewModel)
        XCTAssertEqual(viewModel.navigationPath.count, 1)
    }

    func testPendingSecondDemoOnlyResumesAfterAuthenticatedState() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let coordinator = DemoQuotaCoordinatorStub(
            initialState: .secondAttemptEligible,
            startedState: .secondAttemptActive
        )
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        viewModel.startDemo(reason: "cta_second_demo_wait_for_auth")
        await waitForCondition { viewModel.authPrompt?.context == .secondDemo }

        auth.send(.refreshing(.fixture, context: .secondDemo))
        await Task.yield()
        let countBeforeAuthentication = await coordinator.recordedStartCount()
        XCTAssertEqual(countBeforeAuthentication, 0)

        auth.send(.authenticated(.fixture))
        await waitForCondition { viewModel.state == .demoStub }
        let countAfterAuthentication = await coordinator.recordedStartCount()
        XCTAssertEqual(countAfterAuthentication, 1)
    }

    func testAuthFailureKeepsPromptIdentityStable() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let coordinator = DemoQuotaCoordinatorStub(initialState: .secondAttemptEligible)
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        viewModel.startDemo(reason: "cta_second_demo_identity")
        await waitForCondition { viewModel.authPrompt?.context == .secondDemo }
        let originalPromptID = viewModel.authPrompt?.id

        auth.send(.authFailed(context: .secondDemo, message: "Wrong password", reason: .invalidCredentials))
        await waitForCondition { viewModel.authPrompt?.message == "Wrong password" }

        XCTAssertEqual(viewModel.authPrompt?.id, originalPromptID)
    }

    func testDismissAuthPromptWhileBusyKeepsPendingProtectedAction() async {
        let auth = AuthServiceStub(initialState: .anonymousEligible)
        let coordinator = DemoQuotaCoordinatorStub(
            initialState: .secondAttemptEligible,
            startedState: .secondAttemptActive
        )
        let viewModel = makeViewModel(
            entitlement: EntitlementServiceStub(initialState: .ready(product: .mock)),
            auth: auth,
            coordinator: coordinator
        )

        viewModel.handleSplashFinished()
        await waitForCondition { viewModel.demoQuotaState == .secondAttemptEligible }
        viewModel.startDemo(reason: "cta_second_demo_busy_dismiss")
        await waitForCondition { viewModel.authPrompt?.context == .secondDemo }

        auth.send(.authenticating(method: .emailSignIn, context: .secondDemo))
        await Task.yield()
        viewModel.dismissAuthPrompt()
        XCTAssertNotNil(viewModel.authPrompt)

        auth.send(.authenticated(.fixture))
        await waitForCondition { viewModel.state == .demoStub }

        let startedCount = await coordinator.recordedStartCount()
        XCTAssertEqual(startedCount, 1)
    }

    // MARK: - Helpers

    private func makeViewModel(
        entitlement: any EntitlementServicing,
        auth: (any AuthServicing)? = nil,
        coordinator: DemoQuotaCoordinating = DemoQuotaCoordinatorStub()
    ) -> AppFlowViewModel {
        AppFlowViewModel(
            repository: OnboardingCompletionRepositoryStub(),
            demoQuotaCoordinator: coordinator,
            entitlementService: entitlement,
            authService: auth
        )
    }

    private func waitForCondition(timeout: TimeInterval = 1.0, condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }
}

private final class OnboardingCompletionRepositoryStub: OnboardingCompletionRepository {
    var hasCompletedOnboarding: Bool = true
    func markCompleted() { hasCompletedOnboarding = true }
}

private actor DemoQuotaCoordinatorStub: DemoQuotaCoordinating {
    private var continuation: AsyncStream<DemoQuotaStateMachine.State>.Continuation?
    private let stream: AsyncStream<DemoQuotaStateMachine.State>
    private let initialState: DemoQuotaStateMachine.State
    private let startedState: DemoQuotaStateMachine.State
    private var startCallCount = 0

    init(
        initialState: DemoQuotaStateMachine.State = .fresh,
        startedState: DemoQuotaStateMachine.State = .firstAttemptActive
    ) {
        self.initialState = initialState
        self.startedState = startedState
        var capturedContinuation: AsyncStream<DemoQuotaStateMachine.State>.Continuation?
        self.stream = AsyncStream { continuation in
            capturedContinuation = continuation
            continuation.yield(initialState)
        }
        self.continuation = capturedContinuation
    }

    func prepareForDemoStart() async {}
    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State> { stream }
    func currentState() async -> DemoQuotaStateMachine.State { initialState }
    func markAttemptStarted(startMetadata: [String : Any]) async throws -> DemoQuotaStateMachine.State {
        startCallCount += 1
        continuation?.yield(startedState)
        return startedState
    }
    func markAttemptCompleted(resultMetadata: [String : Any]) async -> DemoQuotaStateMachine.State { .gatePending }
    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async {}

    func recordedStartCount() -> Int { startCallCount }
}

@MainActor
private extension PaywallProduct {
    static var mock: PaywallProduct {
        PaywallProduct(id: "pro", displayName: "Girl Power Coaching", displayPrice: "$19.99", periodDescription: "month", features: [])
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
