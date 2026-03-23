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

    func testSignInTriggersCentralizedProfileUpsert() async {
        let profileService = ProfileServiceSpy()
        let service = SupabaseAuthService(
            api: SuccessfulSignInAuthAPI(session: .fixture),
            sessionStore: InMemoryAuthSessionStore(),
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        await service.signIn(email: "member@example.com", password: "Password-123!", context: .paywall)
        await waitForCondition {
            await profileService.upsertedUserIDs() == ["user-1"]
        }

        guard case .authenticated = service.state else {
            return XCTFail("Expected authenticated state")
        }
    }

    func testRestoreSessionRefreshTriggersProfileUpsert() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let profileService = ProfileServiceSpy()
        let service = SupabaseAuthService(
            api: SuccessfulRefreshAuthAPI(refreshedSession: .fixture),
            sessionStore: InMemoryAuthSessionStore(initial: expired),
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        await service.restoreSession()
        await waitForCondition {
            await profileService.upsertedUserIDs() == ["user-1"]
        }

        guard case .authenticated = service.state else {
            return XCTFail("Expected authenticated state")
        }
    }

    func testSignInTriggersAuthenticatedDeviceLinkAndExposesMergedQuotaContext() async {
        let linker = AuthenticatedDeviceLinkerSpy(
            result: CurrentDeviceLinkResult(
                status: "linked",
                mergedDemoQuotaSnapshot: DemoQuotaStateMachine.RemoteSnapshot(
                    attemptsUsed: 2,
                    activeAttemptIndex: nil,
                    lastDecision: nil,
                    serverLockReason: .quotaExhausted
                )
            )
        )
        let service = SupabaseAuthService(
            api: SuccessfulSignInAuthAPI(session: .fixture),
            sessionStore: InMemoryAuthSessionStore(),
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: linker,
            profileService: ProfileServiceSpy()
        )

        await service.signIn(email: "member@example.com", password: "Password-123!", context: .paywall)
        await waitForCondition {
            await linker.linkedUserIDs() == ["user-1"]
        }

        let synchronized = await service.synchronizeAuthenticatedContext(for: .fixture)

        XCTAssertEqual(synchronized?.mergedDemoQuotaSnapshot?.attemptsUsed, 2)
        XCTAssertEqual(synchronized?.mergedDemoQuotaSnapshot?.serverLockReason, .quotaExhausted)
    }

    func testSignInPublishesAuthenticatedStateBeforeBackgroundProfileSyncCompletes() async {
        let profileService = BlockingProfileServiceSpy()
        let store = InMemoryAuthSessionStore()
        let service = SupabaseAuthService(
            api: SuccessfulSignInAuthAPI(session: .fixture),
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        let signInTask = Task {
            await service.signIn(email: "member@example.com", password: "Password-123!", context: .paywall)
        }
        await waitForCondition {
            await profileService.upsertStarted()
        }

        guard case .authenticated(let session) = service.state else {
            signInTask.cancel()
            return XCTFail("Expected authenticated state before profile sync completed")
        }
        XCTAssertEqual(session.accessToken, AuthSession.fixture.accessToken)
        XCTAssertEqual(store.savedSession?.accessToken, AuthSession.fixture.accessToken)
        let signInCompletedUpserts = await profileService.completedUpsertCount()
        XCTAssertEqual(signInCompletedUpserts, 0)

        await profileService.resumeUpsert()
        await signInTask.value
        await waitForCondition {
            await profileService.completedUpsertCount() == 1
        }
    }

    func testRestoreSessionPublishesAuthenticatedStateBeforeBackgroundProfileSyncCompletes() async {
        let profileService = BlockingProfileServiceSpy()
        let store = InMemoryAuthSessionStore(initial: .fixture)
        let service = SupabaseAuthService(
            api: SuccessfulSignInAuthAPI(session: .fixture),
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        let restoreTask = Task {
            await service.restoreSession()
        }
        await waitForCondition {
            await profileService.upsertStarted()
        }

        guard case .authenticated(let session) = service.state else {
            restoreTask.cancel()
            return XCTFail("Expected restored authenticated state before profile sync completed")
        }
        XCTAssertEqual(session.accessToken, AuthSession.fixture.accessToken)
        XCTAssertEqual(store.savedSession?.accessToken, AuthSession.fixture.accessToken)
        let restoreCompletedUpserts = await profileService.completedUpsertCount()
        XCTAssertEqual(restoreCompletedUpserts, 0)

        await profileService.resumeUpsert()
        await restoreTask.value
        await waitForCondition {
            await profileService.completedUpsertCount() == 1
        }
    }

    func testRefreshPublishesAuthenticatedStateBeforeBackgroundProfileSyncCompletes() async {
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
        let profileService = BlockingProfileServiceSpy()
        let store = InMemoryAuthSessionStore(initial: expired)
        let service = SupabaseAuthService(
            api: SuccessfulRefreshAuthAPI(refreshedSession: refreshed),
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        let restoreTask = Task {
            await service.restoreSession()
        }
        await waitForCondition {
            await profileService.upsertStarted()
        }

        guard case .authenticated(let session) = service.state else {
            restoreTask.cancel()
            return XCTFail("Expected refreshed authenticated state before profile sync completed")
        }
        XCTAssertEqual(session.accessToken, refreshed.accessToken)
        XCTAssertEqual(store.savedSession?.accessToken, refreshed.accessToken)
        let refreshCompletedUpserts = await profileService.completedUpsertCount()
        XCTAssertEqual(refreshCompletedUpserts, 0)

        await profileService.resumeUpsert()
        await restoreTask.value
        await waitForCondition {
            await profileService.completedUpsertCount() == 1
        }
    }

    func testProfileSyncFailureDoesNotBlockAuthenticatedState() async {
        let profileService = FailingProfileServiceSpy()
        let store = InMemoryAuthSessionStore()
        let service = SupabaseAuthService(
            api: SuccessfulSignInAuthAPI(session: .fixture),
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub(),
            profileService: profileService
        )

        await service.signIn(email: "member@example.com", password: "Password-123!", context: .paywall)
        await waitForCondition {
            await profileService.upsertAttempts() == 1
        }

        guard case .authenticated(let session) = service.state else {
            return XCTFail("Expected authenticated state despite profile sync failure")
        }
        XCTAssertEqual(session.accessToken, AuthSession.fixture.accessToken)
        XCTAssertEqual(store.savedSession?.accessToken, AuthSession.fixture.accessToken)
    }

    func testProfileDecodingRejectsUnsupportedProPlatform() throws {
        let payload = Data(
            """
            {
              "id": "user-1",
              "email": "member@example.com",
              "created_at": "2026-03-22T10:00:00Z",
              "updated_at": "2026-03-22T10:05:00Z",
              "is_pro": false,
              "pro_platform": "stripe",
              "onboarding_completed": false,
              "last_login_at": "2026-03-22T10:05:00Z"
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder.profileDecoder.decode(Profile.self, from: payload))
    }

    func testProfileInsertSendsLatestEmailAndLastLoginAtWhenProfileMissing() async throws {
        let service = SupabaseProfileService(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: makeURLSession()
        )
        var capturedBody: [[String: Any]] = []
        var requestMethods: [String] = []
        URLProtocolStub.requestHandler = { request in
            requestMethods.append(request.httpMethod ?? "")
            XCTAssertEqual(request.url?.path, "/rest/v1/profiles")
            if request.httpMethod == "GET" {
                return (200, Data("[]".utf8))
            }
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            return (201, Self.profilePayload())
        }

        _ = try await service.upsertProfile(using: .fixture)

        let payload = try XCTUnwrap(capturedBody.first)
        XCTAssertEqual(requestMethods, ["GET", "POST"])
        XCTAssertEqual(Set(payload.keys), ["id", "email", "last_login_at"])
        XCTAssertEqual(payload["id"] as? String, "user-1")
        XCTAssertEqual(payload["email"] as? String, "member@example.com")
        XCTAssertNotNil(payload["last_login_at"] as? String)
    }

    func testProfileUpsertPatchesSafeFieldsWhenProfileExists() async throws {
        let service = SupabaseProfileService(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: makeURLSession()
        )
        var capturedBody: [String: Any] = [:]
        var requestMethods: [String] = []
        URLProtocolStub.requestHandler = { request in
            requestMethods.append(request.httpMethod ?? "")
            XCTAssertEqual(request.url?.path, "/rest/v1/profiles")
            if request.httpMethod == "GET" {
                return (200, Self.profilePayload())
            }
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (200, Self.profilePayload())
        }

        _ = try await service.upsertProfile(using: .fixture)

        XCTAssertEqual(requestMethods, ["GET", "PATCH"])
        XCTAssertEqual(Set(capturedBody.keys), ["email", "last_login_at"])
        XCTAssertEqual(capturedBody["email"] as? String, "member@example.com")
        XCTAssertNotNil(capturedBody["last_login_at"] as? String)
    }

    func testProfileOnboardingPatchSendsOnlySafeField() async throws {
        let service = SupabaseProfileService(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: makeURLSession()
        )
        var capturedBody: [String: Any] = [:]
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/rest/v1/profiles")
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (200, Self.profilePayload(onboardingCompleted: true))
        }

        _ = try await service.updateOnboardingCompleted(true, using: .fixture)

        XCTAssertEqual(Set(capturedBody.keys), ["onboarding_completed"])
        XCTAssertEqual(capturedBody["onboarding_completed"] as? Bool, true)
    }

    func testProfileEntitlementSyncPostsSignedTransactionOnly() async throws {
        let service = SupabaseProfileEntitlementSyncService(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: makeURLSession()
        )
        var capturedBody: [String: Any] = [:]
        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/functions/v1/sync-profile-entitlement")
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (
                200,
                Data(
                    """
                    {
                      "profile": {
                        "id": "user-1",
                        "email": "member@example.com",
                        "created_at": "2026-03-22T10:00:00Z",
                        "updated_at": "2026-03-22T10:05:00Z",
                        "is_pro": true,
                        "pro_platform": "apple",
                        "onboarding_completed": false,
                        "last_login_at": "2026-03-22T10:05:00Z"
                      }
                    }
                    """.utf8
                )
            )
        }

        let profile = try await service.markPro(signedTransactionInfo: "signed-transaction-jws", using: .fixture)

        XCTAssertEqual(Set(capturedBody.keys), ["transaction_jws"])
        XCTAssertEqual(capturedBody["transaction_jws"] as? String, "signed-transaction-jws")
        XCTAssertEqual(profile.proPlatform, .apple)
        XCTAssertTrue(profile.isPro)
    }

    func testAuthenticatedDeviceLinkRetriesOnServerFailureAndClearsPendingSessionAfterSuccess() async {
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
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: session,
            pendingStore: pendingStore,
            deviceIdentityProvider: FakeDeviceIdentityProvider(uuid: deviceID)
        )

        URLProtocolStub.requestHandler = { _ in
            (500, Data("{\"status\":\"retry_later\"}".utf8))
        }
        let firstAttempt = await linker.linkCurrentDevice(with: .fixture)
        XCTAssertNil(firstAttempt)
        XCTAssertEqual(pendingStore.load(), pendingID)

        URLProtocolStub.requestHandler = { _ in
            (
                200,
                Data(
                    """
                    {
                      "status": "already_linked",
                      "snapshot": {
                        "attempts_used": 1,
                        "active_attempt_index": null,
                        "last_decision": {
                          "type": "allow",
                          "ts": "2026-03-23T10:00:00Z"
                        },
                        "server_lock_reason": null,
                        "last_sync_at": "2026-03-23T10:00:00Z"
                      }
                    }
                    """.utf8
                )
            )
        }
        let secondAttempt = await linker.linkCurrentDevice(with: .fixture)
        XCTAssertEqual(secondAttempt?.status, "already_linked")
        XCTAssertEqual(secondAttempt?.mergedDemoQuotaSnapshot?.attemptsUsed, 1)
        XCTAssertNil(pendingStore.load())
    }

    func testAuthenticatedDeviceLinkIncludesDeviceIdentityWithoutPendingAnonymousSession() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let session = makeURLSession()
        let deviceID = UUID()
        var capturedBody: [String: Any] = [:]
        let linker = SupabaseAnonymousSessionLinker(
            configuration: SupabaseProjectConfiguration(
                projectURL: URL(string: "https://example.test")!,
                anonKey: "anon-key",
                authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
                appleServiceID: "com.route25.GirlPower.auth",
                urlScheme: "girlpower"
            ),
            urlSession: session,
            pendingStore: pendingStore,
            deviceIdentityProvider: FakeDeviceIdentityProvider(uuid: deviceID)
        )

        URLProtocolStub.requestHandler = { request in
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (
                200,
                Data(
                    """
                    {
                      "status": "linked",
                      "snapshot": {
                        "attempts_used": 2,
                        "active_attempt_index": null,
                        "last_decision": null,
                        "server_lock_reason": "quota",
                        "last_sync_at": "2026-03-23T11:00:00Z"
                      }
                    }
                    """.utf8
                )
            )
        }

        let linked = await linker.linkCurrentDevice(with: .fixture)

        XCTAssertEqual(capturedBody["device_id"] as? String, deviceID.uuidString)
        XCTAssertNil(capturedBody["anon_session_id"])
        XCTAssertEqual(linked?.mergedDemoQuotaSnapshot?.attemptsUsed, 2)
        XCTAssertEqual(linked?.mergedDemoQuotaSnapshot?.serverLockReason, .quotaExhausted)
    }

    func testConfigurationLoadsFromInfoDictionary() throws {
        let configuration = try SupabaseProjectConfiguration(
            infoDictionary: [
                "SupabaseProjectURL": "https://example.test",
                "SupabaseAnonKey": "anon-key",
                "SupabaseAuthRedirectURL": "girlpower://auth/callback",
                "SupabaseAppleServiceID": "com.route25.GirlPower.auth",
                "SupabaseCallbackScheme": "girlpower",
            ]
        )

        XCTAssertEqual(configuration.projectURL.absoluteString, "https://example.test")
        XCTAssertEqual(configuration.anonKey, "anon-key")
        XCTAssertEqual(configuration.authRedirectURL.absoluteString, "girlpower://auth/callback")
        XCTAssertEqual(configuration.appleServiceID, "com.route25.GirlPower.auth")
        XCTAssertEqual(configuration.urlScheme, "girlpower")
    }

    func testEvaluateSessionServiceSendsCanonicalPayloadWithAnonymousMetadata() async throws {
        let session = makeURLSession()
        let service = EvaluateSessionService(
            endpoint: URL(string: "https://example.test/functions/v1/evaluate-session")!,
            anonKey: "anon-key",
            urlSession: session
        )
        var capturedBody: [String: Any] = [:]
        URLProtocolStub.requestHandler = { request in
            let data = try XCTUnwrap(request.bodyData())
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (200, Data("{\"decision\":{\"outcome\":\"allow\"}}".utf8))
        }

        _ = try await service.evaluate(
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptIndex: 1,
            context: [
                "anon_session_id": "22222222-2222-2222-2222-222222222222",
                "goal": "tempo"
            ]
        )

        XCTAssertEqual(capturedBody["device_id"] as? String, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(capturedBody["attempt_index"] as? Int, 1)
        XCTAssertEqual(capturedBody["payload_version"] as? String, "v1")
        let input = try XCTUnwrap(capturedBody["input"] as? [String: Any])
        XCTAssertEqual(input["prompt"] as? String, "Evaluate whether this device should unlock another free coaching demo.")
        XCTAssertEqual((input["context"] as? [String: String])?["anon_session_id"], "22222222-2222-2222-2222-222222222222")
        let metadata = try XCTUnwrap(capturedBody["metadata"] as? [String: String])
        XCTAssertEqual(metadata["anon_session_id"], "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(metadata["goal"], "tempo")
    }

    func testEvaluateSessionServiceMapsCanonicalDenyDecisionFromRateLimitResponse() async throws {
        let session = makeURLSession()
        let service = EvaluateSessionService(
            endpoint: URL(string: "https://example.test/functions/v1/evaluate-session")!,
            anonKey: "anon-key",
            urlSession: session
        )
        URLProtocolStub.requestHandler = { _ in
            (
                429,
                Data(
                    """
                    {
                      "decision": {
                        "outcome": "deny",
                        "message": "Free demo eligibility is temporarily rate limited. Try again shortly."
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await service.evaluate(
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptIndex: 1,
            context: [:]
        )

        XCTAssertFalse(result.allowAnotherDemo)
        XCTAssertEqual(result.message, "Free demo eligibility is temporarily rate limited. Try again shortly.")
    }

    func testEvaluateSessionServiceMapsCanonicalDecisionFromDuplicateReplayResponse() async throws {
        let session = makeURLSession()
        let service = EvaluateSessionService(
            endpoint: URL(string: "https://example.test/functions/v1/evaluate-session")!,
            anonKey: "anon-key",
            urlSession: session
        )
        URLProtocolStub.requestHandler = { _ in
            (
                409,
                Data(
                    """
                    {
                      "reason": "duplicate_attempt",
                      "decision": {
                        "outcome": "deny",
                        "message": "This device has already used its free demos.",
                        "lock_reason": "quota"
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await service.evaluate(
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptIndex: 1,
            context: [:]
        )

        XCTAssertFalse(result.allowAnotherDemo)
        XCTAssertEqual(result.message, "This device has already used its free demos.")
        XCTAssertEqual(result.lockReason, "quota")
    }

    func testEvaluateSessionServiceMapsTimeoutReplayResponseToCanonicalTimeoutResult() async throws {
        let session = makeURLSession()
        let service = EvaluateSessionService(
            endpoint: URL(string: "https://example.test/functions/v1/evaluate-session")!,
            anonKey: "anon-key",
            urlSession: session
        )
        URLProtocolStub.requestHandler = { _ in
            (
                409,
                Data(
                    """
                    {
                      "reason": "duplicate_attempt",
                      "decision": {
                        "outcome": "timeout"
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await service.evaluate(
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            attemptIndex: 2,
            context: [:]
        )

        XCTAssertFalse(result.allowAnotherDemo)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.lockReason, "evaluation_timeout")
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

    func testTransientRefreshFailureKeepsCachedSessionAndAvoidsAuthFailure() async {
        let expired = AuthSession(
            accessToken: "expired-token",
            refreshToken: "expired-refresh",
            expiresAt: Date().addingTimeInterval(-60),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
        let store = InMemoryAuthSessionStore(initial: expired)
        let service = SupabaseAuthService(
            api: RefreshNetworkFailingAuthAPI(),
            sessionStore: store,
            anonymousSessionStore: InMemoryPendingAnonymousSessionStore(),
            linker: AnonymousSessionLinkerStub()
        )

        await service.restoreSession()
        guard case .authenticated(let restoredSession) = service.state else {
            return XCTFail("Expected cached session to remain authenticated")
        }
        XCTAssertEqual(restoredSession.accessToken, "expired-token")
        XCTAssertEqual(store.savedSession?.accessToken, "expired-token")

        let ensuredSession = await service.ensureValidSession(for: .paywall)
        XCTAssertEqual(ensuredSession?.accessToken, "expired-token")
        guard case .authenticated(let ensuredStateSession) = service.state else {
            return XCTFail("Expected cached session to stay authenticated after transient refresh failure")
        }
        XCTAssertEqual(ensuredStateSession.accessToken, "expired-token")
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

    func testBeginAnonymousSessionPreservesExistingPendingIDWhenAuthenticated() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        let pendingID = UUID()
        pendingStore.save(pendingID)
        let service = SupabaseAuthService(
            api: RefreshBlockingAuthAPI(refreshedSession: .fixture),
            sessionStore: InMemoryAuthSessionStore(initial: .fixture),
            anonymousSessionStore: pendingStore,
            linker: AnonymousSessionLinkerStub()
        )

        await service.restoreSession()
        let returnedID = service.beginAnonymousSessionIfNeeded()

        XCTAssertNil(returnedID)
        XCTAssertEqual(pendingStore.load(), pendingID)
    }

    func testSignOutClearsPendingAnonymousSession() async {
        let pendingStore = InMemoryPendingAnonymousSessionStore()
        pendingStore.save(UUID())
        let service = SupabaseAuthService(
            api: RefreshBlockingAuthAPI(refreshedSession: .fixture),
            sessionStore: InMemoryAuthSessionStore(initial: .fixture),
            anonymousSessionStore: pendingStore,
            linker: AnonymousSessionLinkerStub()
        )

        await service.signOut()

        XCTAssertNil(pendingStore.load())
        XCTAssertEqual(service.state, .anonymousEligible)
    }

    private func makeService(initialSession: AuthSession? = nil) -> (SupabaseAuthService, InMemoryAuthSessionStore) {
        let configuration = SupabaseProjectConfiguration(
            projectURL: URL(string: "https://example.test")!,
            anonKey: "anon-key",
            authRedirectURL: URL(string: "https://example.test/auth/v1/callback")!,
            appleServiceID: "com.route25.GirlPower.auth",
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

    private static func profilePayload(
        onboardingCompleted: Bool = false,
        isPro: Bool = false,
        proPlatform: String? = nil
    ) -> Data {
        let platformJSON = proPlatform.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            [
              {
                "id": "user-1",
                "email": "member@example.com",
                "created_at": "2026-03-22T10:00:00Z",
                "updated_at": "2026-03-22T10:05:00Z",
                "is_pro": \(isPro ? "true" : "false"),
                "pro_platform": \(platformJSON),
                "onboarding_completed": \(onboardingCompleted ? "true" : "false"),
                "last_login_at": "2026-03-22T10:05:00Z"
              }
            ]
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
    func linkCurrentDevice(with authSession: AuthSession) async -> CurrentDeviceLinkResult? {
        CurrentDeviceLinkResult(status: "linked", mergedDemoQuotaSnapshot: nil)
    }
}

private actor AuthenticatedDeviceLinkerSpy: AnonymousSessionLinking {
    private let result: CurrentDeviceLinkResult?
    private var sessions: [AuthSession] = []

    init(result: CurrentDeviceLinkResult?) {
        self.result = result
    }

    func linkCurrentDevice(with authSession: AuthSession) async -> CurrentDeviceLinkResult? {
        sessions.append(authSession)
        return result
    }

    func linkedUserIDs() -> [String] {
        sessions.map(\.user.id)
    }
}

private actor ProfileServiceSpy: ProfileServicing {
    private var upsertedSessions: [AuthSession] = []

    func fetchProfile(using session: AuthSession) async throws -> Profile? { nil }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        upsertedSessions.append(session)
        return Profile(
            id: session.user.id,
            email: session.user.email,
            createdAt: Date(),
            updatedAt: Date(),
            isPro: false,
            proPlatform: nil,
            onboardingCompleted: false,
            lastLoginAt: Date()
        )
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        try await upsertProfile(using: session)
    }

    func upsertedUserIDs() -> [String] {
        upsertedSessions.map(\.user.id)
    }
}

private actor BlockingProfileServiceSpy: ProfileServicing {
    private var didStartUpsert = false
    private var completedUpserts = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func fetchProfile(using session: AuthSession) async throws -> Profile? { nil }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        didStartUpsert = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        completedUpserts += 1
        return Profile(
            id: session.user.id,
            email: session.user.email,
            createdAt: Date(),
            updatedAt: Date(),
            isPro: false,
            proPlatform: nil,
            onboardingCompleted: false,
            lastLoginAt: Date()
        )
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        try await upsertProfile(using: session)
    }

    func upsertStarted() -> Bool {
        didStartUpsert
    }

    func completedUpsertCount() -> Int {
        completedUpserts
    }

    func resumeUpsert() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailingProfileServiceSpy: ProfileServicing {
    private var attempts = 0

    func fetchProfile(using session: AuthSession) async throws -> Profile? { nil }

    func upsertProfile(using session: AuthSession) async throws -> Profile {
        attempts += 1
        throw ProfileServiceError.invalidResponse
    }

    func updateOnboardingCompleted(_ completed: Bool, using session: AuthSession) async throws -> Profile {
        throw ProfileServiceError.invalidResponse
    }

    func upsertAttempts() -> Int {
        attempts
    }
}

private actor SuccessfulSignInAuthAPI: SupabaseAuthAPI {
    let session: AuthSession

    init(session: AuthSession) {
        self.session = session
    }

    func signUp(email: String, password: String) async throws -> AuthSession { session }
    func signIn(email: String, password: String) async throws -> AuthSession { session }
    func exchangeAppleIdentityToken(_ identityToken: String, nonce: String) async throws -> AuthSession { session }
    func refresh(refreshToken: String) async throws -> AuthSession { session }
}

private actor SuccessfulRefreshAuthAPI: SupabaseAuthAPI {
    let refreshedSession: AuthSession

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
        refreshedSession
    }
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

private actor RefreshNetworkFailingAuthAPI: SupabaseAuthAPI {
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
        throw SupabaseAuthAPIError.networkUnavailable
    }
}

private struct FakeDeviceIdentityProvider: DeviceIdentityProviding {
    let uuid: UUID

    func deviceID() async throws -> UUID { uuid }
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

private extension JSONDecoder {
    static var profileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension URLRequest {
    func bodyData() -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }
}
