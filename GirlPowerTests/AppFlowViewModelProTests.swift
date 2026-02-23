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

    // MARK: - Helpers

    private func makeViewModel(entitlement: EntitlementServicing) -> AppFlowViewModel {
        AppFlowViewModel(
            repository: OnboardingCompletionRepositoryStub(),
            demoQuotaCoordinator: DemoQuotaCoordinatorStub(),
            entitlementService: entitlement
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
    private let stream: AsyncStream<DemoQuotaStateMachine.State>

    init() {
        self.stream = AsyncStream { continuation in
            continuation.yield(.fresh)
        }
    }

    func prepareForDemoStart() async {}
    func observeStates() -> AsyncStream<DemoQuotaStateMachine.State> { stream }
    func currentState() async -> DemoQuotaStateMachine.State { .fresh }
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
