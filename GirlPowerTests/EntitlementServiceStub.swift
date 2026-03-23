import Foundation
@testable import GirlPower

@MainActor
final class EntitlementServiceStub: ObservableObject, EntitlementServicing {
    @Published var state: EntitlementState
    var isPro: Bool
    private(set) var authenticatedProfile: Profile?
    private let stream: AsyncStream<EntitlementState>
    private let continuation: AsyncStream<EntitlementState>.Continuation

    init(initialState: EntitlementState = .loading, isPro: Bool = false) {
        self.state = initialState
        self.isPro = isPro
        var captured: AsyncStream<EntitlementState>.Continuation!
        self.stream = AsyncStream { continuation in
            captured = continuation
            continuation.yield(initialState)
        }
        self.continuation = captured
    }

    func load() async {}
    func purchase() async {}
    func restore() async {}
    func updateAuthenticatedContext(session: AuthSession?, profile: Profile?) async {
        authenticatedProfile = profile
        if let profile {
            isPro = profile.isPro
        }
    }

    func observeStates() -> AsyncStream<EntitlementState> {
        stream
    }

    func send(_ newState: EntitlementState, isPro: Bool) {
        state = newState
        self.isPro = isPro
        continuation.yield(newState)
    }
}

@MainActor
final class AuthServiceStub: ObservableObject, AuthServicing {
    @Published private(set) var state: AuthState

    var ensuredSession: AuthSession?
    var pendingAnonymousSessionID: UUID?
    var synchronizedContextResult: PostAuthenticationSyncResult?
    private let stream: AsyncStream<AuthState>
    private let continuation: AsyncStream<AuthState>.Continuation

    init(initialState: AuthState = .anonymousEligible) {
        self.state = initialState
        var captured: AsyncStream<AuthState>.Continuation!
        self.stream = AsyncStream { continuation in
            captured = continuation
            continuation.yield(initialState)
        }
        self.continuation = captured
    }

    func observeStates() -> AsyncStream<AuthState> { stream }
    func restoreSession() async {}
    func handleAppDidBecomeActive() async {}

    func requireAuthentication(context: AuthRequirementContext, message: String) async {
        send(.authRequired(context: context, message: message))
    }

    func dismissFailure() async {
        send(.anonymousEligible)
    }

    func ensureValidSession(for context: AuthRequirementContext) async -> AuthSession? {
        if let ensuredSession {
            send(.authenticated(ensuredSession))
            return ensuredSession
        }
        send(.authRequired(context: context, message: context.defaultMessage))
        return nil
    }

    func synchronizeAuthenticatedContext(for session: AuthSession) async -> PostAuthenticationSyncResult? {
        synchronizedContextResult
    }

    func signIn(email: String, password: String, context: AuthRequirementContext) async {
        guard let ensuredSession else { return }
        send(.authenticated(ensuredSession))
    }

    func signUp(email: String, password: String, context: AuthRequirementContext) async {
        guard let ensuredSession else { return }
        send(.authenticated(ensuredSession))
    }

    func signInWithApple(identityToken: String, nonce: String, context: AuthRequirementContext) async {
        guard let ensuredSession else { return }
        send(.authenticated(ensuredSession))
    }

    func signOut() async {
        send(.anonymousEligible)
    }

    func beginAnonymousSessionIfNeeded() -> UUID? {
        pendingAnonymousSessionID
    }

    func send(_ newState: AuthState) {
        state = newState
        continuation.yield(newState)
    }
}
