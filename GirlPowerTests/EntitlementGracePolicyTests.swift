import XCTest
@testable import GirlPower

final class EntitlementGracePolicyTests: XCTestCase {
    func testEffectiveIsProTrueWhenSubscribedEvenWithoutSnapshot() {
        let policy = EntitlementGracePolicy(
            isSubscribed: true,
            hasValidatedSnapshot: false,
            revalidationGraceDeadline: nil
        )

        XCTAssertTrue(policy.effectiveIsPro(now: Date()))
    }

    func testEffectiveIsProTrueWhenSnapshotExistsAndDeadlineInFuture() {
        let now = Date(timeIntervalSince1970: 100)
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: true,
            revalidationGraceDeadline: now.addingTimeInterval(5)
        )

        XCTAssertTrue(policy.effectiveIsPro(now: now))
    }

    func testEffectiveIsProFalseWhenGraceDeadlineExpires() {
        let now = Date(timeIntervalSince1970: 100)
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: true,
            revalidationGraceDeadline: now
        )

        XCTAssertFalse(policy.effectiveIsPro(now: now))
    }

    func testEffectiveIsProFalseWithoutValidatedSnapshot() {
        let policy = EntitlementGracePolicy(
            isSubscribed: false,
            hasValidatedSnapshot: false,
            revalidationGraceDeadline: Date().addingTimeInterval(10)
        )

        XCTAssertFalse(policy.effectiveIsPro(now: Date()))
    }

    func testGraceDeadlineReturnsNilWhenSnapshotMissing() {
        let deadline = EntitlementGracePolicy.graceDeadline(
            hasValidatedSnapshot: false,
            now: Date(timeIntervalSince1970: 1),
            gracePeriod: 10
        )

        XCTAssertNil(deadline)
    }

    func testGraceDeadlineOffsetsByConfiguredPeriod() {
        let now = Date(timeIntervalSince1970: 100)
        let deadline = EntitlementGracePolicy.graceDeadline(
            hasValidatedSnapshot: true,
            now: now,
            gracePeriod: 12
        )

        XCTAssertEqual(deadline, now.addingTimeInterval(12))
    }
}

@MainActor
final class StoreKitAuthContextTests: XCTestCase {
    func testAuthenticatedProfileFallbackSetsIsProWhenProfileReportsPro() async {
        let service = StoreKitEntitlementService(
            productIDs: ["girlpower.pro.monthly"],
            snapshotStore: InMemoryEntitlementSnapshotStore()
        )

        XCTAssertFalse(service.isPro)

        await service.updateAuthenticatedContext(session: .fixture, profile: .proFixture)

        XCTAssertTrue(service.isPro)
    }

    func testClearingAuthenticatedSessionRemovesProfileFallback() async {
        let service = StoreKitEntitlementService(
            productIDs: ["girlpower.pro.monthly"],
            snapshotStore: InMemoryEntitlementSnapshotStore()
        )

        await service.updateAuthenticatedContext(session: .fixture, profile: .proFixture)
        XCTAssertTrue(service.isPro)

        await service.updateAuthenticatedContext(session: nil, profile: nil)

        XCTAssertFalse(service.isPro)
    }
}

private final class InMemoryEntitlementSnapshotStore: EntitlementSnapshotPersisting {
    private var snapshot: EntitlementSnapshot?

    init(snapshot: EntitlementSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() -> EntitlementSnapshot? {
        snapshot
    }

    func save(_ snapshot: EntitlementSnapshot) {
        self.snapshot = snapshot
    }

    func clear() {
        snapshot = nil
    }
}

private extension AuthSession {
    static var fixture: AuthSession {
        AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            user: AuthUser(id: "user-1", email: "member@example.com")
        )
    }
}

private extension Profile {
    static var proFixture: Profile {
        let now = Date(timeIntervalSince1970: 1)
        return Profile(
            id: "user-1",
            email: "member@example.com",
            createdAt: now,
            updatedAt: now,
            isPro: true,
            proPlatform: .apple,
            onboardingCompleted: false,
            lastLoginAt: now
        )
    }
}
