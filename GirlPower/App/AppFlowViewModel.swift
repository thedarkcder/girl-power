import OSLog
import SwiftUI

@MainActor
final class AppFlowViewModel: ObservableObject {
    enum Route: Hashable {
        case demoStub
        case paywall
    }

    @Published private(set) var state: AppFlowStateMachine.State
    @Published var navigationPath = NavigationPath()
    @Published private(set) var demoQuotaState: DemoQuotaStateMachine.State = .fresh
    @Published private(set) var summaryViewModel: SquatPostSetSummaryViewModel?

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

    var activeAttemptIndex: Int {
        currentAttemptIndex
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
    private let paywallRouter: PaywallRouting
    private var stateTask: Task<Void, Never>?
    private var currentAttemptIndex: Int = 1
    private let logger = Logger(subsystem: "com.girlpower.app", category: "AppFlow")

    init(
        repository: OnboardingCompletionRepository,
        demoQuotaCoordinator: DemoQuotaCoordinating,
        paywallRouter: PaywallRouting = PaywallRouter(),
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
        self.paywallRouter = paywallRouter
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
        summaryViewModel = nil
        let metadata: [String: Any] = [
            "reason": reason,
            "cta_label": demoButtonTitle,
            "timestamp": isoFormatter.string(from: Date())
        ]
        Task {
            let newState = try? await demoQuotaCoordinator.markAttemptStarted(startMetadata: metadata)
            await MainActor.run {
                if let startState = newState {
                    switch startState {
                    case .firstAttemptActive:
                        self.currentAttemptIndex = 1
                    case .secondAttemptActive:
                        self.currentAttemptIndex = 2
                    default:
                        break
                    }
                }
                if newState != nil {
                    apply(event: .startDemo)
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

    func completeAttempt(with input: SessionSummaryInput) async -> SummaryContext {
        let metadata = summaryMetadata(from: input)
        let newState = await demoQuotaCoordinator.markAttemptCompleted(resultMetadata: metadata)
        let summary = SessionSummaryFactory.make(from: input)
        let resolvedState = newState ?? demoQuotaState
        demoQuotaState = resolvedState
        currentAttemptIndex = min(summary.attemptIndex + 1, 2)
        navigationPath = NavigationPath()
        let context = SummaryContext(summary: summary, ctaState: summaryCTAState(for: resolvedState, attemptIndex: summary.attemptIndex))
        presentSummary(context)
        return context
    }

    func presentSummary(_ context: SummaryContext) {
        let adjustedCTA = summaryCTAState(for: demoQuotaState, attemptIndex: context.summary.attemptIndex)
        let adjustedContext = SummaryContext(summary: context.summary, ctaState: adjustedCTA)
        summaryViewModel = SquatPostSetSummaryViewModel(context: adjustedContext)
        apply(event: .showSummary)
    }

    func startSecondAttemptFromSummary() {
        guard summaryViewModel != nil else {
            logger.notice("Ignoring One More Go tap because summary is no longer active")
            return
        }
        summaryViewModel = nil
        startDemo(reason: "summary_one_more_go")
    }

    func continueToPaywall() {
        guard state != .paywall else {
            logger.notice("Ignoring duplicate paywall navigation request while already presenting")
            return
        }
        navigationPath = NavigationPath()
        let attemptIndex = summaryViewModel?.context.summary.attemptIndex ?? currentAttemptIndex
        summaryViewModel = nil
        paywallRouter.presentPaywall()
        apply(event: .showPaywall)
        currentAttemptIndex = min(attemptIndex + 1, 2)
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
        case .paywall:
            navigationPath = NavigationPath()
            navigationPath.append(Route.paywall)
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
                    if let summaryVM = summaryViewModel {
                        let attempt = summaryVM.context.summary.attemptIndex
                        let ctaState = summaryCTAState(for: newState, attemptIndex: attempt)
                        summaryVM.updateCTAState(ctaState)
                    }
                }
            }
        }
    }

    private func summaryCTAState(for quotaState: DemoQuotaStateMachine.State, attemptIndex: Int) -> SummaryCTAState {
        switch quotaState {
        case .gatePending:
            if attemptIndex > 1 {
                logSummaryMismatch("Gate pending after second attempt", attemptIndex: attemptIndex, quotaState: quotaState)
            }
            return .awaitingDecision
        case .secondAttemptEligible:
            guard attemptIndex == 1 else {
                logSummaryMismatch("Second attempt eligible state with attempt index \(attemptIndex)", attemptIndex: attemptIndex, quotaState: quotaState)
                return .locked(message: DemoQuotaStateMachine.LockReason.quotaExhausted.userFacingMessage)
            }
            return .secondAttemptEligible
        case .locked(let reason):
            return .locked(message: reason.userFacingMessage)
        default:
            if attemptIndex >= 2 {
                if quotaState.isLocked == false {
                    logSummaryMismatch("Forcing lock due to attempt index despite quota state", attemptIndex: attemptIndex, quotaState: quotaState)
                }
                return .locked(message: DemoQuotaStateMachine.LockReason.quotaExhausted.userFacingMessage)
            }
            if attemptIndex == 1 && quotaState != .gatePending {
                logSummaryMismatch("Unexpected quota state for attempt index 1", attemptIndex: attemptIndex, quotaState: quotaState)
            }
            return .awaitingDecision
        }
    }

    private func summaryMetadata(from input: SessionSummaryInput) -> [String: Any] {
        var corrections: [String: Int] = [:]
        input.snapshot.correctionCounts.forEach { key, value in
            corrections[key.rawValue] = value
        }
        return [
            "attempt_index": input.attemptIndex,
            "duration_seconds": input.duration,
            "repetition_count": input.snapshot.repetitionCount,
            "tempo_samples": input.snapshot.tempoSamples,
            "coaching_corrections": corrections,
            "generated_at": isoFormatter.string(from: input.generatedAt)
        ]
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func logSummaryMismatch(
        _ message: String,
        attemptIndex: Int,
        quotaState: DemoQuotaStateMachine.State
    ) {
        logger.error("Summary CTA mismatch: \(message, privacy: .public) [attempt=\(attemptIndex, privacy: .public) state=\(String(describing: quotaState), privacy: .public)]")
    }
}
