import XCTest
@testable import GirlPower

@MainActor
final class AuthSystemTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.requestHandler = nil
    }

    func testSignUpPromotesImmediateSupabaseSessionToAuthenticatedState() async {
        let (service, store) = makeService()
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/signup")
            return (200, Self.sessionPayload(accessToken: "signup-token", refreshToken: "signup-refresh"))
        }

        await service.signUp(email: "fresh@example.com", password: "Password-123!", context: .secondDemo)

        guard case .authenticated(let session) = service.state else {
            return XCTFail("Expected authenticated state")
        }
        XCTAssertEqual(session.accessToken, "signup-token")
        XCTAssertEqual(store.savedSession?.accessToken, "signup-token")
    }

    func testRestoreSessionRefreshesExpiredToken() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let (service, store) = makeService(initialSession: expired)
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
            return (200, Self.sessionPayload(accessToken: "refreshed-token", refreshToken: "refreshed-refresh"))
        }

        await service.restoreSession()

        guard case .authenticated(let session) = service.state else {
            return XCTFail("Expected refreshed authenticated state")
        }
        XCTAssertEqual(session.accessToken, "refreshed-token")
        XCTAssertEqual(store.savedSession?.refreshToken, "refreshed-refresh")
    }

    func testAnonymousLinkRetriesOnServerFailureAndClearsOnDuplicate() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let pendingID = UUID()
        pendingStore.save(pendingID)
        let deviceID = UUID()
        let session = makeURLSession()
        let linker = SupabaseAnonymousSessionLinker(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.girlpower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: session,
            pendingStore: pendingStore,
            deviceIdentityStorage: FakeKeychainPersisting(uuid: deviceID)
        )

        URLProtocolStub.requestHandler = { _ in
            (500, Data("{\"status\":\"retry_later\"}".utf8))
        }
        let firstAttempt = await linker.linkPendingSession(with: .fixture)
        XCTAssertFalse(firstAttempt)
        XCTAssertEqual(pendingStore.load(), pendingID)

        URLProtocolStub.requestHandler = { _ in
            (409, Data("{\"status\":\"duplicate\"}".utf8))
        }
        let secondAttempt = await linker.linkPendingSession(with: .fixture)
        XCTAssertTrue(secondAttempt)
        XCTAssertNil(pendingStore.load())
    }

    func testAnonymousLinkClearsPendingSessionWhenServerRejectsStaleSession() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let pendingID = UUID()
        pendingStore.save(pendingID)
        let session = makeURLSession()
        let linker = SupabaseAnonymousSessionLinker(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.girlpower.stage.auth",
                urlScheme: "girlpower-stage"
            ),
            urlSession: session,
            pendingStore: pendingStore,
            deviceIdentityStorage: FakeKeychainPersisting(uuid: UUID())
        )

        URLProtocolStub.requestHandler = { _ in
            (412, Data("{\"status\":\"stale_session\"}".utf8))
        }

        let linked = await linker.linkPendingSession(with: .fixture)

        XCTAssertTrue(linked)
        XCTAssertNil(pendingStore.load())
    }

    func testConfigurationLoadsFromInfoDictionary() throws {
        let configuration = try SupabaseProjectConfiguration(
            infoDictionary: [
                "SupabaseProjectURL": "https://example.test",
                "SupabaseAnonKey": "anon-key",
                "SupabaseAuthRedirectURL": "girlpower-stage://auth/callback",
                "SupabaseAppleServiceID": "com.route25.girlpower.stage.auth",
                "SupabaseCallbackScheme": "girlpower-stage",
            ]
        )

        XCTAssertEqual(configuration.projectURL.absoluteString, "https://example.test")
        XCTAssertEqual(configuration.anonKey, "anon-key")
        XCTAssertEqual(configuration.authRedirectURL.absoluteString, "girlpower-stage://auth/callback")
        XCTAssertEqual(configuration.appleServiceID, "com.route25.girlpower.stage.auth")
        XCTAssertEqual(configuration.urlScheme, "girlpower-stage")
    }

    func testRestoreSessionAndForegroundRefreshShareSingleInFlightTask() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let refreshed = AuthSession(
            accessToken: "refreshed-token",
            refreshToken: "refreshed-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let api = RefreshBlockingAuthAPI(refreshedSession: refreshed)
        let store = InMemoryAuthSessionStore(initial: expired)
        let service = SupabaseAuthService(
            api: api,
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub()
        )

        let restoreTask = Task { await service.restoreSession() }
        await waitForCondition {
            await api.refreshCallCount() == 1 && service.state.session?.accessToken == "expired-token"
        }

        let foregroundTask = Task { await service.handleAppDidBecomeActive() }
        await Task.yield()
        let refreshCallsBeforeResume = await api.refreshCallCount()
        XCTAssertEqual(refreshCallsBeforeResume, 1)

        await api.resumeRefresh()
        await restoreTask.value
        await foregroundTask.value

        let refreshCallsAfterResume = await api.refreshCallCount()
        XCTAssertEqual(refreshCallsAfterResume, 1)
        guard case .authenticated(let session) = service.state else {
            return XCTFail("Expected authenticated state after shared refresh")
        }
        XCTAssertEqual(session.accessToken, "refreshed-token")
        XCTAssertEqual(store.savedSession?.refreshToken, "refreshed-refresh")
    }

    func testEnsureValidSessionWaitsForInFlightRefresh() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let refreshed = AuthSession(
            accessToken: "refreshed-token",
            refreshToken: "refreshed-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let api = RefreshBlockingAuthAPI(refreshedSession: refreshed)
        let service = SupabaseAuthService(
            api: api,
            sessionStore: InMemoryAuthSessionStore(initial: expired),
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub()
        )

        let restoreTask = Task { await service.restoreSession() }
        await waitForCondition {
            await api.refreshCallCount() == 1 && service.state.session?.accessToken == "expired-token"
        }

        let ensuredTask = Task { await service.ensureValidSession(for: .paywall) }
        await Task.yield()
        if case .authRequired = service.state {
            XCTFail("Expected refresh to stay in flight instead of forcing auth")
        }

        await api.resumeRefresh()
        let ensuredSession = await ensuredTask.value
        await restoreTask.value

        XCTAssertEqual(ensuredSession?.accessToken, "refreshed-token")
    }

    func testEnsureValidSessionFailsClosedWhenInFlightRefreshRejects() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let api = RefreshRejectingAuthAPI()
        let store = InMemoryAuthSessionStore(initial: expired)
        let service = SupabaseAuthService(
            api: api,
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub()
        )

        let restoreTask = Task { await service.restoreSession() }
        await waitForCondition {
            await api.refreshCallCount() == 1 && service.state.session?.accessToken == "expired-token"
        }

        let ensuredTask = Task { await service.ensureValidSession(for: .paywall) }
        await api.resumeRefresh()
        let ensuredSession = await ensuredTask.value
        await restoreTask.value

        XCTAssertNil(ensuredSession)
        XCTAssertNil(store.savedSession)
        guard case .authFailed(let context, _, let reason) = service.state else {
            return XCTFail("Expected auth failure after refresh rejection")
        }
        XCTAssertEqual(context, .paywall)
        XCTAssertEqual(reason, .refreshRejected)
    }

    func testBeginAnonymousSessionDoesNotCreatePendingIDWhileRefreshingCachedSession() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let api = RefreshBlockingAuthAPI(refreshedSession: .fixture)
        let service = SupabaseAuthService(
            api: api,
            sessionStore: InMemoryAuthSessionStore(initial: expired),
            anonymousSessionStore: pendingStore,
            linker: AnonymousSessionLinkerStub()
        )

        let restoreTask = Task { await service.restoreSession() }
        await waitForCondition {
            await api.refreshCallCount() == 1 && service.state.session?.accessToken == "expired-token"
        }
        let pendingID = service.beginAnonymousSessionIfNeeded()
        await api.resumeRefresh()
        await restoreTask.value

        XCTAssertNil(pendingID)
        XCTAssertNil(pendingStore.load())
    }

    private func makeService(initialSession: AuthSession? = nil) -> (SupabaseAuthService, InMemoryAuthSessionStore) {
        let configuration = SupabaseProjectConfiguration(
            projectURL: URL(string: "https://example.test")!,
            anonKey: "anon-key",
            authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
            appleServiceID: "com.route25.girlpower.stage.auth",
            urlScheme: "girlpower-stage"
        )
        let sessionStore = InMemoryAuthSessionStore(initial: initialSession)
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let service = SupabaseAuthService(
            api: SupabaseAuthRESTAPI(configuration: configuration, urlSession: makeURLSession()),
            sessionStore: sessionStore,
            anonymousSessionStore: pendingStore,
            linker: AnonymousSessionLinkerStub()
        )
        return (service, sessionStore)
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func sessionPayload(accessToken: String, refreshToken: String) -> Data {
        Data(
            """
            {
              "access_token": "\(accessToken)",
              "refresh_token": "\(refreshToken)",
              "expires_in": 3600,
              "token_type": "bearer",
              "user": {
                "id": "user-1",
                "email": "member@example.com"
              }
            }
            """.utf8
        )
    }
}

private final class InMemoryAuthSessionStore: AuthSessionStoring {
    private(set) var savedSession: AuthSession?

    init(initial: AuthSession? = nil) {
        self.savedSession = initial
    }

    func load() throws -> AuthSession? { savedSession }
    func save(_ session: AuthSession) throws { savedSession = session }
    func clear() throws { savedSession = nil }
}

private final class InMemoryPendingAnonymousSessionStore: PendingAnonymousSessionStoring {
    private var value: UUID?

    func load() -> UUID? { value }
    func save(_ sessionID: UUID) { value = sessionID }
    func clear() { value = nil }
}

private final class AnonymousSessionLinkerStub: AnonymousSessionLinking {
    func linkPendingSession(with authSession: AuthSession) async -> Bool { true }
}

private actor RefreshBlockingAuthAPI: SupabaseAuthAPI {
    private let refreshedSession: AuthSession
    private var continuation: CheckedContinuation<AuthSession, Never>?
    private var refreshCalls = 0

    init(refreshedSession: AuthSession) {
        self.refreshedSession = refreshedSession
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func exchangeAppleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        refreshCalls += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func refreshCallCount() -> Int {
        refreshCalls
    }

    func resumeRefresh() {
        continuation?.resume(returning: refreshedSession)
        continuation = nil
    }
}

private actor RefreshRejectingAuthAPI: SupabaseAuthAPI {
    private var continuation: CheckedContinuation<AuthSession, Error>?
    private var refreshCalls = 0

    func signUp(email: String, password: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func exchangeAppleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession {
        throw SupabaseAuthAPIError.invalidResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        refreshCalls += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func refreshCallCount() -> Int {
        refreshCalls
    }

    func resumeRefresh() {
        continuation?.resume(throwing: SupabaseAuthAPIError.refreshRejected)
        continuation = nil
    }
}

private final class FakeKeychainPersisting: KeychainPersisting {
    let uuid: UUID

    init(uuid: UUID) {
        self.uuid = uuid
    }

    func readUUID() throws -> UUID? { uuid }
    func store(uuid: UUID) throws {}
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension AuthSession {
    static var fixture: AuthSession {
        AuthSession(
            accessToken: "live-token",
            refreshToken: "live-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
    }
}

private extension AuthSystemTests {
    func waitForCondition(
        timeout: TimeInterval = 1.0,
        condition: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }
}
