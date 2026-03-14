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

    init(initialState: DemoQuotaStateMachine.State = .fresh) {
        self.initialState = initialState
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
    func markAttemptStarted(startMetadata: [String : Any]) async throws -> DemoQuotaStateMachine.State { .firstAttemptActive }
    func markAttemptCompleted(resultMetadata: [String : Any]) async -> DemoQuotaStateMachine.State { .gatePending }
    func resetFromServer(snapshot: DemoQuotaStateMachine.RemoteSnapshot) async {}
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
