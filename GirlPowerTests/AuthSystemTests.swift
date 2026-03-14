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

    private func makeService(initialSession: AuthSession? = nil) -> (SupabaseAuthService, InMemoryAuthSessionStore) {
        let configuration = SupabaseProjectConfiguration(
            projectURL: URL(string: "https://example.test")!,
            anonKey: "anon-key",
            authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
            appleServiceID: "com.route25.girlpower.auth",
            urlScheme: "girlpower"
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
