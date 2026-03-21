import CryptoKit
import Foundation
import OSLog
import Security

enum AuthRequirementContext: String, Codable, Equatable {
    case secondDemo
    case paywall
    case restore
    case retry

    var defaultMessage: String {
        switch self {
        case .secondDemo:
            return "Create an account or sign in to unlock your second demo."
        case .paywall:
            return "Sign in before continuing to subscriptions."
        case .restore:
            return "Restore your session to keep access to protected actions."
        case .retry:
            return "Sign in again to retry this action."
        }
    }
}

enum AuthMethod: String, Codable, Equatable {
    case emailSignIn
    case emailSignUp
    case apple
}

enum AuthFailureReason: String, Codable, Equatable {
    case invalidCredentials
    case networkUnavailable
    case refreshRejected
    case unexpectedResponse
    case appleCredentialInvalid
    case cancelled
}

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var shouldRefreshSoon: Bool {
        expiresAt <= Date().addingTimeInterval(120)
    }
}

enum AuthState: Equatable {
    case anonymousEligible
    case authRequired(context: AuthRequirementContext, message: String)
    case authenticating(method: AuthMethod, context: AuthRequirementContext)
    case authenticated(AuthSession)
    case refreshing(AuthSession, context: AuthRequirementContext?)
    case authFailed(context: AuthRequirementContext, message: String, reason: AuthFailureReason)

    var session: AuthSession? {
        switch self {
        case .authenticated(let session):
            return session
        case .refreshing(let session, _):
            return session
        default:
            return nil
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
}

struct AuthStateMachine {
    enum Event {
        case requireAuthentication(context: AuthRequirementContext, message: String)
        case beginAuthentication(method: AuthMethod, context: AuthRequirementContext)
        case restoreSession(AuthSession)
        case beginRefresh(AuthSession, context: AuthRequirementContext?)
        case authenticationSucceeded(AuthSession)
        case authenticationFailed(context: AuthRequirementContext, message: String, reason: AuthFailureReason)
        case clearAuthentication
        case signOut
    }

    func transition(from state: AuthState, event: Event) -> AuthState {
        switch event {
        case .requireAuthentication(let context, let message):
            return .authRequired(context: context, message: message)
        case .beginAuthentication(let method, let context):
            return .authenticating(method: method, context: context)
        case .restoreSession(let session),
             .authenticationSucceeded(let session):
            return .authenticated(session)
        case .beginRefresh(let session, let context):
            return .refreshing(session, context: context)
        case .authenticationFailed(let context, let message, let reason):
            return .authFailed(context: context, message: message, reason: reason)
        case .clearAuthentication:
            if case .authFailed(let context, _, _) = state {
                return .authRequired(context: context, message: context.defaultMessage)
            }
            return .anonymousEligible
        case .signOut:
            return .anonymousEligible
        }
    }
}

struct AuthPrompt: Identifiable, Equatable {
    var id: String { context.rawValue }
    let context: AuthRequirementContext
    let message: String
}

struct SupabaseProjectConfiguration {
    enum Error: Swift.Error, Equatable {
        case missingValue(String)
        case invalidURL(String, String)
    }

    private enum InfoKey {
        static let projectURL = "SupabaseProjectURL"
        static let anonKey = "SupabaseAnonKey"
        static let authRedirectURL = "SupabaseAuthRedirectURL"
        static let appleServiceID = "SupabaseAppleServiceID"
        static let callbackScheme = "SupabaseCallbackScheme"
    }

    let projectURL: URL
    let anonKey: String
    let authRedirectURL: URL
    let appleServiceID: String
    let urlScheme: String

    init(
        projectURL: URL,
        anonKey: String,
        authRedirectURL: URL,
        appleServiceID: String,
        urlScheme: String
    ) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.authRedirectURL = authRedirectURL
        self.appleServiceID = appleServiceID
        self.urlScheme = urlScheme
    }

    static func live(bundle: Bundle = .main) -> SupabaseProjectConfiguration {
        do {
            return try SupabaseProjectConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
        } catch {
            preconditionFailure("Missing Supabase auth configuration: \(error)")
        }
    }

    init(infoDictionary: [String: Any]) throws {
        let projectURLValue = try Self.requiredString(InfoKey.projectURL, in: infoDictionary)
        let authRedirectURLValue = try Self.requiredString(InfoKey.authRedirectURL, in: infoDictionary)

        guard let projectURL = URL(string: projectURLValue) else {
            throw Error.invalidURL(InfoKey.projectURL, projectURLValue)
        }
        guard let authRedirectURL = URL(string: authRedirectURLValue) else {
            throw Error.invalidURL(InfoKey.authRedirectURL, authRedirectURLValue)
        }

        self.projectURL = projectURL
        self.anonKey = try Self.requiredString(InfoKey.anonKey, in: infoDictionary)
        self.authRedirectURL = authRedirectURL
        self.appleServiceID = try Self.requiredString(InfoKey.appleServiceID, in: infoDictionary)
        self.urlScheme = try Self.requiredString(InfoKey.callbackScheme, in: infoDictionary)
    }

    var linkAnonymousSessionURL: URL {
        projectURL.appendingPathComponent("functions/v1/link-anonymous-session")
    }

    private static func requiredString(_ key: String, in infoDictionary: [String: Any]) throws -> String {
        guard let value = infoDictionary[key] as? String,
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Error.missingValue(key)
        }
        return value
    }
}

enum SupabaseAuthAPIError: Error, Equatable {
    case invalidCredentials(String)
    case networkUnavailable
    case invalidResponse
    case refreshRejected
    case appleCredentialInvalid
}

protocol SupabaseAuthAPI {
    func signUp(email: String, password: String) async throws -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    func exchangeAppleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession
    func refresh(refreshToken: String) async throws -> AuthSession
}

protocol AuthSessionStoring {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

protocol PendingAnonymousSessionStoring {
    func load() -> UUID?
    func save(_ sessionID: UUID)
    func clear()
}

protocol AnonymousSessionLinking {
    func linkPendingSession(with authSession: AuthSession) async -> Bool
}

@MainActor
protocol AuthServicing: ObservableObject {
    var state: AuthState { get }

    func observeStates() -> AsyncStream<AuthState>
    func restoreSession() async
    func handleAppDidBecomeActive() async
    func requireAuthentication(context: AuthRequirementContext, message: String) async
    func dismissFailure() async
    func ensureValidSession(for context: AuthRequirementContext) async -> AuthSession?
    func signIn(email: String, password: String, context: AuthRequirementContext) async
    func signUp(email: String, password: String, context: AuthRequirementContext) async
    func signInWithApple(identityToken: String, nonce: String, context: AuthRequirementContext) async
    func signOut() async
    func beginAnonymousSessionIfNeeded() -> UUID?
}

final class KeychainAuthSessionStore: AuthSessionStoring {
    private let service: String
    private let account: String

    init(service: String = "com.route25.girlpower.auth.session", account: String = "supabase-session") {
        self.service = service
        self.account = account
    }

    func load() throws -> AuthSession? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery(returnData: true) as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SupabaseAuthAPIError.invalidResponse
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query = baseQuery(returnData: false)
        var status = SecItemAdd(query.merging([kSecValueData as String: data]) { _, newValue in newValue } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw SupabaseAuthAPIError.invalidResponse
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery(returnData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SupabaseAuthAPIError.invalidResponse
        }
    }

    private func baseQuery(returnData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if returnData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

final class UserDefaultsPendingAnonymousSessionStore: PendingAnonymousSessionStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "auth.pendingAnonymousSessionID") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> UUID? {
        guard let rawValue = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: rawValue)
    }

    func save(_ sessionID: UUID) {
        defaults.set(sessionID.uuidString, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct AnonymousSessionLinkResult: Decodable {
    let status: String
}

final class SupabaseAnonymousSessionLinker: AnonymousSessionLinking {
    private let configuration: SupabaseProjectConfiguration
    private let urlSession: URLSession
    private let pendingStore: PendingAnonymousSessionStoring
    private let deviceIdentityStorage: KeychainPersisting

    init(
        configuration: SupabaseProjectConfiguration,
        urlSession: URLSession = .shared,
        pendingStore: PendingAnonymousSessionStoring,
        deviceIdentityStorage: KeychainPersisting = KeychainDeviceIdentityStorage()
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.pendingStore = pendingStore
        self.deviceIdentityStorage = deviceIdentityStorage
    }

    func linkPendingSession(with authSession: AuthSession) async -> Bool {
        guard let pendingSessionID = pendingStore.load(),
              let deviceID = try? deviceIdentityStorage.readUUID() else {
            return true
        }

        var request = URLRequest(url: configuration.linkAnonymousSessionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(LinkPayload(deviceID: deviceID.uuidString, anonSessionID: pendingSessionID.uuidString))

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            switch httpResponse.statusCode {
            case 200, 201, 204:
                pendingStore.clear()
                return true
            case 409, 412:
                pendingStore.clear()
                return true
            default:
                if !data.isEmpty,
                   let result = try? JSONDecoder().decode(AnonymousSessionLinkResult.self, from: data),
                   ["duplicate", "stale_session"].contains(result.status) {
                    pendingStore.clear()
                    return true
                }
                return false
            }
        } catch {
            return false
        }
    }

    private struct LinkPayload: Encodable {
        let deviceID: String
        let anonSessionID: String

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case anonSessionID = "anon_session_id"
        }
    }
}

final class SupabaseAuthRESTAPI: SupabaseAuthAPI {
    private let configuration: SupabaseProjectConfiguration
    private let urlSession: URLSession

    init(configuration: SupabaseProjectConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        try await requestSession(
            path: "auth/v1/signup",
            body: [
                "email": email,
                "password": password
            ]
        )
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await requestSession(
            path: "auth/v1/token?grant_type=password",
            body: [
                "email": email,
                "password": password
            ]
        )
    }

    func exchangeAppleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession {
        try await requestSession(
            path: "auth/v1/token?grant_type=id_token",
            body: [
                "provider": "apple",
                "id_token": identityToken,
                "nonce": nonce
            ]
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await requestSession(
            path: "auth/v1/token?grant_type=refresh_token",
            body: [
                "refresh_token": refreshToken
            ]
        )
    }

    private func requestSession(path: String, body: [String: String]) async throws -> AuthSession {
        guard let endpoint = makeEndpoint(path: path) else {
            throw SupabaseAuthAPIError.invalidResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SupabaseAuthAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                let payload = try JSONDecoder().decode(SupabaseAuthSessionResponse.self, from: data)
                return try payload.makeSession()
            case 400, 401, 422:
                let message = (try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data).message) ?? "Authentication failed."
                if path.contains("refresh_token") {
                    throw SupabaseAuthAPIError.refreshRejected
                }
                if path.contains("id_token") {
                    throw SupabaseAuthAPIError.appleCredentialInvalid
                }
                throw SupabaseAuthAPIError.invalidCredentials(message)
            default:
                throw SupabaseAuthAPIError.invalidResponse
            }
        } catch let error as SupabaseAuthAPIError {
            throw error
        } catch {
            throw SupabaseAuthAPIError.networkUnavailable
        }
    }

    private func makeEndpoint(path: String) -> URL? {
        var components = URLComponents(url: configuration.projectURL, resolvingAgainstBaseURL: false)
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = "/" + parts[0]
        if parts.count == 2 {
            components?.percentEncodedQuery = String(parts[1])
        }
        return components?.url
    }
}

@MainActor
final class SupabaseAuthService: ObservableObject, AuthServicing {
    @Published private(set) var state: AuthState

    private let stateMachine = AuthStateMachine()
    private let api: SupabaseAuthAPI
    private let sessionStore: AuthSessionStoring
    private let anonymousSessionStore: PendingAnonymousSessionStoring
    private let linker: AnonymousSessionLinking
    private var continuations: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    private var sessionRecoveryTask: Task<AuthSession?, Never>?
    private var sessionRecoveryContext: AuthRequirementContext?
    private let logger = Logger(subsystem: "com.route25.girlpower", category: "Auth")

    init(
        api: SupabaseAuthAPI,
        sessionStore: AuthSessionStoring = KeychainAuthSessionStore(),
        anonymousSessionStore: PendingAnonymousSessionStoring = UserDefaultsPendingAnonymousSessionStore(),
        linker: AnonymousSessionLinking
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.anonymousSessionStore = anonymousSessionStore
        self.linker = linker
        self.state = .anonymousEligible
    }

    func observeStates() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
            continuations[id] = continuation
            continuation.yield(state)
        }
    }

    func restoreSession() async {
        _ = await restoreOrJoinExistingRecovery()
    }

    func handleAppDidBecomeActive() async {
        switch state {
        case .authenticated(let session) where session.shouldRefreshSoon:
            _ = await refreshOrJoin(session: session, context: .restore)
        case .refreshing:
            _ = await sessionRecoveryTask?.value
        default:
            _ = await restoreOrJoinExistingRecovery()
        }
    }

    func requireAuthentication(context: AuthRequirementContext, message: String) async {
        apply(.requireAuthentication(context: context, message: message))
    }

    func dismissFailure() async {
        apply(.clearAuthentication)
    }

    func ensureValidSession(for context: AuthRequirementContext) async -> AuthSession? {
        switch state {
        case .authenticated(let session):
            if session.shouldRefreshSoon {
                return await refreshOrJoin(session: session, context: context)
            }
            return session
        case .refreshing(let session, let refreshingContext):
            if let task = sessionRecoveryTask {
                if refreshingContext != context {
                    sessionRecoveryContext = context
                    apply(.beginRefresh(session, context: context))
                }
                return await task.value
            }
            apply(.requireAuthentication(context: context, message: context.defaultMessage))
            return nil
        case .authRequired, .authFailed, .anonymousEligible, .authenticating:
            apply(.requireAuthentication(context: context, message: context.defaultMessage))
            return nil
        }
    }

    func signIn(email: String, password: String, context: AuthRequirementContext) async {
        apply(.beginAuthentication(method: .emailSignIn, context: context))
        await performAuthentication(context: context) {
            try await self.api.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String, context: AuthRequirementContext) async {
        apply(.beginAuthentication(method: .emailSignUp, context: context))
        await performAuthentication(context: context) {
            try await self.api.signUp(email: email, password: password)
        }
    }

    func signInWithApple(identityToken: String, nonce: String, context: AuthRequirementContext) async {
        apply(.beginAuthentication(method: .apple, context: context))
        await performAuthentication(context: context) {
            try await self.api.exchangeAppleIdentityToken(identityToken, nonce: nonce)
        }
    }

    func signOut() async {
        try? sessionStore.clear()
        anonymousSessionStore.clear()
        apply(.signOut)
    }

    func beginAnonymousSessionIfNeeded() -> UUID? {
        guard state.session == nil else {
            return nil
        }
        if let existing = anonymousSessionStore.load() {
            return existing
        }
        let pending = UUID()
        anonymousSessionStore.save(pending)
        return pending
    }

    private func performAuthentication(
        context: AuthRequirementContext,
        action: @escaping () async throws -> AuthSession
    ) async {
        do {
            let session = try await action()
            try sessionStore.save(session)
            apply(.authenticationSucceeded(session))
            let linked = await linker.linkPendingSession(with: session)
            if linked == false {
                logger.warning("Anonymous session link will retry on the next authenticated launch")
            }
        } catch let error as SupabaseAuthAPIError {
            if error == .refreshRejected {
                try? sessionStore.clear()
            }
            apply(.authenticationFailed(context: context, message: message(for: error, context: context), reason: reason(for: error)))
        } catch {
            apply(.authenticationFailed(context: context, message: context.defaultMessage, reason: .unexpectedResponse))
        }
    }

    private func refresh(session: AuthSession, context: AuthRequirementContext?) async -> AuthSession? {
        apply(.beginRefresh(session, context: context))
        do {
            let refreshed = try await api.refresh(refreshToken: session.refreshToken)
            try sessionStore.save(refreshed)
            apply(.authenticationSucceeded(refreshed))
            let linked = await linker.linkPendingSession(with: refreshed)
            if linked == false {
                logger.warning("Anonymous session link still pending after refresh")
            }
            return refreshed
        } catch let error as SupabaseAuthAPIError {
            switch error {
            case .refreshRejected:
                try? sessionStore.clear()
                let resolvedContext = sessionRecoveryContext ?? context ?? .restore
                apply(.authenticationFailed(context: resolvedContext, message: "Your session expired or Supabase could not refresh it. Sign in again to continue.", reason: .refreshRejected))
                return nil
            case .networkUnavailable, .invalidResponse:
                logger.warning("Keeping cached session after transient refresh failure: \(String(describing: error), privacy: .public)")
                apply(.authenticationSucceeded(session))
                return session
            case .invalidCredentials, .appleCredentialInvalid:
                logger.warning("Unexpected refresh error kept cached session active: \(String(describing: error), privacy: .public)")
                apply(.authenticationSucceeded(session))
                return session
            }
        } catch {
            logger.warning("Keeping cached session after unexpected refresh failure")
            apply(.authenticationSucceeded(session))
            return session
        }
    }

    private func restoreOrJoinExistingRecovery() async -> AuthSession? {
        if let task = sessionRecoveryTask {
            return await task.value
        }
        return await startSessionRecovery(context: .restore) {
            do {
                guard let session = try self.sessionStore.load() else {
                    self.apply(.clearAuthentication)
                    return nil
                }
                if session.shouldRefreshSoon {
                    return await self.refresh(session: session, context: .restore)
                }
                self.apply(.restoreSession(session))
                _ = await self.linker.linkPendingSession(with: session)
                return session
            } catch {
                self.apply(.authenticationFailed(context: .restore, message: "Stored session could not be restored.", reason: .unexpectedResponse))
                return nil
            }
        }
    }

    private func refreshOrJoin(session: AuthSession, context: AuthRequirementContext?) async -> AuthSession? {
        if let task = sessionRecoveryTask {
            return await task.value
        }
        return await startSessionRecovery(context: context) {
            await self.refresh(session: session, context: context)
        }
    }

    private func startSessionRecovery(
        context: AuthRequirementContext?,
        operation: @escaping @MainActor () async -> AuthSession?
    ) async -> AuthSession? {
        let task = Task<AuthSession?, Never> { @MainActor in
            self.sessionRecoveryContext = context
            defer {
                self.sessionRecoveryTask = nil
                self.sessionRecoveryContext = nil
            }
            return await operation()
        }
        sessionRecoveryTask = task
        return await task.value
    }

    private func apply(_ event: AuthStateMachine.Event) {
        let nextState = stateMachine.transition(from: state, event: event)
        guard nextState != state else { return }
        state = nextState
        continuations.values.forEach { $0.yield(nextState) }
    }

    private func reason(for error: SupabaseAuthAPIError) -> AuthFailureReason {
        switch error {
        case .invalidCredentials:
            return .invalidCredentials
        case .networkUnavailable:
            return .networkUnavailable
        case .refreshRejected:
            return .refreshRejected
        case .appleCredentialInvalid:
            return .appleCredentialInvalid
        case .invalidResponse:
            return .unexpectedResponse
        }
    }

    private func message(for error: SupabaseAuthAPIError, context: AuthRequirementContext) -> String {
        switch error {
        case .invalidCredentials(let message):
            return message
        case .networkUnavailable:
            return "Supabase is unreachable right now. Retry or sign in again when the network is available."
        case .refreshRejected:
            return "Your session expired and could not be refreshed. Sign in again to continue."
        case .appleCredentialInvalid:
            return "Apple Sign In did not return a valid credential for Supabase."
        case .invalidResponse:
            return context.defaultMessage
        }
    }
}

@MainActor
final class DisabledAuthService: ObservableObject, AuthServicing {
    @Published private(set) var state: AuthState = .anonymousEligible

    func observeStates() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            continuation.yield(.anonymousEligible)
            continuation.finish()
        }
    }

    func restoreSession() async {}
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

enum AppleSignInNonce {
    static func makeRawNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct SupabaseAuthSessionResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: TimeInterval?
    let expiresIn: TimeInterval?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case user
    }

    func makeSession() throws -> AuthSession {
        guard let accessToken,
              let refreshToken,
              let user else {
            throw SupabaseAuthAPIError.invalidResponse
        }
        let expiry = expiresAt.map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(expiresIn ?? 3600)
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            user: AuthUser(id: user.id, email: user.email)
        )
    }
}

private struct SupabaseAuthUser: Decodable {
    let id: String
    let email: String?
}

private struct SupabaseErrorResponse: Decodable {
    let message: String
}
