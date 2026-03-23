import AuthenticationServices
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
    @Published private(set) var entitlementState: EntitlementState
    @Published private(set) var isProUser: Bool
    @Published private(set) var authState: AuthState
    @Published var authPrompt: AuthPrompt?

    var demoButtonTitle: String {
        if isProUser {
            return "Start Coaching"
        }
        if demoQuotaState == .secondAttemptEligible && authState.isAuthenticated == false {
            return "Sign in to continue"
        }
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
        if isProUser {
            return false
        }
        if demoQuotaState == .secondAttemptEligible && authState.isAuthenticated == false {
            return false
        }
        return demoQuotaState.isLocked || demoQuotaState == .gatePending
    }

    var activeAttemptIndex: Int {
        currentAttemptIndex
    }

    var demoStatusMessage: String? {
        if isProUser {
            return "Unlimited coaching unlocked."
        }
        if demoQuotaState == .secondAttemptEligible && authState.isAuthenticated == false {
            return AuthRequirementContext.secondDemo.defaultMessage
        }
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

    var paywallEntitlementService: any EntitlementServicing {
        entitlementService
    }

    var isAuthBusy: Bool {
        switch authState {
        case .authenticating, .refreshing:
            return true
        default:
            return false
        }
    }

    private let stateMachine: AppFlowStateMachine
    private let repository: OnboardingCompletionRepository
    private let demoQuotaCoordinator: DemoQuotaCoordinating
    private let entitlementService: any EntitlementServicing
    private let authService: any AuthServicing
    private var stateTask: Task<Void, Never>?
    private var entitlementTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var profileSyncTask: Task<Void, Never>?
    private var authenticatedContextTask: Task<Void, Never>?
    private var currentAttemptIndex: Int = 1
    private var activeAnonymousSessionID: UUID?
    private var pendingProtectedAction: ProtectedAction?
    private var appleSignInNonce: String?
    private var skipOnboardingAfterSplash: Bool
    private let logger = Logger(subsystem: "com.girlpower.app", category: "AppFlow")

    private enum ProtectedAction {
        case secondDemo(reason: String)
        case paywall
    }

    init(
        repository: OnboardingCompletionRepository,
        demoQuotaCoordinator: DemoQuotaCoordinating,
        entitlementService: any EntitlementServicing,
        authService: (any AuthServicing)? = nil,
        slides: [OnboardingSlide] = OnboardingSlide.defaultSlides,
        stateMachine: AppFlowStateMachine? = nil
    ) {
        self.repository = repository
        self.demoQuotaCoordinator = demoQuotaCoordinator
        self.entitlementService = entitlementService
        self.authService = authService ?? DisabledAuthService()
        self.slides = slides
        self.stateMachine = stateMachine ?? AppFlowStateMachine(slideCount: slides.count)
        self.state = self.stateMachine.initialState()
        self.entitlementState = entitlementService.state
        self.isProUser = entitlementService.isPro
        self.authState = self.authService.state
        self.skipOnboardingAfterSplash = repository.hasCompletedOnboarding
        syncNavigation(for: state)
        observeDemoQuota()
        observeEntitlements()
        observeAuth()
    }

    deinit {
        stateTask?.cancel()
        entitlementTask?.cancel()
        authTask?.cancel()
        profileSyncTask?.cancel()
        authenticatedContextTask?.cancel()
    }

    func handleSplashFinished() {
        apply(event: skipOnboardingAfterSplash ? .restoreCompletedOnboarding : .splashFinished)
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
        skipOnboardingAfterSplash = true
        if let session = authState.session {
            profileSyncTask?.cancel()
            profileSyncTask = Task { [weak self] in
                guard let self else { return }
                _ = await self.repository.syncWithProfile(using: session)
            }
        }
        apply(event: .onboardingCompleted)
    }

    func handleAppDidBecomeActive() {
        Task {
            await authService.handleAppDidBecomeActive()
        }
    }

    func startDemo(reason: String = "cta_tap") {
        if isProUser {
            startUnlimitedSession(reason: reason)
            return
        }
        guard isDemoButtonDisabled == false else { return }
        if demoQuotaState == .secondAttemptEligible {
            executeProtectedAction(
                .secondDemo(reason: reason),
                context: .secondDemo,
                onAuthorized: { viewModel in
                    if viewModel.isProUser {
                        viewModel.startUnlimitedSession(reason: reason)
                    } else {
                        viewModel.startTrackedDemo(reason: reason)
                    }
                }
            )
            return
        }
        startTrackedDemo(reason: reason)
    }

    func dismissAuthPrompt() {
        guard authStateIsBusy(authService.state) == false else { return }
        authPrompt = nil
        pendingProtectedAction = nil
    }

    func submitEmailSignIn(email: String, password: String) {
        let context = authPrompt?.context ?? .retry
        Task {
            await authService.signIn(email: email, password: password, context: context)
        }
    }

    func submitEmailSignUp(email: String, password: String) {
        let context = authPrompt?.context ?? .retry
        Task {
            await authService.signUp(email: email, password: password, context: context)
        }
    }

    func prepareAppleSignIn(request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.makeRawNonce()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    func completeAppleSignIn(result: Result<ASAuthorization, Error>) {
        let context = authPrompt?.context ?? .retry
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleSignInNonce else {
                Task {
                    await authService.requireAuthentication(
                        context: context,
                        message: "Apple Sign In did not return a valid credential."
                    )
                }
                return
            }
            Task {
                await authService.signInWithApple(identityToken: identityToken, nonce: nonce, context: context)
            }
        case .failure:
            Task {
                await authService.requireAuthentication(
                    context: context,
                    message: "Apple Sign In was cancelled before Supabase could create a session."
                )
            }
        }
    }

    private func startUnlimitedSession(reason: String) {
        summaryViewModel = nil
        logger.log("Starting unlimited coaching session (\(reason))")
        apply(event: .startDemo)
    }

    func finishDemo(reason: String = "user_exit") {
        let metadata: [String: Any] = [
            "reason": reason,
            "timestamp": isoFormatter.string(from: Date())
        ]
        Task {
            _ = await demoQuotaCoordinator.markAttemptCompleted(resultMetadata: metadata)
            await MainActor.run {
                self.activeAnonymousSessionID = nil
                apply(event: .finishDemo)
            }
        }
    }

    func completeAttempt(with input: SessionSummaryInput) async -> SummaryContext {
        let summary = SessionSummaryFactory.make(from: input)
        let resolvedState: DemoQuotaStateMachine.State
        if isProUser {
            resolvedState = demoQuotaState
        } else {
            let metadata = summaryMetadata(from: input)
            let newState = await demoQuotaCoordinator.markAttemptCompleted(resultMetadata: metadata)
            resolvedState = newState
            demoQuotaState = resolvedState
        }
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

    func startNextAttemptFromSummary() {
        guard summaryViewModel != nil else {
            logger.notice("Ignoring summary primary action because summary is no longer active")
            return
        }
        summaryViewModel = nil
        if isProUser {
            startUnlimitedSession(reason: "summary_pro_start")
        } else {
            startDemo(reason: "summary_one_more_go")
        }
    }

    func continueToPaywall() {
        guard isProUser == false else {
            logger.notice("Skipping paywall routing because entitlement already unlocked")
            return
        }
        executeProtectedAction(
            .paywall,
            context: .paywall,
            onAuthorized: { viewModel in
                if viewModel.isProUser {
                    viewModel.handleProUnlocked()
                } else {
                    viewModel.presentPaywall()
                }
            }
        )
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

    private func observeEntitlements() {
        entitlementTask = Task {
            let stream = entitlementService.observeStates()
            for await newState in stream {
                await MainActor.run {
                    entitlementState = newState
                    let previouslyPro = isProUser
                    isProUser = entitlementService.isPro
                    if let summaryVM = summaryViewModel {
                        let attempt = summaryVM.context.summary.attemptIndex
                        let ctaState = summaryCTAState(for: demoQuotaState, attemptIndex: attempt)
                        summaryVM.updateCTAState(ctaState)
                    }
                    if isProUser && !previouslyPro {
                        handleProUnlocked()
                    }
                }
            }
        }
    }

    private func observeAuth() {
        authTask = Task {
            let stream = authService.observeStates()
            for await newState in stream {
                await MainActor.run {
                    authState = newState
                    if case .authenticated(let session) = newState {
                        authPrompt = nil
                        authenticatedContextTask?.cancel()
                        authenticatedContextTask = Task { [weak self] in
                            guard let self else { return }
                            await self.refreshAuthenticatedContext(for: session)
                            guard Task.isCancelled == false else { return }
                            await MainActor.run {
                                self.resumePendingProtectedActionIfNeeded()
                                self.scheduleAuthenticatedProfileSync(for: session)
                            }
                        }
                    } else if case .authRequired(let context, let message) = newState {
                        authPrompt = AuthPrompt(context: context, message: message)
                    } else if case .authFailed(let context, let message, _) = newState {
                        authPrompt = AuthPrompt(context: context, message: message)
                    }
                    if newState.session == nil {
                        authenticatedContextTask?.cancel()
                        profileSyncTask?.cancel()
                        Task { await self.entitlementService.updateAuthenticatedContext(session: nil, profile: nil) }
                    }
                }
            }
        }
    }

    private func handleProUnlocked() {
        logger.log("Entitlement unlocked; dismissing paywall if needed")
        if state == .paywall {
            finishDemo(reason: "paywall_purchase_success")
        }
    }

    private func summaryCTAState(for quotaState: DemoQuotaStateMachine.State, attemptIndex: Int) -> SummaryCTAState {
        if isProUser {
            return .proUnlocked
        }
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
        ].merging(anonymousSessionMetadata()) { current, _ in current }
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func startTrackedDemo(reason: String) {
        summaryViewModel = nil
        let anonymousSessionID = authService.beginAnonymousSessionIfNeeded()
        activeAnonymousSessionID = anonymousSessionID
        var metadata: [String: Any] = [
            "reason": reason,
            "cta_label": demoButtonTitle,
            "timestamp": isoFormatter.string(from: Date())
        ]
        if let anonymousSessionID {
            metadata["anon_session_id"] = anonymousSessionID.uuidString
        }
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

    private func anonymousSessionMetadata() -> [String: Any] {
        guard let activeAnonymousSessionID else { return [:] }
        return ["anon_session_id": activeAnonymousSessionID.uuidString]
    }

    private func presentAuthPrompt(context: AuthRequirementContext, message: String) {
        authPrompt = AuthPrompt(context: context, message: message)
    }

    private func promptMessage(for context: AuthRequirementContext) -> String {
        switch authState {
        case .authRequired(let promptContext, let message) where promptContext == context:
            return message
        case .authFailed(let promptContext, let message, _) where promptContext == context:
            return message
        default:
            return context.defaultMessage
        }
    }

    private func executeProtectedAction(
        _ protectedAction: ProtectedAction,
        context: AuthRequirementContext,
        onAuthorized: @escaping @MainActor (AppFlowViewModel) -> Void
    ) {
        Task {
            guard let session = await authService.ensureValidSession(for: context) else {
                await MainActor.run {
                    self.pendingProtectedAction = protectedAction
                    self.presentAuthPrompt(context: context, message: self.promptMessage(for: context))
                }
                return
            }
            await refreshAuthenticatedContext(for: session)
            await MainActor.run {
                onAuthorized(self)
            }
        }
    }

    private func resumePendingProtectedActionIfNeeded() {
        guard let action = pendingProtectedAction else { return }
        pendingProtectedAction = nil
        switch action {
        case .secondDemo(let reason):
            if isProUser {
                startUnlimitedSession(reason: reason)
                return
            }
            startTrackedDemo(reason: reason)
        case .paywall:
            guard isProUser == false else {
                handleProUnlocked()
                return
            }
            presentPaywall()
        }
    }

    private func refreshAuthenticatedContext(for session: AuthSession) async {
        let syncResult = await authService.synchronizeAuthenticatedContext(for: session)
        if let snapshot = syncResult?.mergedDemoQuotaSnapshot {
            demoQuotaState = DemoQuotaStateMachine().state(from: snapshot)
            await demoQuotaCoordinator.resetFromServer(snapshot: snapshot)
        }
        await entitlementService.updateAuthenticatedContext(session: session, profile: syncResult?.profile)
        let previouslyPro = isProUser
        isProUser = entitlementService.isPro
        if let summaryVM = summaryViewModel {
            let attempt = summaryVM.context.summary.attemptIndex
            let ctaState = summaryCTAState(for: demoQuotaState, attemptIndex: attempt)
            summaryVM.updateCTAState(ctaState)
        }
        if isProUser && !previouslyPro {
            handleProUnlocked()
        }
    }

    private func presentPaywall() {
        guard state != .paywall else {
            logger.notice("Ignoring duplicate paywall navigation request while already presenting")
            return
        }
        navigationPath = NavigationPath()
        let attemptIndex = summaryViewModel?.context.summary.attemptIndex ?? currentAttemptIndex
        summaryViewModel = nil
        apply(event: .showPaywall)
        currentAttemptIndex = min(attemptIndex + 1, 2)
    }

    private func logSummaryMismatch(
        _ message: String,
        attemptIndex: Int,
        quotaState: DemoQuotaStateMachine.State
    ) {
        logger.error("Summary CTA mismatch: \(message, privacy: .public) [attempt=\(attemptIndex, privacy: .public) state=\(String(describing: quotaState), privacy: .public)]")
    }

    private func authStateIsBusy(_ state: AuthState) -> Bool {
        switch state {
        case .authenticating, .refreshing:
            return true
        default:
            return false
        }
    }

    private func scheduleAuthenticatedProfileSync(for session: AuthSession) {
        profileSyncTask?.cancel()
        profileSyncTask = Task { [weak self] in
            guard let self else { return }
            let completed = await self.repository.syncWithProfile(using: session)
            guard Task.isCancelled == false else { return }
            if completed {
                await MainActor.run {
                    self.skipOnboardingAfterSplash = true
                    if case .onboarding = self.state {
                        self.apply(event: .restoreCompletedOnboarding)
                    }
                }
            }
        }
    }
}
